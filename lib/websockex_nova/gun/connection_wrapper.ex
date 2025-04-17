defmodule WebsockexNova.Gun.ConnectionWrapper do
  @moduledoc """
  Wraps the Gun WebSocket connection functionality, providing a simplified interface.

  This module abstracts away the complexity of dealing with Gun directly, offering
  functions for connecting, upgrading to WebSocket, sending frames, and processing messages.

  It uses a structured state machine approach with the ConnectionManager to manage
  connection lifecycle, reconnection strategies, and state transitions.
  """

  use GenServer
  require Logger

  alias WebsockexNova.Gun.ConnectionState
  alias WebsockexNova.Gun.ConnectionManager
  alias WebsockexNova.Gun.ConnectionWrapper.MessageHandlers

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

  @typedoc "Options for connection wrapper"
  @type options :: %{
          optional(:transport) => :tcp | :tls,
          optional(:transport_opts) => Keyword.t(),
          optional(:protocols) => [:http | :http2 | :socks | :ws],
          optional(:retry) => non_neg_integer() | :infinity,
          optional(:callback_pid) => pid(),
          optional(:ws_opts) => map(),
          optional(:test_mode) => boolean(),
          optional(:backoff_type) => :linear | :exponential | :jittered,
          optional(:base_backoff) => non_neg_integer()
        }

  @default_options %{
    transport: :tcp,
    transport_opts: [],
    protocols: [:http],
    retry: 5,
    ws_opts: %{},
    test_mode: false,
    backoff_type: :exponential,
    base_backoff: 1000
  }

  # Client API

  @doc """
  Opens a connection to a WebSocket server.

  ## Parameters

  * `host` - Hostname or IP address of the server
  * `port` - Port number of the server (default: 80, or 443 for TLS)
  * `options` - Connection options (see `t:options/0`)
  * `supervisor` - Optional Gun client supervisor PID

  ## Options

  * `:transport` - Transport protocol (`:tcp` or `:tls`, default: `:tcp`)
  * `:transport_opts` - Options for the transport protocol
  * `:protocols` - Protocols to negotiate (`[:http | :http2 | :socks | :ws]`)
  * `:retry` - Number of times to retry connection (default: 5)
  * `:callback_pid` - Process to send WebSocket messages to
  * `:ws_opts` - WebSocket-specific options
  * `:test_mode` - Whether to operate in test mode (default: false)
  * `:backoff_type` - Reconnection backoff strategy (`:linear`, `:exponential`, or `:jittered`)
  * `:base_backoff` - Base backoff time in milliseconds (default: 1000)

  ## Returns

  * `{:ok, pid}` on success
  * `{:error, reason}` on failure
  """
  @spec open(binary(), pos_integer(), options(), pid() | nil) :: {:ok, pid()} | {:error, term()}
  def open(host, port, options \\ %{}, supervisor \\ nil) do
    GenServer.start_link(__MODULE__, {host, port, options, supervisor})
  end

  @doc """
  Closes a WebSocket connection.

  ## Parameters

  * `pid` - The connection wrapper PID

  ## Returns

  * `:ok`
  """
  @spec close(pid()) :: :ok
  def close(pid) do
    GenServer.cast(pid, :close)
  end

  @doc """
  Upgrades an HTTP connection to WebSocket.

  ## Parameters

  * `pid` - The connection wrapper PID
  * `path` - The WebSocket endpoint path
  * `headers` - Additional headers for the upgrade request

  ## Returns

  * `{:ok, reference()}` on success
  * `{:error, reason}` on failure
  """
  @spec upgrade_to_websocket(pid(), binary(), Keyword.t()) ::
          {:ok, reference()} | {:error, term()}
  def upgrade_to_websocket(pid, path, headers \\ []) do
    GenServer.call(pid, {:upgrade_to_websocket, path, headers})
  end

  @doc """
  Sends a WebSocket frame.

  ## Parameters

  * `pid` - The connection wrapper PID
  * `stream_ref` - The stream reference from the upgrade
  * `frame` - WebSocket frame to send

  ## Returns

  * `:ok` on success
  * `{:error, reason}` on failure
  """
  @spec send_frame(pid(), reference(), frame() | [frame()]) :: :ok | {:error, term()}
  def send_frame(pid, stream_ref, frame) do
    GenServer.call(pid, {:send_frame, stream_ref, frame})
  end

  @doc """
  Process a Gun message.

  ## Parameters

  * `pid` - The connection wrapper PID
  * `message` - The Gun message to process

  ## Returns

  * `:ok`
  """
  @spec process_gun_message(pid(), tuple()) :: :ok
  def process_gun_message(pid, message) do
    GenServer.cast(pid, {:process_gun_message, message})
  end

  @doc """
  Gets the current state of the connection wrapper.

  ## Parameters

  * `pid` - The connection wrapper PID

  ## Returns

  The current state of the connection wrapper.
  """
  @spec get_state(pid()) :: ConnectionState.t()
  def get_state(pid) do
    GenServer.call(pid, :get_state)
  end

  @doc """
  Sets the connection status (mainly for testing).

  ## Parameters

  * `pid` - The connection wrapper PID
  * `status` - The new status to set

  ## Returns

  * `:ok`
  """
  @spec set_status(pid(), status()) :: :ok
  def set_status(pid, status) do
    GenServer.cast(pid, {:set_status, status})
  end

  # Server callbacks

  @impl true
  def init({host, port, options, _supervisor}) do
    merged_options = Map.merge(@default_options, options)
    state = ConnectionState.new(host, port, merged_options)

    if state.options.test_mode do
      # In test mode, don't actually try to establish a connection
      {:ok, state}
    else
      # Start connection using ConnectionManager
      case initiate_connection(state) do
        {:ok, updated_state} ->
          {:ok, updated_state}

        {:error, reason, error_state} ->
          Logger.error("Failed to open connection: #{inspect(reason)}")
          {:ok, error_state}
      end
    end
  end

  @impl true
  def handle_call({:upgrade_to_websocket, path, headers}, _from, state) do
    if state.options.test_mode || (state.gun_pid && state.status == :connected) do
      stream_ref =
        if state.options.test_mode,
          do: make_ref(),
          else:
            :gun.ws_upgrade(
              state.gun_pid,
              path,
              headers_to_gun_format(headers),
              state.options.ws_opts
            )

      # Track the stream
      state = ConnectionState.update_stream(state, stream_ref, :upgrading)

      {:reply, {:ok, stream_ref}, state}
    else
      {:reply, {:error, :not_connected}, state}
    end
  end

  def handle_call({:send_frame, stream_ref, frame}, _from, state) do
    if state.options.test_mode || state.gun_pid do
      if state.options.test_mode do
        # In test mode, just pretend it worked
        {:reply, :ok, state}
      else
        # In normal mode, check the stream status
        case Map.get(state.active_streams, stream_ref) do
          :websocket ->
            # Send frame via Gun
            result = :gun.ws_send(state.gun_pid, stream_ref, frame)
            {:reply, result, state}

          nil ->
            {:reply, {:error, :stream_not_found}, state}

          status ->
            {:reply, {:error, {:invalid_stream_status, status}}, state}
        end
      end
    else
      {:reply, {:error, :not_connected}, state}
    end
  end

  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_cast({:process_gun_message, message}, state) do
    handle_gun_message(message, state)
  end

  def handle_cast(:close, state) do
    Logger.debug(
      "Closing connection wrapper with #{map_size(state.active_streams)} active streams"
    )

    # Clean up all stream references first
    cleaned_state = ConnectionState.clear_all_streams(state)

    # Close Gun connection if it exists
    if state.gun_pid do
      Logger.debug("Closing Gun connection: #{inspect(state.gun_pid)}")

      # In test mode with fake PID, we need to explicitly terminate the process
      if state.options.test_mode do
        Process.exit(state.gun_pid, :kill)
      else
        # Use gun:shutdown/1 to ensure the connection is properly closed
        # This both closes the connection and kills the process
        :gun.shutdown(state.gun_pid)
      end
    end

    # Final cleanup of state before termination
    final_state = ConnectionState.prepare_for_termination(cleaned_state)

    # Terminate the GenServer
    {:stop, :normal, final_state}
  end

  def handle_cast({:set_status, status}, state) do
    {:noreply, ConnectionState.update_status(state, status)}
  end

  @impl true
  def handle_info({:gun_up, gun_pid, protocol}, %{gun_pid: gun_pid} = state) do
    # Add debug logging
    Logger.debug("Gun UP received for pid #{inspect(gun_pid)}, protocol: #{inspect(protocol)}")

    case ConnectionManager.transition_to(state, :connected) do
      {:ok, new_state} ->
        # Explicitly send the notification here
        if new_state.options[:callback_pid] do
          Logger.debug("Sending connection_up directly to callback")
          send(new_state.options[:callback_pid], {:websockex_nova, {:connection_up, protocol}})
        end

        MessageHandlers.handle_connection_up(gun_pid, protocol, new_state)

      {:error, reason} ->
        Logger.error("Failed to transition state: #{inspect(reason)}")
        {:noreply, state}
    end
  end

  def handle_info(
        {:gun_down, gun_pid, protocol, reason, killed_streams, unprocessed_streams},
        %{gun_pid: gun_pid} = state
      ) do
    # Transition to disconnected with the reason
    case ConnectionManager.transition_to(state, :disconnected, %{reason: reason}) do
      {:ok, disconnected_state} ->
        # Handle cleanup of killed streams
        disconnected_state_with_cleanup =
          if killed_streams && is_list(killed_streams) do
            ConnectionState.remove_streams(disconnected_state, killed_streams)
          else
            disconnected_state
          end

        # Handle reconnection if appropriate
        new_state = handle_possible_reconnection(disconnected_state_with_cleanup, reason)

        MessageHandlers.handle_connection_down(
          gun_pid,
          protocol,
          reason,
          new_state,
          killed_streams,
          unprocessed_streams
        )

      {:error, transition_reason} ->
        Logger.error("Failed to transition state: #{inspect(transition_reason)}")
        {:noreply, state}
    end
  end

  def handle_info(
        {:gun_upgrade, gun_pid, stream_ref, ["websocket"], headers},
        %{gun_pid: gun_pid} = state
      ) do
    # Transition to websocket_connected
    case ConnectionManager.transition_to(state, :websocket_connected) do
      {:ok, new_state} ->
        MessageHandlers.handle_websocket_upgrade(gun_pid, stream_ref, headers, new_state)

      {:error, reason} ->
        Logger.error("Failed to transition state: #{inspect(reason)}")
        {:noreply, state}
    end
  end

  def handle_info({:gun_ws, gun_pid, stream_ref, frame}, %{gun_pid: gun_pid} = state) do
    MessageHandlers.handle_websocket_frame(gun_pid, stream_ref, frame, state)
  end

  def handle_info({:gun_error, gun_pid, stream_ref, reason}, %{gun_pid: gun_pid} = state) do
    # Clean up the stream that encountered an error
    state_with_cleanup = ConnectionState.remove_stream(state, stream_ref)
    MessageHandlers.handle_error(gun_pid, stream_ref, reason, state_with_cleanup)
  end

  def handle_info(
        {:gun_response, gun_pid, stream_ref, is_fin, status, headers},
        %{gun_pid: gun_pid} = state
      ) do
    MessageHandlers.handle_http_response(gun_pid, stream_ref, is_fin, status, headers, state)
  end

  def handle_info({:gun_data, gun_pid, stream_ref, is_fin, data}, %{gun_pid: gun_pid} = state) do
    MessageHandlers.handle_http_data(gun_pid, stream_ref, is_fin, data, state)
  end

  def handle_info({:reconnect, attempt}, state) do
    Logger.debug("Attempting reconnection, attempt #{attempt}")

    # Try to reconnect
    case initiate_connection(state) do
      {:ok, new_state} -> {:noreply, new_state}
      {:error, _reason, error_state} -> {:noreply, error_state}
    end
  end

  def handle_info(other, state) do
    Logger.debug("Unhandled message: #{inspect(other)}")
    {:noreply, state}
  end

  # Private functions

  defp handle_gun_message({:gun_up, pid, protocol}, state) do
    MessageHandlers.handle_connection_up(pid, protocol, state)
  end

  defp handle_gun_message(
         {:gun_down, pid, protocol, reason, killed_streams, unprocessed_streams},
         state
       ) do
    # Explicitly clean up any killed streams before passing to the handler
    state_with_cleanup =
      if killed_streams && is_list(killed_streams) do
        ConnectionState.remove_streams(state, killed_streams)
      else
        state
      end

    MessageHandlers.handle_connection_down(
      pid,
      protocol,
      reason,
      state_with_cleanup,
      killed_streams,
      unprocessed_streams
    )
  end

  defp handle_gun_message({:gun_upgrade, pid, stream_ref, ["websocket"], headers}, state) do
    MessageHandlers.handle_websocket_upgrade(pid, stream_ref, headers, state)
  end

  defp handle_gun_message({:gun_ws, pid, stream_ref, frame}, state) do
    MessageHandlers.handle_websocket_frame(pid, stream_ref, frame, state)
  end

  defp handle_gun_message({:gun_error, pid, stream_ref, reason}, state) do
    MessageHandlers.handle_error(pid, stream_ref, reason, state)
  end

  defp handle_gun_message(
         {:gun_response, pid, stream_ref, is_fin, status, headers},
         state
       ) do
    MessageHandlers.handle_http_response(pid, stream_ref, is_fin, status, headers, state)
  end

  defp handle_gun_message({:gun_data, pid, stream_ref, is_fin, data}, state) do
    MessageHandlers.handle_http_data(pid, stream_ref, is_fin, data, state)
  end

  defp handle_gun_message(_message, state) do
    # Unhandled message
    {:noreply, state}
  end

  # Initiates a connection with state transition
  defp initiate_connection(state) do
    # Let the ConnectionManager handle both the transition and connection attempt
    case ConnectionManager.start_connection(state) do
      {:ok, updated_state} -> {:ok, updated_state}
      {:error, reason, error_state} -> {:error, reason, error_state}
    end
  end

  # Handle possible reconnection based on connection state
  defp handle_possible_reconnection(state, _reason) do
    # Use ConnectionManager to determine if reconnection is appropriate
    case ConnectionManager.handle_reconnection(state) do
      {:ok, reconnect_after, reconnecting_state} ->
        # Schedule reconnection after the calculated delay
        Logger.debug(
          "Scheduling reconnection in #{reconnect_after}ms, attempt #{reconnecting_state.reconnect_attempts}"
        )

        # Send ourselves a delayed reconnect message
        Process.send_after(
          self(),
          {:reconnect, reconnecting_state.reconnect_attempts},
          reconnect_after
        )

        reconnecting_state

      {:error, error_reason, error_state} ->
        Logger.debug("Not reconnecting: #{inspect(error_reason)}")
        error_state
    end
  end

  defp headers_to_gun_format(headers) do
    Enum.map(headers, fn
      {key, value} when is_binary(key) -> {key, to_string(value)}
      {key, value} when is_atom(key) -> {to_string(key), to_string(value)}
      other -> other
    end)
  end
end
