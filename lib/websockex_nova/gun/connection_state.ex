defmodule WebsockexNova.Gun.ConnectionState do
  @moduledoc """
  State structure for ConnectionWrapper.

  This module defines the state structure used by the ConnectionWrapper,
  providing better type safety and organization of state data.
  """

  alias WebsockexNova.Gun.ConnectionWrapper

  @typedoc "Connection state structure"
  @type t :: %__MODULE__{
          gun_pid: pid() | nil,
          gun_monitor_ref: reference() | nil,
          host: String.t(),
          port: non_neg_integer(),
          transport: atom(),
          path: String.t(),
          ws_opts: map(),
          status: ConnectionWrapper.status(),
          options: map(),
          callback_pid: pid() | nil,
          last_error: term() | nil,
          active_streams: %{reference() => map()},
          reconnect_attempts: non_neg_integer(),
          handlers: %{
            optional(:connection_handler) => module(),
            optional(:connection_handler_state) => term(),
            optional(:message_handler) => module(),
            optional(:message_handler_state) => term(),
            optional(:error_handler) => module(),
            optional(:error_handler_state) => term(),
            optional(:logging_handler) => module(),
            optional(:logging_handler_state) => term(),
            optional(:subscription_handler) => module(),
            optional(:subscription_handler_state) => term(),
            optional(:auth_handler) => module(),
            optional(:auth_handler_state) => term()
          }
        }

  defstruct [
    :gun_pid,
    :gun_monitor_ref,
    :host,
    :port,
    :transport,
    :path,
    :ws_opts,
    :status,
    :options,
    :callback_pid,
    :last_error,
    active_streams: %{},
    reconnect_attempts: 0,
    handlers: %{}
  ]

  @doc """
  Creates a new connection state.

  ## Parameters

  * `host` - The hostname to connect to
  * `port` - The port to connect to
  * `options` - Connection options

  ## Returns

  A new connection state struct
  """
  @spec new(String.t(), non_neg_integer(), map()) :: t()
  def new(host, port, options) do
    %__MODULE__{
      host: host,
      port: port,
      status: :initialized,
      options: options,
      callback_pid: Map.get(options, :callback_pid),
      active_streams: %{}
    }
  end

  @doc """
  Updates the connection status in the state.

  ## Parameters

  * `state` - Current connection state
  * `status` - New status to set

  ## Returns

  Updated connection state struct
  """
  @spec update_status(t(), ConnectionWrapper.status()) :: t()
  def update_status(state, status) do
    %{state | status: status}
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
    %{state | active_streams: Map.put(state.active_streams, stream_ref, status)}
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
    %{state | active_streams: Map.delete(state.active_streams, stream_ref)}
  end

  @doc """
  Removes multiple streams from the active streams map.

  ## Parameters

  * `state` - Current connection state
  * `stream_refs` - List of stream references to remove

  ## Returns

  Updated connection state struct
  """
  @spec remove_streams(t(), [reference()]) :: t()
  def remove_streams(state, stream_refs) when is_list(stream_refs) do
    active_streams =
      Enum.reduce(stream_refs, state.active_streams, fn ref, streams ->
        Map.delete(streams, ref)
      end)

    %{state | active_streams: active_streams}
  end

  @doc """
  Clears all active streams.

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
  Increments the reconnection attempt counter.

  ## Parameters

  * `state` - Current connection state

  ## Returns

  Updated connection state struct
  """
  @spec increment_reconnect_attempts(t()) :: t()
  def increment_reconnect_attempts(state) do
    %{state | reconnect_attempts: state.reconnect_attempts + 1}
  end

  @doc """
  Resets the reconnection attempt counter.

  ## Parameters

  * `state` - Current connection state

  ## Returns

  Updated connection state struct
  """
  @spec reset_reconnect_attempts(t()) :: t()
  def reset_reconnect_attempts(state) do
    %{state | reconnect_attempts: 0}
  end

  @doc """
  Updates the entire active_streams map.

  ## Parameters

  * `state` - Current connection state
  * `active_streams` - New active streams map to replace the existing one

  ## Returns

  Updated connection state struct
  """
  @spec update_active_streams(t(), %{reference() => atom()}) :: t()
  def update_active_streams(state, active_streams) when is_map(active_streams) do
    %{state | active_streams: active_streams}
  end

  @doc """
  Prepares state for cleanup before termination.
  Clears all active streams and references.

  ## Parameters

  * `state` - Current connection state

  ## Returns

  Cleaned up state struct
  """
  @spec prepare_for_termination(t()) :: t()
  def prepare_for_termination(state) do
    state
    |> clear_all_streams()
    |> Map.put(:gun_pid, nil)
  end

  @doc """
  Sets up the connection handler and initializes its state.

  ## Parameters

  * `state` - Current connection state
  * `handler_module` - The connection handler module to use
  * `handler_options` - Options to pass to the handler's init/1 function

  ## Returns

  Updated connection state struct with the handler and its state
  """
  @spec setup_connection_handler(t(), module(), map()) :: t()
  def setup_connection_handler(state, handler_module, handler_options) when is_atom(handler_module) do
    case handler_module.init(handler_options) do
      {:ok, handler_state} ->
        %{
          state
          | handlers:
              Map.merge(state.handlers, %{
                connection_handler: handler_module,
                connection_handler_state: handler_state
              })
        }

      # If init returns an error, we'll still set the handler but with nil state
      _error ->
        %{
          state
          | handlers:
              Map.merge(state.handlers, %{
                connection_handler: handler_module,
                connection_handler_state: nil
              })
        }
    end
  end

  @doc """
  Updates the connection handler state.

  ## Parameters

  * `state` - Current connection state
  * `handler_state` - New handler state

  ## Returns

  Updated connection state struct
  """
  @spec update_connection_handler_state(t(), term()) :: t()
  def update_connection_handler_state(state, handler_state) do
    %{state | handlers: Map.put(state.handlers, :connection_handler_state, handler_state)}
  end

  @doc """
  Sets up the message handler and initializes its state.

  ## Parameters

  * `state` - Current connection state
  * `handler_module` - The message handler module to use
  * `handler_options` - Options to pass to the handler's init/1 function

  ## Returns

  Updated connection state struct with the handler and its state
  """
  @spec setup_message_handler(t(), module(), map()) :: t()
  def setup_message_handler(state, handler_module, handler_options) when is_atom(handler_module) do
    case handler_module.init(handler_options) do
      {:ok, handler_state} ->
        %{
          state
          | handlers:
              Map.merge(state.handlers, %{
                message_handler: handler_module,
                message_handler_state: handler_state
              })
        }

      # If init returns an error, we'll still set the handler but with nil state
      _error ->
        %{
          state
          | handlers:
              Map.merge(state.handlers, %{
                message_handler: handler_module,
                message_handler_state: nil
              })
        }
    end
  end

  @doc """
  Updates the message handler state.

  ## Parameters

  * `state` - Current connection state
  * `handler_state` - New handler state

  ## Returns

  Updated connection state struct
  """
  @spec update_message_handler_state(t(), term()) :: t()
  def update_message_handler_state(state, handler_state) do
    %{state | handlers: Map.put(state.handlers, :message_handler_state, handler_state)}
  end

  @doc """
  Sets up the error handler and initializes its state.

  ## Parameters

  * `state` - Current connection state
  * `handler_module` - The error handler module to use
  * `handler_options` - Options to pass to the handler's init/1 function

  ## Returns

  Updated connection state struct with the handler and its state
  """
  @spec setup_error_handler(t(), module(), map()) :: t()
  def setup_error_handler(state, handler_module, handler_options) when is_atom(handler_module) do
    case handler_module.init(handler_options) do
      {:ok, handler_state} ->
        %{
          state
          | handlers:
              Map.merge(state.handlers, %{
                error_handler: handler_module,
                error_handler_state: handler_state
              })
        }

      # If init returns an error, we'll still set the handler but with nil state
      _error ->
        %{
          state
          | handlers:
              Map.merge(state.handlers, %{
                error_handler: handler_module,
                error_handler_state: nil
              })
        }
    end
  end

  @doc """
  Updates the error handler state.

  ## Parameters

  * `state` - Current connection state
  * `handler_state` - New handler state

  ## Returns

  Updated connection state struct
  """
  @spec update_error_handler_state(t(), term()) :: t()
  def update_error_handler_state(state, handler_state) do
    %{state | handlers: Map.put(state.handlers, :error_handler_state, handler_state)}
  end

  @doc """
  Updates the entire handlers map.

  ## Parameters

  * `state` - Current connection state
  * `handlers` - New handlers map to replace or merge with the existing one

  ## Returns

  Updated connection state struct
  """
  @spec update_handlers(t(), map()) :: t()
  def update_handlers(state, handlers) when is_map(handlers) do
    %{state | handlers: handlers}
  end

  @doc """
  Adds a stream to the active streams map with metadata.

  ## Parameters

  * `state` - Current connection state
  * `stream_ref` - Stream reference
  * `metadata` - Map of metadata about the stream

  ## Returns

  Updated connection state struct
  """
  @spec add_active_stream(t(), reference(), map()) :: t()
  def add_active_stream(state, stream_ref, metadata) when is_map(metadata) do
    %{state | active_streams: Map.put(state.active_streams, stream_ref, metadata)}
  end

  @doc """
  Sets up the logging handler and initializes its state.

  ## Parameters

  * `state` - Current connection state
  * `handler_module` - The logging handler module to use
  * `handler_options` - Options to pass to the handler's init/1 function

  ## Returns

  Updated connection state struct with the handler and its state
  """
  @spec setup_logging_handler(t(), module(), map()) :: t()
  def setup_logging_handler(state, handler_module, handler_options) when is_atom(handler_module) do
    case handler_module.init(handler_options) do
      {:ok, handler_state} ->
        %{
          state
          | handlers:
              Map.merge(state.handlers, %{
                logging_handler: handler_module,
                logging_handler_state: handler_state
              })
        }

      # If init returns an error, we'll still set the handler but with nil state
      _error ->
        %{
          state
          | handlers:
              Map.merge(state.handlers, %{
                logging_handler: handler_module,
                logging_handler_state: nil
              })
        }
    end
  end

  @doc """
  Sets up the subscription handler and initializes its state.

  ## Parameters
  * `state` - Current connection state
  * `handler_module` - The subscription handler module to use
  * `handler_options` - Options to pass to the handler's init/1 function

  ## Returns
  Updated connection state struct with the handler and its state
  """
  @spec setup_subscription_handler(t(), module(), map()) :: t()
  def setup_subscription_handler(state, handler_module, handler_options) when is_atom(handler_module) do
    case handler_module.init(handler_options) do
      {:ok, handler_state} ->
        %{
          state
          | handlers:
              Map.merge(state.handlers, %{
                subscription_handler: handler_module,
                subscription_handler_state: handler_state
              })
        }

      _error ->
        %{
          state
          | handlers:
              Map.merge(state.handlers, %{
                subscription_handler: handler_module,
                subscription_handler_state: nil
              })
        }
    end
  end

  @doc """
  Sets up the auth handler and initializes its state.

  ## Parameters
  * `state` - Current connection state
  * `handler_module` - The auth handler module to use
  * `handler_options` - Options to pass to the handler's init/1 function

  ## Returns
  Updated connection state struct with the handler and its state
  """
  @spec setup_auth_handler(t(), module(), map()) :: t()
  def setup_auth_handler(state, handler_module, handler_options) when is_atom(handler_module) do
    case handler_module.init(handler_options) do
      {:ok, handler_state} ->
        %{
          state
          | handlers:
              Map.merge(state.handlers, %{
                auth_handler: handler_module,
                auth_handler_state: handler_state
              })
        }

      _error ->
        %{
          state
          | handlers:
              Map.merge(state.handlers, %{
                auth_handler: handler_module,
                auth_handler_state: nil
              })
        }
    end
  end
end
