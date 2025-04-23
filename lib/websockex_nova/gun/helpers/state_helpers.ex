defmodule WebsockexNova.Gun.Helpers.StateHelpers do
  @moduledoc """
  Helper functions for consistent state operations across the codebase.

  This module provides a single source of truth for common state update operations,
  ensuring that state mutations are consistent throughout the application.

  It also includes standardized logging for state transitions to maintain
  consistent log messages and log levels across the application.
  """

  alias WebsockexNova.Gun.ConnectionState

  require Logger

  @doc """
  Updates state for a successful connection.

  Performs standard updates when a connection is established:
  - Updates the Gun PID
  - Sets status to :connected
  - Resets reconnection attempts
  - Logs the connection establishment

  ## Parameters

  * `state` - The current connection state
  * `gun_pid` - The Gun connection process PID

  ## Returns

  Updated connection state
  """
  @spec handle_connection_established(ConnectionState.t(), pid()) :: ConnectionState.t()
  def handle_connection_established(state, gun_pid) do
    log_state_transition(
      state,
      :connected,
      "Connection established to #{state.host}:#{state.port}"
    )

    state
    |> ConnectionState.update_gun_pid(gun_pid)
    |> ConnectionState.update_status(:connected)
  end

  @doc """
  Updates state for a connection failure.

  Performs standard updates when a connection fails:
  - Records the error reason
  - Sets status to :error
  - Logs the failure with the reason

  ## Parameters

  * `state` - The current connection state
  * `reason` - The failure reason

  ## Returns

  Updated connection state
  """
  @spec handle_connection_failure(ConnectionState.t(), term()) :: ConnectionState.t()
  def handle_connection_failure(state, reason) do
    log_state_transition(
      state,
      :error,
      "Connection failed to #{state.host}:#{state.port}. Reason: #{inspect(reason)}",
      :error
    )

    state
    |> ConnectionState.record_error(reason)
    |> ConnectionState.update_status(:error)
  end

  @doc """
  Updates state for a disconnection event.

  Performs standard updates when a connection is lost:
  - Records the disconnect reason
  - Sets status to :disconnected
  - Logs the disconnection with the reason

  ## Parameters

  * `state` - The current connection state
  * `reason` - The disconnect reason

  ## Returns

  Updated connection state
  """
  @spec handle_disconnection(ConnectionState.t(), term()) :: ConnectionState.t()
  def handle_disconnection(state, reason) do
    log_state_transition(
      state,
      :disconnected,
      "Connection to #{state.host}:#{state.port} lost. Reason: #{inspect(reason)}"
    )

    state
    |> ConnectionState.record_error(reason)
    |> ConnectionState.update_status(:disconnected)
  end

  @doc """
  Updates state for a successful WebSocket upgrade.

  Performs standard updates when a WebSocket connection is established:
  - Updates the stream status to :websocket
  - Sets overall connection status to :websocket_connected
  - Logs the WebSocket upgrade

  ## Parameters

  * `state` - The current connection state
  * `stream_ref` - The stream reference for the WebSocket connection

  ## Returns

  Updated connection state
  """
  @spec handle_websocket_upgrade(ConnectionState.t(), reference()) :: ConnectionState.t()
  def handle_websocket_upgrade(state, stream_ref) do
    log_state_transition(
      state,
      :websocket_connected,
      "WebSocket connection established to #{state.host}:#{state.port}"
    )

    state
    |> ConnectionState.update_stream(stream_ref, :websocket)
    |> ConnectionState.update_status(:websocket_connected)
  end

  @doc """
  Updates state for a reconnection attempt.

  Performs standard updates when attempting to reconnect:
  - Increments the reconnection attempt counter
  - Sets status to :reconnecting
  - Logs the reconnection attempt with the attempt number

  ## Parameters

  * `state` - The current connection state

  ## Returns

  Updated connection state
  """
  @spec handle_reconnection_attempt(ConnectionState.t()) :: ConnectionState.t()
  def handle_reconnection_attempt(state) do
    new_state = ConnectionState.update_status(state, :reconnecting)

    log_state_transition(
      state,
      :reconnecting,
      "Attempting to reconnect to #{state.host}:#{state.port} (attempt #{new_state.reconnect_attempts})"
    )

    new_state
  end

  @doc """
  Updates state when receiving connection ownership info from another process.

  This function is critical for proper Gun process ownership transfer between
  processes. When a process transfers Gun ownership, it sends a `:gun_info`
  message containing state details to help rebuild the state in the new owner.

  The function:
  1. Validates that required information is present in the info map
  2. Updates the connection state with Gun PID and connection status
  3. Ensures a proper process monitor is established
  4. Migrates active streams information if available

  ## Parameters

  * `state` - The current connection state
  * `info` - Connection info map from previous owner with the following keys:
    * `:gun_pid` - (required) The Gun process PID
    * `:status` - (required) Current connection status
    * `:host` - Hostname of connection
    * `:port` - Port of connection
    * `:options` - Connection options
    * `:active_streams` - Map of active stream references

  ## Returns

  Updated connection state

  ## Examples

      iex> handle_ownership_transfer(state, %{gun_pid: pid, status: :connected})
      %ConnectionState{gun_pid: pid, status: :connected, ...}

  """
  @spec handle_ownership_transfer(ConnectionState.t(), map()) :: ConnectionState.t()
  def handle_ownership_transfer(state, info) do
    if valid_ownership_info?(info) do
      log_state_transition(
        state,
        info.status,
        "Received Gun connection ownership from another process"
      )

      updated_state =
        state
        |> ConnectionState.update_gun_pid(info.gun_pid)
        |> ConnectionState.update_status(info.status)

      updated_state_with_monitor =
        update_monitor_if_needed(state, updated_state)

      update_active_streams_if_needed(updated_state_with_monitor, info)
    else
      log_event(:error, :invalid_ownership_transfer_info, %{info: info}, state)
      state
    end
  end

  defp valid_ownership_info?(info) do
    is_map(info) and Map.has_key?(info, :gun_pid) and Map.has_key?(info, :status)
  end

  defp update_monitor_if_needed(state, updated_state) do
    if updated_state.gun_monitor_ref do
      if state.gun_pid != nil and updated_state.gun_pid != state.gun_pid do
        Process.demonitor(updated_state.gun_monitor_ref, [:flush])
        monitor_ref = Process.monitor(updated_state.gun_pid)
        ConnectionState.update_gun_monitor_ref(updated_state, monitor_ref)
      else
        updated_state
      end
    else
      monitor_ref = Process.monitor(updated_state.gun_pid)
      ConnectionState.update_gun_monitor_ref(updated_state, monitor_ref)
    end
  end

  defp update_active_streams_if_needed(state, info) do
    if Map.has_key?(info, :active_streams) and map_size(info.active_streams) > 0 do
      ConnectionState.update_active_streams(state, info.active_streams)
    else
      state
    end
  end

  # Private helper functions

  # Logging helpers
  defp log_event(:connection, event, context, state) do
    if Map.has_key?(state, :logging_handler) and function_exported?(state.logging_handler, :log_connection_event, 3) do
      state.logging_handler.log_connection_event(event, context, state)
    else
      Logger.info("[CONNECTION] #{inspect(event)} | #{inspect(context)}")
    end
  end

  # defp log_event(:message, event, context, state) do
  #   if Map.has_key?(state, :logging_handler) and function_exported?(state.logging_handler, :log_message_event, 3) do
  #     state.logging_handler.log_message_event(event, context, state)
  #   else
  #     Logger.debug("[MESSAGE] #{inspect(event)} | #{inspect(context)}")
  #   end
  # end

  defp log_event(:error, event, context, state) do
    if Map.has_key?(state, :logging_handler) and function_exported?(state.logging_handler, :log_error_event, 3) do
      state.logging_handler.log_error_event(event, context, state)
    else
      Logger.error("[ERROR] #{inspect(event)} | #{inspect(context)}")
    end
  end

  # Logs state transitions with standardized format and appropriate log level
  defp log_state_transition(state, new_status, message, _level \\ :debug) do
    metadata = %{
      host: state.host,
      port: state.port,
      from_status: state.status,
      to_status: new_status
    }

    metadata =
      if Map.has_key?(state, :trace_id),
        do: Map.put(metadata, :trace_id, state.trace_id),
        else: metadata

    log_event(:connection, :state_transition, %{message: message, metadata: metadata}, state)
  end
end
