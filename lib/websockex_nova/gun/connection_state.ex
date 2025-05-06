defmodule WebsockexNova.Gun.ConnectionState do
  @moduledoc """
  State structure for ConnectionWrapper.

  This module defines the state structure used by the ConnectionWrapper,
  providing better type safety and organization of state data.

  ## IMPORTANT: State Layering
  This struct should ONLY contain transport-layer, process-local, or Gun-specific data.
  It should NOT store canonical application-level state like:
  - Authentication
  - Subscriptions
  - User credentials
  - Application handler state

  The canonical application state lives in `WebsockexNova.ClientConn`.
  This struct may reference a ClientConn struct for operations, but should
  never duplicate the canonical state.

  ## Reconnection Policy
  - The connection state no longer tracks reconnection attempts or delays.
  - All reconnection policy and tracking is handled by the error handler.
  """

  require Logger

  @typedoc "Connection status"
  @type status ::
          :initialized
          | :connecting
          | :connected
          | :websocket_connected
          | :disconnected
          | :reconnecting
          | :error
          | :closed

  @typedoc "Connection state structure"
  @type t :: %__MODULE__{
          # Gun/Transport process state (local to this process)
          gun_pid: pid() | nil,
          gun_monitor_ref: reference() | nil,

          # Connection configuration (duplicated from ClientConn for easy access)
          # These are read-only once set
          host: String.t(),
          port: non_neg_integer(),
          transport: atom(),
          path: String.t(),
          ws_opts: map(),

          # Local process state
          status: status(),
          options: map(),
          callback_pid: pid() | nil,
          last_error: term() | nil,
          active_streams: %{reference() => map()},

          # Handler module references - should only store the module names, not the state
          handlers: %{
            optional(:connection_handler) => module(),
            optional(:message_handler) => module(),
            optional(:error_handler) => module(),
            optional(:logging_handler) => module(),
            optional(:subscription_handler) => module(),
            optional(:auth_handler) => module(),
            optional(:rate_limit_handler) => module(),
            optional(:metrics_collector) => module()
          }
        }

  defstruct [
    # Gun/Transport process state
    :gun_pid,
    :gun_monitor_ref,

    # Connection configuration (duplicated from ClientConn for local usage)
    :host,
    :port,
    :transport,
    :path,
    :ws_opts,

    # Local process state
    :status,
    :options,
    :callback_pid,
    :last_error,
    active_streams: %{},

    # Handler module references only, not state
    handlers: %{}
  ]

  @doc """
  Creates a new connection state.

  ## Parameters

  * `host` - The hostname to connect to
  * `port` - The port to connect to
  * `options` - Connection options (only transport configuration is stored)

  ## Returns

  A new connection state struct
  """
  @spec new(String.t(), non_neg_integer(), map()) :: t()
  def new(host, port, options) do
    transport_options = filter_transport_options(options)

    %__MODULE__{
      # Gun/transport state
      gun_pid: nil,
      gun_monitor_ref: nil,

      # Connection configuration
      host: host,
      port: port,
      transport: Map.get(transport_options, :transport, :tcp),
      path: Map.get(transport_options, :path, "/ws"),
      ws_opts: Map.get(transport_options, :ws_opts, %{}),

      # Local process state
      status: :initialized,
      options: transport_options,
      callback_pid: Map.get(transport_options, :callback_pid),
      active_streams: %{},
      last_error: nil,

      # Handler module references
      handlers: extract_handler_modules(transport_options)
    }
  end

  # Only allow transport config keys in options
  @transport_option_keys [
    :host,
    :port,
    :transport,
    :path,
    :ws_opts,
    :protocols,
    :transport_opts,
    :retry,
    :backoff_type,
    :base_backoff,
    :callback_pid,
    :headers,
    :rate_limiter
  ]
  defp filter_transport_options(options) do
    Map.take(options, @transport_option_keys)
  end

  # Extract only handler module names from options, not their state
  defp extract_handler_modules(options) do
    %{}
    |> maybe_add_handler(:connection_handler, Map.get(options, :connection_handler))
    |> maybe_add_handler(:message_handler, Map.get(options, :message_handler))
    |> maybe_add_handler(:error_handler, Map.get(options, :error_handler))
    |> maybe_add_handler(:logging_handler, Map.get(options, :logging_handler))
    |> maybe_add_handler(:subscription_handler, Map.get(options, :subscription_handler))
    |> maybe_add_handler(:auth_handler, Map.get(options, :auth_handler))
    |> maybe_add_handler(:rate_limit_handler, Map.get(options, :rate_limit_handler))
    |> maybe_add_handler(:metrics_collector, Map.get(options, :metrics_collector))
  end

  defp maybe_add_handler(map, _key, nil), do: map
  defp maybe_add_handler(map, key, module), do: Map.put(map, key, module)

  @doc """
  Updates the connection status in the state.

  ## Parameters

  * `state` - Current connection state
  * `status` - New status to set

  ## Returns

  Updated connection state struct
  """
  @spec update_status(t(), status()) :: t()
  def update_status(state, status) do
    %{state | status: status}
  end

  @doc """
  Sets up the connection handler module and stores it in the handlers map.

  ## Parameters

  * `state` - Current connection state
  * `connection_handler` - Connection handler module
  * `options` - Handler options (not stored in ConnectionState)

  ## Returns

  Updated connection state struct
  """
  @spec setup_connection_handler(t(), module(), map()) :: t()
  def setup_connection_handler(state, connection_handler, options) do
    {_, handler_state} =
      case connection_handler.init(options) do
        {:ok, handler_state} -> {:ok, handler_state}
        other -> {other, %{}}
      end

    state
    |> update_handler(:connection_handler, connection_handler)
    |> then(fn s ->
      %{s | handlers: Map.put(s.handlers, :connection_handler_state, handler_state)}
    end)
  end

  @doc """
  Sets up the message handler module and stores it in the handlers map.

  ## Parameters

  * `state` - Current connection state
  * `message_handler` - Message handler module
  * `options` - Handler options (not stored in ConnectionState)

  ## Returns

  Updated connection state struct
  """
  @spec setup_message_handler(t(), module(), map()) :: t()
  def setup_message_handler(state, message_handler, _options) do
    update_handler(state, :message_handler, message_handler)
  end

  @doc """
  Sets up the error handler module and stores it in the handlers map.

  ## Parameters

  * `state` - Current connection state
  * `error_handler` - Error handler module
  * `options` - Handler options (not stored in ConnectionState)

  ## Returns

  Updated connection state struct
  """
  @spec setup_error_handler(t(), module(), map()) :: t()
  def setup_error_handler(state, error_handler, _options) do
    update_handler(state, :error_handler, error_handler)
  end

  @doc """
  Sets up the subscription handler module and stores it in the handlers map.

  ## Parameters

  * `state` - Current connection state
  * `subscription_handler` - Subscription handler module
  * `options` - Handler options (not stored in ConnectionState)

  ## Returns

  Updated connection state struct
  """
  @spec setup_subscription_handler(t(), module(), map()) :: t()
  def setup_subscription_handler(state, subscription_handler, options) do
    {_, handler_state} =
      case subscription_handler.subscription_init(options) do
        {:ok, handler_state} -> {:ok, handler_state}
        other -> {other, %{}}
      end

    state
    |> update_handler(:subscription_handler, subscription_handler)
    |> then(fn s ->
      %{s | handlers: Map.put(s.handlers, :subscription_handler_state, handler_state)}
    end)
  end

  @doc """
  Sets up the auth handler module and stores it in the handlers map.

  ## Parameters

  * `state` - Current connection state
  * `auth_handler` - Auth handler module
  * `options` - Handler options (not stored in ConnectionState)

  ## Returns

  Updated connection state struct
  """
  @spec setup_auth_handler(t(), module(), map()) :: t()
  def setup_auth_handler(state, auth_handler, _options) do
    handler_state = %{}

    state
    |> update_handler(:auth_handler, auth_handler)
    |> then(fn s -> %{s | handlers: Map.put(s.handlers, :auth_handler_state, handler_state)} end)
  end

  @doc """
  Adds an active stream to the state with the given status and data.

  ## Parameters

  * `state` - Current connection state
  * `stream_ref` - Stream reference to add
  * `stream_data` - Data for the stream, can be either an atom status or a map with data

  ## Returns

  Updated connection state struct
  """
  @spec add_active_stream(t(), reference(), atom() | map()) :: t()
  def add_active_stream(state, stream_ref, stream_data) do
    updated_streams = Map.put(state.active_streams, stream_ref, stream_data)
    %{state | active_streams: updated_streams}
  end

  @doc """
  Removes multiple streams from the active streams map.

  ## Parameters

  * `state` - Current connection state
  * `stream_refs` - List of stream references to remove

  ## Returns

  Updated connection state struct
  """
  @spec remove_streams(t(), list(reference())) :: t()
  def remove_streams(state, stream_refs) when is_list(stream_refs) do
    updated_streams =
      Enum.reduce(stream_refs, state.active_streams, fn ref, acc ->
        Map.delete(acc, ref)
      end)

    %{state | active_streams: updated_streams}
  end

  @doc """
  Clears all active streams from the state.

  ## Parameters

  * `state` - Current connection state

  ## Returns

  Updated connection state struct with empty active_streams
  """
  @spec clear_all_streams(t()) :: t()
  def clear_all_streams(state) do
    %{state | active_streams: %{}}
  end

  @doc """
  Prepares the state for process termination by clearing references and resources.

  ## Parameters

  * `state` - Current connection state

  ## Returns

  Updated connection state ready for termination
  """
  @spec prepare_for_termination(t()) :: t()
  def prepare_for_termination(state) do
    state
    |> clear_all_streams()
    |> update_gun_pid(nil)
    |> update_gun_monitor_ref(nil)
    |> update_status(:closed)
  end

  @doc """
  Updates the Gun connection PID in the state.

  ## Parameters

  * `state` - Current connection state
  * `gun_pid` - The Gun connection process PID

  ## Returns

  Updated connection state struct
  """
  @spec update_gun_pid(t(), pid() | nil) :: t()
  def update_gun_pid(state, gun_pid) do
    %{state | gun_pid: gun_pid}
  end

  @doc """
  Updates the Gun connection monitor reference in the state.

  ## Parameters

  * `state` - Current connection state
  * `monitor_ref` - Monitor reference for the Gun process

  ## Returns

  Updated connection state struct
  """
  @spec update_gun_monitor_ref(t(), reference() | nil) :: t()
  def update_gun_monitor_ref(state, monitor_ref) do
    %{state | gun_monitor_ref: monitor_ref}
  end

  @doc """
  Records an error in the state.

  ## Parameters

  * `state` - Current connection state
  * `error` - Error to record

  ## Returns

  Updated connection state struct
  """
  @spec record_error(t(), term()) :: t()
  def record_error(state, error) do
    %{state | last_error: error}
  end

  @doc """
  Updates or adds a stream in the active streams map.

  ## Parameters

  * `state` - Current connection state
  * `stream_ref` - Stream reference
  * `status` - Stream status

  ## Returns

  Updated connection state struct
  """
  @spec update_stream(t(), reference(), atom()) :: t()
  def update_stream(state, stream_ref, status) do
    updated_streams = Map.put(state.active_streams, stream_ref, status)
    %{state | active_streams: updated_streams}
  end

  @doc """
  Removes a stream from the active streams map.

  ## Parameters

  * `state` - Current connection state
  * `stream_ref` - Stream reference to remove

  ## Returns

  Updated connection state struct
  """
  @spec remove_stream(t(), reference()) :: t()
  def remove_stream(state, stream_ref) do
    updated_streams = Map.delete(state.active_streams, stream_ref)
    %{state | active_streams: updated_streams}
  end

  @doc """
  Updates the active streams map.

  ## Parameters

  * `state` - Current connection state
  * `active_streams` - Map of stream references to stream data

  ## Returns

  Updated connection state struct
  """
  @spec update_active_streams(t(), map()) :: t()
  def update_active_streams(state, active_streams) when is_map(active_streams) do
    %{state | active_streams: active_streams}
  end

  @doc """
  Updates a handler module reference.

  ## Parameters

  * `state` - Current connection state
  * `handler_key` - Key for the handler (:connection_handler, :message_handler, etc.)
  * `module` - Handler module

  ## Returns

  Updated connection state struct
  """
  @spec update_handler(t(), atom(), module()) :: t()
  def update_handler(state, handler_key, module) do
    updated_handlers = Map.put(state.handlers, handler_key, module)
    %{state | handlers: updated_handlers}
  end

  @doc """
  Updates multiple handlers at once in the handlers map.

  ## Parameters

  * `state` - Current connection state
  * `handlers` - Map of handler keys to handler modules or state

  ## Returns

  Updated connection state struct
  """
  @spec update_handlers(t(), map()) :: t()
  def update_handlers(state, handlers) when is_map(handlers) do
    updated_handlers = Map.merge(state.handlers || %{}, handlers)
    %{state | handlers: updated_handlers}
  end

  @doc """
  Updates the connection handler state within the handlers map.

  ## Parameters

  * `state` - Current connection state
  * `handler_state` - New handler state to store

  ## Returns

  Updated connection state struct
  """
  @spec update_connection_handler_state(t(), any()) :: t()
  def update_connection_handler_state(state, handler_state) do
    updated_handlers = Map.put(state.handlers, :connection_handler_state, handler_state)
    %{state | handlers: updated_handlers}
  end

  @doc """
  Setup the logging handler module.

  ## Parameters

  * `state` - Current connection state
  * `logging_handler` - Logging handler module
  * `_options` - Logging handler options (not stored in ConnectionState)

  ## Returns

  Updated connection state struct
  """
  @spec setup_logging_handler(t(), module(), map()) :: t()
  def setup_logging_handler(state, logging_handler, _options) do
    # Note: handler state/options are stored in ClientConn, not here
    update_handler(state, :logging_handler, logging_handler)
  end

  @doc """
  Gets the callback PID from the state.

  ## Parameters

  * `state` - Current connection state

  ## Returns

  The callback PID, or nil if none exists
  """
  @spec get_callback_pid(t()) :: pid() | nil
  def get_callback_pid(state) do
    state.callback_pid
  end

  @doc """
  Updates the callback PID in the state.

  ## Parameters

  * `state` - Current connection state
  * `pid` - New callback PID

  ## Returns

  Updated connection state struct
  """
  @spec update_callback_pid(t(), pid() | nil) :: t()
  def update_callback_pid(state, pid) do
    %{state | callback_pid: pid}
  end
end
