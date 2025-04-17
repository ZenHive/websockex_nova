defmodule WebsockexNova.Gun.Helpers.StateHelpersTest do
  use ExUnit.Case, async: true

  alias WebsockexNova.Gun.ConnectionState
  alias WebsockexNova.Gun.Helpers.StateHelpers

  describe "state transition helpers" do
    setup do
      state = ConnectionState.new("test-host.com", 443, %{transport: :tls})
      %{state: state}
    end

    test "handle_connection_established/2 updates state correctly", %{state: state} do
      gun_pid = self()

      updated_state = StateHelpers.handle_connection_established(state, gun_pid)

      assert updated_state.gun_pid == gun_pid
      assert updated_state.status == :connected
      assert updated_state.reconnect_attempts == 0
    end

    test "handle_connection_failure/2 updates state correctly", %{state: state} do
      reason = :econnrefused

      updated_state = StateHelpers.handle_connection_failure(state, reason)

      assert updated_state.status == :error
      assert updated_state.last_error == reason
    end

    test "handle_disconnection/2 updates state with disconnect reason", %{state: state} do
      reason = :normal

      updated_state = StateHelpers.handle_disconnection(state, reason)

      assert updated_state.status == :disconnected
      assert updated_state.last_error == reason
    end

    test "handle_websocket_upgrade/2 updates stream and state", %{state: state} do
      stream_ref = make_ref()

      updated_state = StateHelpers.handle_websocket_upgrade(state, stream_ref)

      assert updated_state.status == :websocket_connected
      assert Map.get(updated_state.active_streams, stream_ref) == :websocket
    end
  end

  describe "stateful operations" do
    test "reconnection counter is preserved through transitions" do
      # Create initial state with 2 reconnection attempts
      state =
        ConnectionState.new("test-host.com", 443, %{transport: :tls})
        |> ConnectionState.increment_reconnect_attempts()
        |> ConnectionState.increment_reconnect_attempts()

      assert state.reconnect_attempts == 2

      # When connection is established, counter should be reset
      updated_state = StateHelpers.handle_connection_established(state, self())
      assert updated_state.reconnect_attempts == 0

      # When disconnected, counter should be preserved
      disconnected_state = StateHelpers.handle_disconnection(updated_state, :timeout)
      assert disconnected_state.reconnect_attempts == 0
    end

    test "error transitions preserve existing data" do
      # Create state with existing data
      gun_pid = self()
      stream_ref = make_ref()

      state =
        ConnectionState.new("test-host.com", 443, %{transport: :tls})
        |> ConnectionState.update_gun_pid(gun_pid)
        |> ConnectionState.update_stream(stream_ref, :upgrading)

      # When error occurs, should preserve gun_pid and active streams
      error_state = StateHelpers.handle_connection_failure(state, :fatal_error)

      assert error_state.status == :error
      assert error_state.last_error == :fatal_error
      assert error_state.gun_pid == gun_pid
      assert error_state.active_streams[stream_ref] == :upgrading
    end
  end
end
