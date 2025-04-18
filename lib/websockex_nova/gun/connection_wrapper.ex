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
          optional(:backoff_type) => :linear | :exponential | :jittered,
          optional(:base_backoff) => non_neg_integer()
        }

  @default_options %{
    transport: :tcp,
    transport_opts: [],
    protocols: [:http],
    retry: 5,
    ws_opts: %{},
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

  @doc """
  Transfers ownership of the Gun connection to another process.

  After transferring ownership, the target process will receive all Gun messages.
  This function also updates the monitor reference to track the connection
  in its new location.

  ## Parameters

  * `pid` - The connection wrapper PID
  * `new_owner_pid` - PID of the process that should become the new owner

  ## Returns

  * `:ok` on success
  * `{:error, reason}` on failure
  """
  @spec transfer_ownership(pid(), pid()) :: :ok | {:error, term()}
  def transfer_ownership(pid, new_owner_pid) do
    GenServer.call(pid, {:transfer_ownership, new_owner_pid})
  end

  # Server callbacks

  @impl true
  def init({host, port, options, _supervisor}) do
    merged_options = Map.merge(@default_options, options)
    state = ConnectionState.new(host, port, merged_options)

    case initiate_connection(state) do
      {:ok, updated_state} ->
        {:ok, updated_state}

      {:error, reason, error_state} ->
        Logger.error("Failed to open connection: #{inspect(reason)}")
        {:ok, error_state}
    end
  end

  @impl true
  def handle_call({:upgrade_to_websocket, path, headers}, _from, state) do
    if state.gun_pid && state.status == :connected do
      stream_ref =
        :gun.ws_upgrade(
          state.gun_pid,
          path,
          headers_to_gun_format(headers),
          state.options.ws_opts
        )

      # Update state with stream reference
      updated_state = ConnectionState.update_stream(state, stream_ref, :upgrading)

      {:reply, {:ok, stream_ref}, updated_state}
    else
      {:reply, {:error, :not_connected}, state}
    end
  end

  def handle_call({:send_frame, stream_ref, frame}, _from, state) do
    if state.gun_pid do
      case Map.get(state.active_streams, stream_ref) do
        :websocket ->
          result = :gun.ws_send(state.gun_pid, stream_ref, frame)
          {:reply, result, state}

        nil ->
          {:reply, {:error, :stream_not_found}, state}

        status ->
          {:reply, {:error, {:invalid_stream_status, status}}, state}
      end
    else
      {:reply, {:error, :not_connected}, state}
    end
  end

  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  def handle_call({:transfer_ownership, new_owner_pid}, _from, state) do
    if state.gun_pid do
      case :gun.set_owner(state.gun_pid, new_owner_pid) do
        :ok ->
          # When we transfer ownership, we need to:
          # 1. Demonitor the old monitor reference if it exists
          # 2. Create a new monitor for the gun process
          if state.gun_monitor_ref do
            Process.demonitor(state.gun_monitor_ref)
          end

          # Create new monitor
          gun_monitor_ref = Process.monitor(state.gun_pid)
          updated_state = ConnectionState.update_gun_monitor_ref(state, gun_monitor_ref)
          {:reply, :ok, updated_state}

        {:error, reason} = error ->
          Logger.error("Failed to transfer Gun process ownership: #{inspect(reason)}")
          {:reply, error, state}
      end
    else
      {:reply, {:error, :no_gun_pid}, state}
    end
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
    {:noreply, new_state} = MessageHandlers.handle_connection_up(gun_pid, protocol, state)
    {:noreply, new_state}
  end

  def handle_info(
        {:gun_down, gun_pid, protocol, reason, killed_streams, unprocessed_streams},
        %{gun_pid: gun_pid} = state
      ) do
    case ConnectionManager.transition_to(state, :disconnected, %{reason: reason}) do
      {:ok, disconnected_state} ->
        disconnected_state_with_cleanup =
          if killed_streams && is_list(killed_streams) do
            ConnectionState.remove_streams(disconnected_state, killed_streams)
          else
            disconnected_state
          end

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

  def handle_info({:reconnect, _attempt}, state) do
    case initiate_connection(state) do
      {:ok, new_state} -> {:noreply, new_state}
      {:error, _reason, error_state} -> {:noreply, error_state}
    end
  end

  def handle_info({:debug_check_mailbox, pid}, state) do
    info = Process.info(pid, [:message_queue_len, :messages])
    Logger.info("Process #{inspect(pid)} info: #{inspect(info)}")

    {:noreply, state}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, pid, reason}, state) do
    cond do
      # If it's our monitored Gun process that died
      state.gun_monitor_ref == ref and state.gun_pid == pid ->
        Logger.error("Gun process terminated: #{inspect(reason)}")

        # Try to transition to disconnected state first
        case ConnectionManager.transition_to(state, :disconnected, %{reason: reason}) do
          {:ok, disconnected_state} ->
            # Handle possible reconnection if needed
            new_state = handle_possible_reconnection(disconnected_state, reason)

            # Notify the callback about connection down if available
            if new_state.callback_pid do
              send(new_state.callback_pid, {:websockex_nova, {:connection_down, :http, reason}})
            end

            # If the reason is a crash, we might want to terminate this process as well
            # since Gun process was terminated unexpectedly
            if reason in [:crash, :killed, :shutdown] do
              {:stop, :gun_terminated, new_state}
            else
              {:noreply, new_state}
            end

          {:error, _transition_error} ->
            # Failed to transition, terminate this process as well
            {:stop, :gun_terminated, state}
        end

      # Other DOWN messages that aren't for our gun process
      true ->
        {:noreply, state}
    end
  end

  def handle_info(other, state) do
    Logger.warning("Unhandled message in ConnectionWrapper: #{inspect(other)}")
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
    {:noreply, state}
  end

  defp initiate_connection(state) do
    case ConnectionManager.start_connection(state) do
      {:ok, updated_state} -> {:ok, updated_state}
      {:error, reason, error_state} -> {:error, reason, error_state}
    end
  end

  defp handle_possible_reconnection(state, _reason) do
    case ConnectionManager.handle_reconnection(state) do
      {:ok, reconnect_after, reconnecting_state} ->
        Process.send_after(
          self(),
          {:reconnect, reconnecting_state.reconnect_attempts},
          reconnect_after
        )

        reconnecting_state

      {:error, _error_reason, error_state} ->
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
