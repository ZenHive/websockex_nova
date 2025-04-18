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
  alias WebsockexNova.Gun.ConnectionWrapper.ErrorHandler

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

  @doc """
  Receives ownership of a Gun connection from another process.

  ## Parameters

  * `pid` - The connection wrapper PID
  * `gun_pid` - PID of the Gun process being transferred

  ## Returns

  * `:ok` on success
  * `{:error, reason}` on failure
  """
  @spec receive_ownership(pid(), pid()) :: :ok | {:error, term()}
  def receive_ownership(pid, gun_pid) do
    GenServer.call(pid, {:receive_ownership, gun_pid})
  end

  @doc """
  Waits for the WebSocket upgrade to complete.

  This function uses gun:await/3 with an explicit monitor reference
  to avoid potential deadlocks during ownership transfers.

  ## Parameters

  * `pid` - The connection wrapper PID
  * `stream_ref` - Stream reference from the upgrade
  * `timeout` - Timeout in milliseconds (default: 5000)

  ## Returns

  * `{:ok, headers}` on successful upgrade
  * `{:error, reason}` on failure
  """
  @spec wait_for_websocket_upgrade(pid(), reference(), non_neg_integer()) ::
          {:ok, list()} | {:error, term()}
  def wait_for_websocket_upgrade(pid, stream_ref, timeout \\ 5000) do
    GenServer.call(pid, {:wait_for_websocket_upgrade, stream_ref, timeout})
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
          ErrorHandler.handle_stream_error(stream_ref, :stream_not_found, state)

        status ->
          ErrorHandler.handle_stream_error(stream_ref, {:invalid_stream_status, status}, state)
      end
    else
      ErrorHandler.handle_connection_error(:not_connected, state)
    end
  end

  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  def handle_call({:transfer_ownership, new_owner_pid}, _from, state) do
    cond do
      # Make sure we have a valid Gun PID
      is_nil(state.gun_pid) ->
        Logger.error("Cannot transfer ownership: no Gun process available")
        {:reply, {:error, :no_gun_pid}, state}

      # Make sure the target process is valid
      not is_pid(new_owner_pid) or not Process.alive?(new_owner_pid) ->
        Logger.error(
          "Cannot transfer ownership: invalid target process #{inspect(new_owner_pid)}"
        )

        {:reply, {:error, :invalid_target_process}, state}

      # Make sure the Gun process is still alive
      not Process.alive?(state.gun_pid) ->
        # Our monitor should have caught this, but let's be defensive
        Logger.error("Cannot transfer ownership: Gun process is no longer alive")
        {:reply, {:error, :gun_process_not_alive}, state}

      # All checks passed, proceed with transfer
      true ->
        # When we transfer ownership, we need to:
        # 1. Demonitor the old monitor reference if it exists
        if state.gun_monitor_ref do
          Process.demonitor(state.gun_monitor_ref, [:flush])
        end

        # 2. Create a new monitor for the gun process
        gun_monitor_ref = Process.monitor(state.gun_pid)

        # 3. Transfer ownership using the Gun API
        case :gun.set_owner(state.gun_pid, new_owner_pid) do
          :ok ->
            Logger.info(
              "Successfully transferred Gun process ownership to #{inspect(new_owner_pid)}"
            )

            # 4. Update our state with the new monitor reference
            updated_state = ConnectionState.update_gun_monitor_ref(state, gun_monitor_ref)

            # 5. Ensure both processes have required info by sending process info
            # This helps the new owner process build its own state
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

          {:error, reason} = error ->
            # If transfer failed, demonitor our new monitor and log the error
            Process.demonitor(gun_monitor_ref, [:flush])
            Logger.error("Failed to transfer Gun process ownership: #{inspect(reason)}")
            {:reply, error, state}
        end
    end
  end

  def handle_call({:receive_ownership, gun_pid}, _from, state) do
    # Validate parameters first
    if is_nil(gun_pid) or not is_pid(gun_pid) or not Process.alive?(gun_pid) do
      Logger.error("Invalid Gun PID or process not alive: #{inspect(gun_pid)}")
      {:reply, {:error, :invalid_gun_pid}, state}
    else
      # Create a monitor for the gun process
      gun_monitor_ref = Process.monitor(gun_pid)

      # Get information about the connection
      case :gun.info(gun_pid) do
        info when is_map(info) ->
          # Verify that we can actually set ourselves as the owner
          case :gun.set_owner(gun_pid, self()) do
            :ok ->
              # Update our state with the new gun_pid and monitor
              updated_state =
                state
                |> ConnectionState.update_gun_pid(gun_pid)
                |> ConnectionState.update_gun_monitor_ref(gun_monitor_ref)
                |> ConnectionState.update_status(:connected)

              Logger.info("Successfully received Gun connection ownership")
              {:reply, :ok, updated_state}

            {:error, reason} = error ->
              # If we can't set ourselves as owner, something is wrong
              Process.demonitor(gun_monitor_ref)
              Logger.error("Failed to set self as Gun owner: #{inspect(reason)}")
              {:reply, error, state}
          end

        {:error, reason} = error ->
          # If we can't get info, something is wrong
          Process.demonitor(gun_monitor_ref)
          Logger.error("Failed to get Gun process info: #{inspect(reason)}")
          {:reply, error, state}
      end
    end
  end

  def handle_call({:wait_for_websocket_upgrade, stream_ref, timeout}, _from, state) do
    if state.gun_pid do
      # Using the existing monitor for reliability
      monitor_ref = state.gun_monitor_ref

      case :gun.await(state.gun_pid, stream_ref, timeout, monitor_ref) do
        {:upgrade, ["websocket"], headers} ->
          # Update the stream status to indicate it's a websocket
          updated_state = ConnectionState.update_stream(state, stream_ref, :websocket)
          {:reply, {:ok, headers}, updated_state}

        {:response, status, headers} when status >= 400 ->
          # HTTP error response
          reason = {:http_error, status, headers}

          WebsockexNova.Gun.ConnectionWrapper.ErrorHandler.handle_upgrade_error(
            stream_ref,
            reason,
            state
          )

        {:error, reason} ->
          # Connection or timeout error
          WebsockexNova.Gun.ConnectionWrapper.ErrorHandler.handle_upgrade_error(
            stream_ref,
            reason,
            state
          )
      end
    else
      WebsockexNova.Gun.ConnectionWrapper.ErrorHandler.handle_connection_error(
        :not_connected,
        state
      )
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

        # Use schedule_reconnection instead of handle_possible_reconnection
        reconnect_callback = fn delay, _attempt ->
          Process.send_after(self(), {:reconnect, :timer}, delay)
        end

        new_state =
          ConnectionManager.schedule_reconnection(
            disconnected_state_with_cleanup,
            reconnect_callback
          )

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

        ErrorHandler.handle_transition_error(
          state.status,
          :disconnected,
          transition_reason,
          state
        )
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
        ErrorHandler.handle_transition_error(state.status, :websocket_connected, reason, state)
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
      {:ok, new_state} ->
        {:noreply, new_state}

      {:error, reason, error_state} ->
        Logger.error("Failed to reconnect: #{inspect(reason)}")
        ErrorHandler.handle_async_error(nil, {:reconnect_failed, reason}, error_state)
    end
  end

  def handle_info({:gun_info, info}, state) do
    # Use StateHelpers to handle the ownership transfer
    final_state = WebsockexNova.Gun.Helpers.StateHelpers.handle_ownership_transfer(state, info)
    {:noreply, final_state}
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
            # Schedule reconnection if needed
            reconnect_callback = fn delay, _attempt ->
              Process.send_after(self(), {:reconnect, :monitor}, delay)
            end

            new_state =
              ConnectionManager.schedule_reconnection(disconnected_state, reconnect_callback)

            # Notify the callback about connection down if available
            if new_state.callback_pid do
              MessageHandlers.notify(new_state.callback_pid, {:connection_down, :http, reason})
            end

            # If the reason is a crash, we might want to terminate this process as well
            # since Gun process was terminated unexpectedly
            if reason in [:crash, :killed, :shutdown] do
              {:stop, :gun_terminated, new_state}
            else
              {:noreply, new_state}
            end

          {:error, transition_reason} ->
            # Failed to transition, terminate this process as well
            ErrorHandler.handle_transition_error(
              state.status,
              :disconnected,
              transition_reason,
              state
            )

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

  defp headers_to_gun_format(headers) do
    Enum.map(headers, fn
      {key, value} when is_binary(key) -> {key, to_string(value)}
      {key, value} when is_atom(key) -> {to_string(key), to_string(value)}
      other -> other
    end)
  end
end
