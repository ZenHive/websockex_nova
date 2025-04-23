defmodule WebsockexNova.Gun.ConnectionWrapper do
  @moduledoc """
  A thin adapter over Gun's WebSocket implementation, providing a standardized API.

  ## Thin Adapter Pattern

  This module implements the "thin adapter" architectural pattern by:

  1. **Abstracting Gun's API**: Provides a simpler, more standardized interface over Gun's
     lower-level functionality while maintaining full access to Gun's capabilities

  2. **Minimizing Logic**: Acts primarily as a pass-through to the underlying Gun library,
     with minimal logic in the adapter itself

  3. **Delegating Business Logic**: Forwards most decisions to specialized modules like
     ConnectionManager and behavior callbacks

  4. **Standardizing Interfaces**: Exposes a consistent API regardless of underlying
     transport implementation details

  This pattern allows WebsockexNova to potentially support different transport layers
  in the future while maintaining a consistent API for client applications.

  ## Architecture

  ConnectionWrapper uses a clean architecture with strict separation of concerns:

  * **Core ConnectionWrapper**: Minimal GenServer implementation that routes messages
  * **ConnectionState**: Immutable state management with structured updates
  * **ConnectionManager**: Business logic for connection lifecycle and state transitions
  * **MessageHandlers**: Specialized handlers for different Gun message types
  * **BehaviorHelpers**: Consistent delegation to behavior callbacks
  * **ErrorHandler**: Standardized error handling patterns

  ## Delegation Pattern

  The module employs a standardized multi-level delegation pattern:

  1. **Layer 1**: GenServer callbacks receive Gun messages
     ```elixir
     def handle_info({:gun_ws, gun_pid, stream_ref, frame}, %{gun_pid: gun_pid} = state) do
       MessageHandlers.handle_websocket_frame(gun_pid, stream_ref, frame, state)
     end
     ```

  2. **Layer 2**: Messages are delegated to specialized MessageHandlers
     ```elixir
     # In MessageHandlers module
     def handle_websocket_frame(gun_pid, stream_ref, frame, state) do
       # Process frame, then call behavior callbacks through BehaviorHelpers
       BehaviorHelpers.call_handle_frame(state, frame_type, frame_data, stream_ref)
     end
     ```

  3. **Layer 3**: MessageHandlers call behavior callbacks through BehaviorHelpers
     ```elixir
     # In BehaviorHelpers module
     def call_handle_frame(state, frame_type, frame_data, stream_ref) do
       handler_module = Map.get(state.handlers, :connection_handler)
       handler_state = Map.get(state.handlers, :connection_handler_state)
       handler_module.handle_frame(frame_type, frame_data, handler_state)
     end
     ```

  4. **Layer 4**: Results are processed through a consistent handler
     ```elixir
     # Back in ConnectionWrapper
     def process_handler_result({:reply, frame_type, data, state, stream_ref}) do
       :gun.ws_send(state.gun_pid, stream_ref, {frame_type, data})
       {:noreply, state}
     end
     ```

  ## Ownership Model

  Gun connections have a specific ownership model where only one process receives
  messages from a Gun connection. This module provides a complete ownership
  transfer protocol:

  ```elixir
  # Process A - Current owner of Gun connection
  WebsockexNova.Gun.ConnectionWrapper.transfer_ownership(wrapper_pid, target_pid)

  # Process B - Receiving ownership
  WebsockexNova.Gun.ConnectionWrapper.receive_ownership(wrapper_pid, gun_pid)
  ```

  The transfer protocol carefully manages process monitors, message routing, and state
  synchronization to ensure reliable handoff between processes.

  ## Usage Examples

  ### Basic Connection

  ```elixir
  # Open a connection
  {:ok, conn} = WebsockexNova.Gun.ConnectionWrapper.open("example.com", 443, %{
    transport: :tls,
    callback_handler: MyApp.WebSocketHandler
  })

  # Upgrade to WebSocket
  {:ok, stream_ref} = WebsockexNova.Gun.ConnectionWrapper.upgrade_to_websocket(conn, "/ws")

  # Send a frame
  WebsockexNova.Gun.ConnectionWrapper.send_frame(conn, stream_ref, {:text, ~s({"type": "ping"})})
  ```

  ### With Custom Handlers

  ```elixir
  # Configure with custom handlers
  {:ok, conn} = WebsockexNova.Gun.ConnectionWrapper.open("example.com", 443, %{
    transport: :tls,
    callback_handler: MyApp.ConnectionHandler,
    message_handler: MyApp.MessageHandler,
    error_handler: MyApp.ErrorHandler
  })
  ```

  ### Process Transfer

  ```elixir
  # In process A (current owner)
  {:ok, conn} = WebsockexNova.Gun.ConnectionWrapper.open("example.com", 443)
  WebsockexNova.Gun.ConnectionWrapper.transfer_ownership(conn, process_b_pid)

  # In process B (new owner)
  WebsockexNova.Gun.ConnectionWrapper.receive_ownership(my_wrapper_pid, gun_pid)
  ```
  """

  # @behaviour WebsockexNova.ConnectionWrapperBehaviour
  @behaviour WebsockexNova.Transport

  use GenServer

  alias WebsockexNova.Gun.ConnectionManage
  alias WebsockexNova.Gun.ConnectionManager
  alias WebsockexNova.Gun.ConnectionOptions
  alias WebsockexNova.Gun.ConnectionState
  alias WebsockexNova.Gun.ConnectionWrapper.ErrorHandler
  alias WebsockexNova.Gun.ConnectionWrapper.MessageHandlers
  alias WebsockexNova.Gun.Helpers
  alias WebsockexNova.Helpers.StateHelpers
  alias WebsockexNova.Telemetry.TelemetryEvents
  alias WebsockexNova.Transport.RateLimiting

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

  @typedoc "WebSocket frame types"
  @type frame ::
          {:text, binary}
          | {:binary, binary}
          | :ping
          | :pong
          | :close
          | {:close, non_neg_integer(), binary}

  @typedoc """
  Options for connection wrapper

  ## Possible error atoms returned by API functions:
  - :not_connected — The connection is not established or Gun process is missing
  - :stream_not_found — The provided stream reference does not exist or is closed
  - :no_gun_pid — No Gun process is available for ownership transfer
  - :invalid_target_process — The target process for ownership transfer is invalid or dead
  - :gun_process_not_alive — The Gun process is no longer alive
  - :invalid_gun_pid — The provided Gun PID is invalid or dead
  - :http_error — HTTP upgrade or response error (see tuple for details)
  - :invalid_stream_status — The stream is not in a valid state for the requested operation
  - :terminal_error — A terminal error occurred, preventing reconnection
  - :transition_error — State machine transition failed
  - :reconnect_failed — Reconnection attempt failed
  """
  @type options :: %{
          optional(:transport) => :tcp | :tls,
          optional(:transport_opts) => Keyword.t(),
          optional(:protocols) => [:http | :http2 | :socks | :ws],
          optional(:retry) => non_neg_integer() | :infinity,
          optional(:callback_pid) => pid(),
          optional(:ws_opts) => map(),
          optional(:backoff_type) => :linear | :exponential | :jittered,
          optional(:base_backoff) => non_neg_integer(),
          optional(:callback_handler) => module(),
          optional(:message_handler) => module(),
          optional(:error_handler) => module(),
          optional(:rate_limiter) => module()
        }

  # Client API

  @doc """
  Opens a connection to a WebSocket server and upgrades to WebSocket in one step.

  ## Parameters

  * `host` - Hostname or IP address of the server
  * `port` - Port number of the server (default: 80, or 443 for TLS)
  * `path` - WebSocket endpoint path
  * `options` - Connection options (see `t:options/0`)

  ## Returns

  * `{:ok, %WebsockexNova.ClientConn{}}` on success
  * `{:error, reason}` on failure
  """
  @spec open(binary(), pos_integer(), binary(), options()) :: {:ok, WebsockexNova.ClientConn.t()} | {:error, term()}
  @impl WebsockexNova.Transport
  def open(host, port, path, options \\ %{}) do
    # Start the connection process
    case GenServer.start_link(__MODULE__, {host, port, options, nil}) do
      {:ok, pid} ->
        # Wait for connection to be established
        status = wait_for_status(pid, :connected, Map.get(options, :timeout, 5000))

        if status == :connected do
          headers = Map.get(options, :headers, [])
          # Perform WebSocket upgrade
          case GenServer.call(pid, {:upgrade_to_websocket, path, headers}, Map.get(options, :timeout, 5000)) do
            {:ok, stream_ref} ->
              # Wait for websocket_connected status
              ws_status = wait_for_status(pid, :websocket_connected, Map.get(options, :timeout, 5000))

              if ws_status == :websocket_connected do
                # Build ClientConn struct
                state_result = GenServer.call(pid, :get_state)

                case state_result do
                  %WebsockexNova.Gun.ConnectionState{} = _state ->
                    {:ok,
                     %WebsockexNova.ClientConn{
                       transport: __MODULE__,
                       transport_pid: pid,
                       stream_ref: stream_ref,
                       adapter: Map.get(options, :adapter),
                       adapter_state: Map.get(options, :adapter_state),
                       callback_pids: Enum.filter([Map.get(options, :callback_pid)], & &1)
                     }}

                  _other ->
                    GenServer.stop(pid)
                    {:error, :connection_failed}
                end
              else
                GenServer.stop(pid)
                {:error, :websocket_upgrade_failed}
              end

            {:error, reason} ->
              GenServer.stop(pid)
              {:error, reason}
          end
        else
          GenServer.stop(pid)
          {:error, :connection_failed}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Closes a WebSocket connection.

  ## Parameters

  * `conn` - The client connection struct

  ## Returns

  * `:ok`
  """
  @spec close(WebsockexNova.ClientConn.t()) :: :ok
  @impl WebsockexNova.Transport
  def close(%WebsockexNova.ClientConn{transport_pid: pid}) do
    GenServer.cast(pid, :close)
  end

  @doc """
  Upgrades an HTTP connection to WebSocket.

  ## Parameters

  * `conn` - The client connection struct
  * `path` - The WebSocket endpoint path
  * `headers` - Additional headers for the upgrade request

  ## Returns

  * `{:ok, reference()}` on success
  * `{:error, reason}` on failure
  """
  @spec upgrade_to_websocket(WebsockexNova.ClientConn.t(), binary(), Keyword.t()) ::
          {:ok, reference()} | {:error, term()}
  @impl WebsockexNova.Transport
  def upgrade_to_websocket(%WebsockexNova.ClientConn{transport_pid: pid}, path, headers) do
    GenServer.call(pid, {:upgrade_to_websocket, path, headers})
  end

  @doc """
  Sends a WebSocket frame.

  ## Parameters

  * `conn` - The client connection struct
  * `stream_ref` - The stream reference from the upgrade
  * `frame` - WebSocket frame to send

  ## Returns

  * `:ok` on success
  * `{:error, reason}` on failure
  """
  @impl WebsockexNova.Transport
  @spec send_frame(WebsockexNova.ClientConn.t(), reference(), frame() | [frame()]) :: :ok | {:error, term()}
  def send_frame(%WebsockexNova.ClientConn{transport_pid: pid}, stream_ref, frame) do
    Logger.debug(
      "[ConnectionWrapper.send_frame/3] Sending frame: #{inspect(frame)} to stream_ref: #{inspect(stream_ref)}"
    )

    GenServer.call(pid, {:send_frame, stream_ref, frame})
  end

  @doc """
  Process a Gun message.

  ## Parameters

  * `conn` - The client connection struct
  * `message` - The Gun message to process

  ## Returns

  * `:ok`
  """
  @impl WebsockexNova.Transport
  @spec process_transport_message(WebsockexNova.ClientConn.t(), tuple()) :: :ok
  def process_transport_message(%WebsockexNova.ClientConn{transport_pid: pid}, message) do
    GenServer.cast(pid, {:process_gun_message, message})
  end

  @doc """
  Gets the current connection state.

  ## Parameters

  * `conn` - The client connection struct

  ## Returns

  * The current state struct
  """
  @impl WebsockexNova.Transport
  @spec get_state(WebsockexNova.ClientConn.t()) :: ConnectionState.t()
  def get_state(%WebsockexNova.ClientConn{transport_pid: pid}) do
    GenServer.call(pid, :get_state)
  end

  @doc """
  Sets the connection status (mainly for testing).

  ## Parameters

  * `conn` - The client connection struct
  * `status` - The new status to set

  ## Returns

  * `:ok`
  """
  @spec set_status(WebsockexNova.ClientConn.t(), status()) :: :ok
  def set_status(%WebsockexNova.ClientConn{transport_pid: pid}, status) do
    GenServer.cast(pid, {:set_status, status})
  end

  @doc """
  Transfers ownership of the Gun connection to another process.

  Gun connections have a specific ownership model where only one process receives messages
  from a Gun connection. This function implements a safe transfer protocol that ensures
  proper message routing after ownership changes.

  The transfer protocol:
  1. Validates that the Gun process exists and is alive
  2. Validates that the target process exists and is alive
  3. Demonitors the current Gun process monitor
  4. Creates a new monitor for the Gun process
  5. Uses `:gun.set_owner/2` to redirect Gun messages to the new owner
  6. Sends a `:gun_info` message with connection state to the new owner
  7. Updates the local state with the new monitor reference

  After the transfer completes:
  - The target process will receive all Gun messages
  - The original process maintains its ConnectionWrapper state
  - The ConnectionWrapper maintains its monitor of the Gun process

  This function is useful for load balancing, process migration, or implementing
  more complex ownership strategies.

  ## Parameters

  * `conn` - The client connection struct
  * `new_owner_pid` - PID of the process that should become the new owner

  ## Returns

  * `:ok` on success
  * `{:error, :no_gun_pid}` if no Gun process exists
  * `{:error, :invalid_target_process}` if the target process is invalid or dead
  * `{:error, :gun_process_not_alive}` if the Gun process died
  * `{:error, reason}` for other Gun-specific errors
  """
  @spec transfer_ownership(WebsockexNova.ClientConn.t(), pid()) :: :ok | {:error, term()}
  def transfer_ownership(%WebsockexNova.ClientConn{transport_pid: pid}, new_owner_pid) do
    GenServer.call(pid, {:transfer_ownership, new_owner_pid})
  end

  @doc """
  Receives ownership of a Gun connection from another process.

  This function implements the receiving side of the ownership transfer protocol.
  It's designed to be used in conjunction with `transfer_ownership/2` but can also
  be used independently to take ownership of any Gun process.

  The receive protocol:
  1. Validates that the provided Gun PID exists and is alive
  2. Creates a monitor for the Gun process
  3. Retrieves information about the Gun connection using `:gun.info/1`
  4. Sets the current process as the Gun process owner with `:gun.set_owner/2`
  5. Updates the ConnectionWrapper state with the Gun PID, monitor reference, and status

  This function is particularly useful when implementing systems where connections
  need to be dynamically reassigned between processes, such as in worker pools or
  during process handoffs.

  ## Parameters

  * `conn` - The client connection struct
  * `gun_pid` - PID of the Gun process being transferred

  ## Returns

  * `:ok` on success
  * `{:error, :invalid_gun_pid}` if the Gun process is invalid or dead
  * `{:error, reason}` for Gun-specific errors
  """
  @spec receive_ownership(WebsockexNova.ClientConn.t(), pid()) :: :ok | {:error, term()}
  def receive_ownership(%WebsockexNova.ClientConn{transport_pid: pid}, gun_pid) do
    GenServer.call(pid, {:receive_ownership, gun_pid})
  end

  @doc """
  Waits for the WebSocket upgrade to complete.

  ## Parameters

  * `conn` - The client connection struct
  * `stream_ref` - Stream reference from the upgrade
  * `timeout` - Timeout in milliseconds (default: 5000)

  ## Returns

  * `{:ok, headers}` on successful upgrade
  * `{:error, reason}` on failure
  """
  @spec wait_for_websocket_upgrade(WebsockexNova.ClientConn.t(), reference(), non_neg_integer()) ::
          {:ok, list()} | {:error, term()}
  def wait_for_websocket_upgrade(%WebsockexNova.ClientConn{transport_pid: pid}, stream_ref, timeout \\ 5000) do
    GenServer.call(pid, {:wait_for_websocket_upgrade, stream_ref, timeout})
  end

  @doc """
  Subscribes to a channel using the configured subscription handler.
  """
  @spec subscribe(WebsockexNova.ClientConn.t(), reference(), String.t(), map()) :: any
  def subscribe(%WebsockexNova.ClientConn{transport_pid: pid}, stream_ref, channel, params) do
    GenServer.call(pid, {:subscribe, stream_ref, channel, params})
  end

  @doc """
  Unsubscribes from a channel using the configured subscription handler.
  """
  @spec unsubscribe(WebsockexNova.ClientConn.t(), reference(), String.t()) :: any
  def unsubscribe(%WebsockexNova.ClientConn{transport_pid: pid}, stream_ref, channel) do
    GenServer.call(pid, {:unsubscribe, stream_ref, channel})
  end

  @doc """
  Authenticates using the configured auth handler.
  """
  @spec authenticate(WebsockexNova.ClientConn.t(), reference(), map()) :: any
  def authenticate(%WebsockexNova.ClientConn{transport_pid: pid}, stream_ref, credentials) do
    GenServer.call(pid, {:authenticate, stream_ref, credentials})
  end

  @doc """
  Sends a ping using the configured connection handler.
  """
  @spec ping(WebsockexNova.ClientConn.t(), reference()) :: any
  def ping(%WebsockexNova.ClientConn{transport_pid: pid}, stream_ref) do
    GenServer.call(pid, {:ping, stream_ref})
  end

  @doc """
  Gets the status using the configured connection handler.
  """
  @spec status(WebsockexNova.ClientConn.t(), reference()) :: any
  def status(%WebsockexNova.ClientConn{transport_pid: pid}, stream_ref) do
    GenServer.call(pid, {:status, stream_ref})
  end

  @impl WebsockexNova.Transport
  def schedule_reconnection(state, callback) do
    ConnectionManager.schedule_reconnection(state, callback)
  end

  @impl WebsockexNova.Transport
  def start_connection(state) do
    case ConnectionManager.start_connection(state) do
      {:ok, updated_state} -> updated_state
      {:error, _reason, error_state} -> error_state
    end
  end

  # Server callbacks
  @impl true
  def init({host, port, options, _supervisor}) do
    case ConnectionOptions.parse_and_validate(options) do
      {:ok, validated_options} ->
        # Store :rate_limiter in options if provided, else default
        rate_limiter = Map.get(validated_options, :rate_limiter, RateLimiting)
        validated_options = Map.put(validated_options, :rate_limiter, rate_limiter)
        state = ConnectionState.new(host, port, validated_options)

        # Set up behavior handlers if provided in options
        state =
          state
          |> initialize_connection_handler(validated_options)
          |> initialize_subscription_handler(validated_options)
          |> initialize_auth_handler(validated_options)
          |> initialize_message_handler(validated_options)
          |> initialize_error_handler(validated_options)

        # Set up logging handler (default if not provided)
        {logging_handler, logging_handler_opts} =
          case {Map.get(validated_options, :logging_handler), Map.get(validated_options, :logging_handler_options)} do
            {nil, _} -> {WebsockexNova.Defaults.DefaultLoggingHandler, %{}}
            {mod, nil} -> {mod, %{}}
            {mod, opts} -> {mod, opts}
          end

        state = ConnectionState.setup_logging_handler(state, logging_handler, logging_handler_opts)

        case initiate_connection(state) do
          {:ok, updated_state} ->
            {:ok, updated_state}

          {:error, reason, error_state} ->
            Logger.error("Failed to open connection: #{inspect(reason)}")
            {:ok, error_state}
        end

      {:error, msg} ->
        Logger.error("Invalid connection options: #{msg}")
        error_state = host |> ConnectionState.new(port, %{}) |> ConnectionState.update_status(:error)
        {:ok, error_state}
    end
  end

  @impl true
  def handle_call({:upgrade_to_websocket, path, headers}, _from, state) do
    Logger.debug(
      "[ConnectionWrapper] Received upgrade_to_websocket: path=#{inspect(path)}, headers=#{inspect(headers)}, state.status=#{inspect(StateHelpers.get_status(state))}, gun_pid=#{inspect(state.gun_pid)}"
    )

    if state.gun_pid && StateHelpers.get_status(state) == :connected do
      stream_ref =
        :gun.ws_upgrade(
          state.gun_pid,
          path,
          headers_to_gun_format(headers),
          state.options.ws_opts
        )

      Logger.debug("[ConnectionWrapper] Called :gun.ws_upgrade, stream_ref=#{inspect(stream_ref)}")
      # Update state with stream reference
      updated_state = ConnectionState.update_stream(state, stream_ref, :upgrading)
      {:reply, {:ok, stream_ref}, updated_state}
    else
      Logger.error("[ConnectionWrapper] Cannot upgrade: not connected or missing gun_pid. State: #{inspect(state)}")
      {:reply, {:error, :not_connected}, state}
    end
  end

  def handle_call({:send_frame, stream_ref, frame}, _from, state) do
    if is_nil(state.gun_pid) do
      ErrorHandler.handle_connection_error(:not_connected, state)
    else
      case Map.get(state.active_streams, stream_ref) do
        :websocket ->
          handle_send_frame_with_rate_limiting(state, stream_ref, frame)

        nil ->
          ErrorHandler.handle_stream_error(stream_ref, :stream_not_found, state)

        status ->
          ErrorHandler.handle_stream_error(stream_ref, {:invalid_stream_status, status}, state)
      end
    end
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_call(:get_port, _from, state) do
    {:reply, StateHelpers.get_port(state), state}
  end

  @impl true
  def handle_call(:get_status, _from, state) do
    status = StateHelpers.get_status(state)
    {:reply, {:ok, status}, state}
  end

  @impl true
  def handle_call({:transfer_ownership, new_owner_pid}, _from, state) do
    case validate_transfer_ownership(state, new_owner_pid) do
      :ok ->
        # Perform ownership transfer if validation passes
        perform_ownership_transfer(state, new_owner_pid)

      {:error, reason} ->
        # Return error if validation fails (e.g., no Gun pid, invalid target process)
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:receive_ownership, gun_pid}, _from, state) do
    case validate_gun_pid(gun_pid) do
      :ok ->
        # Receive ownership and update state if Gun pid is valid
        receive_ownership_and_update_state(state, gun_pid)

      {:error, reason} ->
        # Return error if Gun pid is invalid or dead
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:wait_for_websocket_upgrade, stream_ref, timeout}, _from, state) do
    Logger.debug(
      "[ConnectionWrapper] Waiting for websocket upgrade: stream_ref=#{inspect(stream_ref)}, timeout=#{inspect(timeout)}, gun_pid=#{inspect(state.gun_pid)}"
    )

    if state.gun_pid do
      monitor_ref = state.gun_monitor_ref
      result = :gun.await(state.gun_pid, stream_ref, timeout, monitor_ref)
      Logger.debug("[ConnectionWrapper] :gun.await result: #{inspect(result)}")
      handle_websocket_upgrade_result(result, stream_ref, state)
    else
      Logger.error("[ConnectionWrapper] Cannot wait for upgrade: gun_pid is nil. State: #{inspect(state)}")
      ErrorHandler.handle_connection_error(:not_connected, state)
    end
  end

  @impl true
  def handle_call({:subscribe, _stream_ref, channel, params}, _from, state) do
    handler = Map.get(state.handlers, :subscription_handler)
    handler_state = Map.get(state.handlers, :subscription_handler_state)
    result = handler.subscribe(channel, params, handler_state)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:unsubscribe, _stream_ref, channel}, _from, state) do
    handler = Map.get(state.handlers, :subscription_handler)
    handler_state = Map.get(state.handlers, :subscription_handler_state)
    result = handler.unsubscribe(channel, handler_state)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:authenticate, stream_ref, credentials}, _from, state) do
    handler = Map.get(state.handlers, :auth_handler)
    handler_state = Map.get(state.handlers, :auth_handler_state)
    result = handler.authenticate(stream_ref, credentials, handler_state)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:ping, stream_ref}, _from, state) do
    handler = Map.get(state.handlers, :connection_handler)
    handler_state = Map.get(state.handlers, :connection_handler_state)
    result = handler.ping(stream_ref, handler_state)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:status, stream_ref}, _from, state) do
    handler = Map.get(state.handlers, :connection_handler)
    handler_state = Map.get(state.handlers, :connection_handler_state)
    result = handler.status(stream_ref, handler_state)
    {:reply, result, state}
  end

  @impl true
  def handle_cast({:process_gun_message, message}, state) do
    handle_gun_message(message, state)
  end

  def handle_cast(:close, state) do
    cleaned_state = ConnectionState.clear_all_streams(state)

    if state.gun_pid do
      :gun.shutdown(state.gun_pid)
    end

    final_state = ConnectionState.prepare_for_termination(cleaned_state)

    {:stop, :normal, final_state}
  end

  def handle_cast({:set_status, status}, state) do
    {:noreply, ConnectionState.update_status(state, status)}
  end

  @impl true
  def handle_info({:gun_up, gun_pid, protocol}, %{gun_pid: gun_pid} = state) do
    # Use MessageHandlers to ensure consistent callback notification format
    # Simply delegate to handler, no need for manual extraction of return value
    MessageHandlers.handle_connection_up(gun_pid, protocol, state)
  end

  @impl true
  def handle_info(
        {:gun_down, gun_pid, protocol, reason, killed_streams, unprocessed_streams},
        %{gun_pid: gun_pid, callback_pid: callback_pid} = state
      ) do
    result = handle_gun_down(state, gun_pid, protocol, reason, killed_streams, unprocessed_streams)
    if callback_pid, do: send(callback_pid, {:connection_down, reason})
    result
  end

  def handle_info({:gun_upgrade, gun_pid, stream_ref, ["websocket"], headers}, %{gun_pid: gun_pid} = state) do
    case ConnectionManager.transition_to(state, :websocket_connected) do
      {:ok, new_state} ->
        # Directly delegate to MessageHandlers
        MessageHandlers.handle_websocket_upgrade(gun_pid, stream_ref, headers, new_state)

      {:error, reason} ->
        Logger.error("Failed to transition state: #{inspect(reason)}")
        ErrorHandler.handle_transition_error(StateHelpers.get_status(state), :websocket_connected, reason, state)
    end
  end

  def handle_info({:gun_ws, gun_pid, stream_ref, frame}, %{gun_pid: gun_pid} = state) do
    # Directly delegate to MessageHandlers
    MessageHandlers.handle_websocket_frame(gun_pid, stream_ref, frame, state)
  end

  def handle_info({:gun_error, gun_pid, stream_ref, reason}, %{gun_pid: gun_pid, callback_pid: callback_pid} = state) do
    # First clean up the stream with the error
    state_with_cleanup = ConnectionState.remove_stream(state, stream_ref)
    # Then delegate to MessageHandlers with the cleaned state
    result = MessageHandlers.handle_error(gun_pid, stream_ref, reason, state_with_cleanup)
    if callback_pid, do: send(callback_pid, {:connection_error, reason})
    result
  end

  def handle_info({:gun_response, gun_pid, stream_ref, is_fin, status, headers}, %{gun_pid: gun_pid} = state) do
    # Directly delegate to MessageHandlers
    MessageHandlers.handle_http_response(gun_pid, stream_ref, is_fin, status, headers, state)
  end

  def handle_info({:gun_data, gun_pid, stream_ref, is_fin, data}, %{gun_pid: gun_pid} = state) do
    # Directly delegate to MessageHandlers
    MessageHandlers.handle_http_data(gun_pid, stream_ref, is_fin, data, state)
  end

  def handle_info({:reconnect, attempt_source}, state) do
    Logger.debug("Reconnection attempt initiated by: #{inspect(attempt_source)}")

    case initiate_connection(state) do
      {:ok, new_state} ->
        {:noreply, new_state}

      {:error, reason, error_state} ->
        # Use standard error handler with reconnect-specific context
        ErrorHandler.handle_async_error(
          nil,
          {:reconnect_failed, reason, attempt_source},
          error_state
        )
    end
  end

  def handle_info({:gun_info, info}, state) do
    # Use StateHelpers to handle the ownership transfer
    final_state = Helpers.StateHelpers.handle_ownership_transfer(state, info)
    {:noreply, final_state}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, pid, reason}, state) do
    if state.gun_monitor_ref == ref and state.gun_pid == pid do
      handle_gun_process_down(state, reason)
    else
      {:noreply, state}
    end
  end

  def handle_info(other, state) do
    Logger.warning("Unhandled message in ConnectionWrapper: #{inspect(other)}")
    {:noreply, state}
  end

  # Private functions

  # Helper to standardize handler result processing
  defp process_handler_result(result) do
    case result do
      {:noreply, updated_state} when is_map(updated_state) ->
        {:noreply, updated_state}

      {:stop, reason, updated_state} when is_map(updated_state) ->
        {:stop, reason, updated_state}

      # Other cases can't occur based on MessageHandlers implementation,
      # but we need to handle them to satisfy Dialyzer
      _other ->
        Logger.warning("Unexpected result from MessageHandlers: #{inspect(result)}")
        {:noreply, %{}}
    end
  end

  defp handle_gun_message({:gun_up, pid, protocol}, state) do
    pid
    |> MessageHandlers.handle_connection_up(protocol, state)
    |> process_handler_result()
  end

  defp handle_gun_message({:gun_down, pid, protocol, reason, killed_streams, unprocessed_streams}, state) do
    # First transition to disconnected state for consistency with handle_info
    case ConnectionManager.transition_to(state, :disconnected, %{reason: reason}) do
      {:ok, disconnected_state} ->
        # Delegate to MessageHandlers with state transition already done
        pid
        |> MessageHandlers.handle_connection_down(
          protocol,
          reason,
          disconnected_state,
          killed_streams,
          unprocessed_streams
        )
        |> process_handler_result()

      {:error, transition_reason} ->
        Logger.error("Failed to transition state: #{inspect(transition_reason)}")

        ErrorHandler.handle_transition_error(
          state.status,
          :disconnected,
          transition_reason,
          state
        )
    end
  end

  defp handle_gun_message({:gun_upgrade, pid, stream_ref, ["websocket"], headers}, state) do
    # Match pattern in handle_info by transitioning state first
    case ConnectionManager.transition_to(state, :websocket_connected) do
      {:ok, new_state} ->
        # Now delegate to MessageHandlers
        pid
        |> MessageHandlers.handle_websocket_upgrade(stream_ref, headers, new_state)
        |> process_handler_result()

      {:error, reason} ->
        Logger.error("Failed to transition state: #{inspect(reason)}")
        ErrorHandler.handle_transition_error(StateHelpers.get_status(state), :websocket_connected, reason, state)
    end
  end

  defp handle_gun_message({:gun_ws, pid, stream_ref, frame}, state) do
    pid
    |> MessageHandlers.handle_websocket_frame(stream_ref, frame, state)
    |> process_handler_result()
  end

  defp handle_gun_message({:gun_error, pid, stream_ref, reason}, state) do
    # Clean up the stream before delegating to MessageHandler
    state_with_cleanup = ConnectionState.remove_stream(state, stream_ref)

    pid
    |> MessageHandlers.handle_error(stream_ref, reason, state_with_cleanup)
    |> process_handler_result()
  end

  defp handle_gun_message({:gun_response, pid, stream_ref, is_fin, status, headers}, state) do
    pid
    |> MessageHandlers.handle_http_response(stream_ref, is_fin, status, headers, state)
    |> process_handler_result()
  end

  defp handle_gun_message({:gun_data, pid, stream_ref, is_fin, data}, state) do
    pid
    |> MessageHandlers.handle_http_data(stream_ref, is_fin, data, state)
    |> process_handler_result()
  end

  defp handle_gun_message(unknown_message, state) do
    # Log unknown messages
    Logger.warning("Received unknown gun message: #{inspect(unknown_message)}")
    {:noreply, state}
  end

  defp initiate_connection(state) do
    case ConnectionManager.start_connection(state) do
      {:ok, updated_state} -> {:ok, updated_state}
      {:error, reason, error_state} -> {:error, reason, error_state}
    end
  end

  defp headers_to_gun_format(headers) do
    Enum.map(headers, fn
      {key, value} when is_binary(key) -> {key, to_string(value)}
      {key, value} when is_atom(key) -> {to_string(key), to_string(value)}
      other -> other
    end)
  end

  # Private helper functions

  defp initialize_connection_handler(state, options) do
    case Map.get(options, :callback_handler) do
      nil ->
        state

      handler_module when is_atom(handler_module) ->
        # Always include :test_pid if present in options
        handler_options =
          options
          |> Map.drop([:transport, :transport_opts, :protocols, :retry, :ws_opts])
          |> Map.put(:connection_wrapper_pid, self())
          |> maybe_put_test_pid(options)

        Logger.debug("[init_conn_handler] handler_options: #{inspect(handler_options)}")
        ConnectionState.setup_connection_handler(state, handler_module, handler_options)
    end
  end

  defp maybe_put_test_pid(opts, original_opts) do
    case Map.get(original_opts, :test_pid) do
      nil -> opts
      test_pid -> Map.put(opts, :test_pid, test_pid)
    end
  end

  defp initialize_subscription_handler(state, options) do
    handler_module = Map.get(options, :subscription_handler) || Map.get(options, :callback_handler)

    if handler_module do
      handler_options =
        options
        |> Map.drop([:transport, :transport_opts, :protocols, :retry, :ws_opts])
        |> Map.put(:connection_wrapper_pid, self())

      ConnectionState.setup_subscription_handler(state, handler_module, handler_options)
    else
      state
    end
  end

  defp initialize_auth_handler(state, options) do
    handler_module = Map.get(options, :auth_handler) || Map.get(options, :callback_handler)

    if handler_module do
      handler_options =
        options
        |> Map.drop([:transport, :transport_opts, :protocols, :retry, :ws_opts])
        |> Map.put(:connection_wrapper_pid, self())

      ConnectionState.setup_auth_handler(state, handler_module, handler_options)
    else
      state
    end
  end

  defp initialize_message_handler(state, options) do
    case Map.get(options, :message_handler) do
      nil ->
        state

      handler_module when is_atom(handler_module) ->
        handler_options =
          options
          |> Map.drop([:transport, :transport_opts, :protocols, :retry, :ws_opts])
          |> Map.put(:connection_wrapper_pid, self())

        ConnectionState.setup_message_handler(state, handler_module, handler_options)
    end
  end

  defp initialize_error_handler(state, options) do
    case Map.get(options, :error_handler) do
      nil ->
        state

      handler_module when is_atom(handler_module) ->
        handler_options =
          options
          |> Map.drop([:transport, :transport_opts, :protocols, :retry, :ws_opts])
          |> Map.put(:connection_wrapper_pid, self())

        ConnectionState.setup_error_handler(state, handler_module, handler_options)
    end
  end

  defp handle_gun_down(state, gun_pid, protocol, reason, killed_streams, unprocessed_streams) do
    case ConnectionManager.transition_to(state, :disconnected, %{reason: reason}) do
      {:ok, disconnected_state} ->
        disconnected_state_with_cleanup =
          cleanup_killed_streams(disconnected_state, killed_streams)

        result =
          MessageHandlers.handle_connection_down(
            gun_pid,
            protocol,
            reason,
            disconnected_state_with_cleanup,
            killed_streams,
            unprocessed_streams
          )

        handle_connection_down_result(result, disconnected_state_with_cleanup, reason)

      {:error, transition_reason} ->
        Logger.error("Failed to transition state: #{inspect(transition_reason)}")
        ErrorHandler.handle_transition_error(StateHelpers.get_status(state), :disconnected, transition_reason, state)
    end
  end

  defp cleanup_killed_streams(state, killed_streams) do
    if killed_streams && is_list(killed_streams) do
      ConnectionState.remove_streams(state, killed_streams)
    else
      state
    end
  end

  defp handle_connection_down_result({:noreply, new_state}, _disconnected_state, _reason) when is_map(new_state) do
    reconnect_callback = fn delay, _attempt ->
      Process.send_after(self(), {:reconnect, :timer}, delay)
    end

    final_state = ConnectionManager.schedule_reconnection(new_state, reconnect_callback)
    {:noreply, final_state}
  end

  defp handle_connection_down_result({:stop, stop_reason, final_state}, _disconnected_state, _reason)
       when is_map(final_state) do
    {:stop, stop_reason, final_state}
  end

  defp handle_connection_down_result(other, disconnected_state, _reason) do
    Logger.error("Unexpected response from handle_connection_down: #{inspect(other)}")
    {:noreply, disconnected_state}
  end

  defp validate_transfer_ownership(state, new_owner_pid) do
    cond do
      is_nil(state.gun_pid) ->
        Logger.error("Cannot transfer ownership: no Gun process available")
        {:error, :no_gun_pid}

      not is_pid(new_owner_pid) or not Process.alive?(new_owner_pid) ->
        Logger.error("Cannot transfer ownership: invalid target process #{inspect(new_owner_pid)}")
        {:error, :invalid_target_process}

      not Process.alive?(state.gun_pid) ->
        Logger.error("Cannot transfer ownership: Gun process is no longer alive")
        {:error, :gun_process_not_alive}

      true ->
        :ok
    end
  end

  defp perform_ownership_transfer(state, new_owner_pid) do
    if state.gun_monitor_ref, do: Process.demonitor(state.gun_monitor_ref, [:flush])
    gun_monitor_ref = Process.monitor(state.gun_pid)
    :gun.set_owner(state.gun_pid, new_owner_pid)
    Logger.info("Successfully transferred Gun process ownership to #{inspect(new_owner_pid)}")
    updated_state = ConnectionState.update_gun_monitor_ref(state, gun_monitor_ref)

    send(
      new_owner_pid,
      {:gun_info,
       %{
         gun_pid: state.gun_pid,
         host: state.host,
         port: state.port,
         status: state.status,
         options: state.options,
         active_streams: state.active_streams
       }}
    )

    {:reply, :ok, updated_state}
  end

  defp validate_gun_pid(gun_pid) do
    if is_nil(gun_pid) or not is_pid(gun_pid) or not Process.alive?(gun_pid) do
      Logger.error("Invalid Gun PID or process not alive: #{inspect(gun_pid)}")
      {:error, :invalid_gun_pid}
    else
      :ok
    end
  end

  defp receive_ownership_and_update_state(state, gun_pid) do
    gun_monitor_ref = Process.monitor(gun_pid)

    case :gun.info(gun_pid) do
      info when is_map(info) ->
        :gun.set_owner(gun_pid, self())

        updated_state =
          state
          |> ConnectionState.update_gun_pid(gun_pid)
          |> ConnectionState.update_gun_monitor_ref(gun_monitor_ref)
          |> ConnectionState.update_status(:connected)

        Logger.info("Successfully received Gun connection ownership")
        {:reply, :ok, updated_state}
    end
  end

  defp handle_gun_process_down(state, reason) do
    Logger.error("Gun process terminated: #{inspect(reason)}")

    case ConnectionManager.transition_to(state, :disconnected, %{reason: reason}) do
      {:ok, disconnected_state} ->
        reconnect_callback = fn delay, _attempt ->
          Process.send_after(self(), {:reconnect, :monitor}, delay)
        end

        new_state = ConnectionManager.schedule_reconnection(disconnected_state, reconnect_callback)

        if new_state.callback_pid do
          MessageHandlers.notify(new_state.callback_pid, {:connection_down, :http, reason})
        end

        if reason in [:crash, :killed, :shutdown] do
          {:stop, :gun_terminated, new_state}
        else
          {:noreply, new_state}
        end

      {:error, transition_reason} ->
        ErrorHandler.handle_transition_error(state.status, :disconnected, transition_reason, state)
        {:stop, :gun_terminated, state}
    end
  end

  defp handle_websocket_upgrade_result(result, stream_ref, state) do
    Logger.debug(
      "[ConnectionWrapper] handle_websocket_upgrade_result: result=#{inspect(result)}, stream_ref=#{inspect(stream_ref)}"
    )

    case result do
      {:upgrade, ["websocket"], headers} ->
        updated_state = ConnectionState.update_stream(state, stream_ref, :websocket)
        {:reply, {:ok, headers}, updated_state}

      {:response, :fin, status, headers} when status >= 400 ->
        reason = {:http_error, status, headers}
        ErrorHandler.handle_upgrade_error(stream_ref, reason, state)

      {:error, reason} ->
        ErrorHandler.handle_upgrade_error(stream_ref, reason, state)
    end
  end

  # Helper functions for rate limiting request construction

  defp frame_type_from_frame({type, _data}) when type in [:text, :binary, :close], do: type
  defp frame_type_from_frame(:ping), do: :ping
  defp frame_type_from_frame(:pong), do: :pong
  defp frame_type_from_frame(:close), do: :close
  defp frame_type_from_frame(_), do: :unknown

  defp method_from_frame({type, _data}) when type in [:text, :binary], do: to_string(type)
  defp method_from_frame({:close, _code, _reason}), do: "close"
  defp method_from_frame(:ping), do: "ping"
  defp method_from_frame(:pong), do: "pong"
  defp method_from_frame(:close), do: "close"
  defp method_from_frame(_), do: "unknown"

  defp frame_data_from_frame({_type, data}), do: data
  defp frame_data_from_frame({:close, code, reason}), do: %{code: code, reason: reason}
  defp frame_data_from_frame(_), do: nil

  # --- Private helpers for send_frame ---
  defp handle_send_frame_with_rate_limiting(state, stream_ref, frame) do
    Logger.debug(
      "[ConnectionWrapper.handle_send_frame_with_rate_limiting] Preparing to send frame: #{inspect(frame)} on stream_ref: #{inspect(stream_ref)} (gun_pid: #{inspect(state.gun_pid)})"
    )

    request = build_rate_limit_request(state, stream_ref, frame)
    rate_limiter = Map.get(state.options, :rate_limiter, RateLimiting)

    case RateLimiting.check(request, rate_limiter) do
      {:allow, _request_id} ->
        Logger.debug(
          "[ConnectionWrapper.handle_send_frame_with_rate_limiting] Allowed by rate limiter. Calling :gun.ws_send with frame: #{inspect(frame)}"
        )

        result = :gun.ws_send(state.gun_pid, stream_ref, frame)

        Logger.debug(
          "[ConnectionWrapper.handle_send_frame_with_rate_limiting] :gun.ws_send result: #{inspect(result)} for frame: #{inspect(frame)}"
        )

        emit_telemetry_for_frame(state, stream_ref, frame)
        {:reply, result, state}

      {:queue, request_id} ->
        Logger.debug(
          "[ConnectionWrapper.handle_send_frame_with_rate_limiting] Queued by rate limiter. Will call :gun.ws_send later for frame: #{inspect(frame)}"
        )

        callback = fn -> :gun.ws_send(state.gun_pid, stream_ref, frame) end
        _ = RateLimiting.on_process(request_id, callback, rate_limiter)
        {:reply, :ok, state}

      {:reject, reason} ->
        Logger.debug(
          "[ConnectionWrapper.handle_send_frame_with_rate_limiting] Rejected by rate limiter: #{inspect(reason)} for frame: #{inspect(frame)}"
        )

        {:reply, {:error, reason}, state}
    end
  end

  defp build_rate_limit_request(state, stream_ref, frame) do
    %{
      type: frame_type_from_frame(frame),
      method: method_from_frame(frame),
      data: frame_data_from_frame(frame),
      stream_ref: stream_ref,
      connection: %{host: state.host, port: state.port}
    }
  end

  defp emit_telemetry_for_frame(state, stream_ref, frame) do
    {frame_type, frame_data} =
      case frame do
        [f | _] -> {frame_type_from_frame(f), frame_data_from_frame(f)}
        _ -> {frame_type_from_frame(frame), frame_data_from_frame(frame)}
      end

    size =
      case frame_data do
        data when is_binary(data) -> byte_size(data)
        _ -> 0
      end

    :telemetry.execute(
      TelemetryEvents.message_sent(),
      %{size: size},
      %{connection_id: state.gun_pid, stream_ref: stream_ref, frame_type: frame_type}
    )
  end

  # Helper to wait for a connection status
  defp wait_for_status(pid, expected_status, timeout) do
    start = System.monotonic_time(:millisecond)
    do_wait_for_status(pid, expected_status, timeout, start)
  end

  defp do_wait_for_status(pid, expected_status, timeout, start) do
    state =
      try do
        GenServer.call(pid, :get_state, 100)
      catch
        :exit, _ -> %{status: :error}
      end

    if Map.get(state, :status) == expected_status do
      expected_status
    else
      now = System.monotonic_time(:millisecond)

      if now - start > timeout do
        :timeout
      else
        Process.sleep(50)
        do_wait_for_status(pid, expected_status, timeout, start)
      end
    end
  end
end
