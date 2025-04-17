defmodule WebSockexNova.Gun.Helpers.StateHelpers do
  @moduledoc """
  Helper functions for consistent state operations across the codebase.

  This module provides a single source of truth for common state update operations,
  ensuring that state mutations are consistent throughout the application.
  """

  alias WebSockexNova.Gun.ConnectionState

  @doc """
  Updates state for a successful connection.

  Performs standard updates when a connection is established:
  - Updates the Gun PID
  - Sets status to :connected
  - Resets reconnection attempts

  ## Parameters

  * `state` - The current connection state
  * `gun_pid` - The Gun connection process PID

  ## Returns

  Updated connection state
  """
  @spec handle_connection_established(ConnectionState.t(), pid()) :: ConnectionState.t()
  def handle_connection_established(state, gun_pid) do
    state
    |> ConnectionState.update_gun_pid(gun_pid)
    |> ConnectionState.update_status(:connected)
    |> ConnectionState.reset_reconnect_attempts()
  end

  @doc """
  Updates state for a connection failure.

  Performs standard updates when a connection fails:
  - Records the error reason
  - Sets status to :error

  ## Parameters

  * `state` - The current connection state
  * `reason` - The failure reason

  ## Returns

  Updated connection state
  """
  @spec handle_connection_failure(ConnectionState.t(), term()) :: ConnectionState.t()
  def handle_connection_failure(state, reason) do
    state
    |> ConnectionState.record_error(reason)
    |> ConnectionState.update_status(:error)
  end

  @doc """
  Updates state for a disconnection event.

  Performs standard updates when a connection is lost:
  - Records the disconnect reason
  - Sets status to :disconnected

  ## Parameters

  * `state` - The current connection state
  * `reason` - The disconnect reason

  ## Returns

  Updated connection state
  """
  @spec handle_disconnection(ConnectionState.t(), term()) :: ConnectionState.t()
  def handle_disconnection(state, reason) do
    state
    |> ConnectionState.record_error(reason)
    |> ConnectionState.update_status(:disconnected)
  end

  @doc """
  Updates state for a successful WebSocket upgrade.

  Performs standard updates when a WebSocket connection is established:
  - Updates the stream status to :websocket
  - Sets overall connection status to :websocket_connected

  ## Parameters

  * `state` - The current connection state
  * `stream_ref` - The stream reference for the WebSocket connection

  ## Returns

  Updated connection state
  """
  @spec handle_websocket_upgrade(ConnectionState.t(), reference()) :: ConnectionState.t()
  def handle_websocket_upgrade(state, stream_ref) do
    state
    |> ConnectionState.update_stream(stream_ref, :websocket)
    |> ConnectionState.update_status(:websocket_connected)
  end
end
