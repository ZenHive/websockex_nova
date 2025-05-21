defmodule WebsockexNova.Gun.ConnectionWrapperReconnectionRaceTest do
  @moduledoc """
  Tests for the reconnection race condition that can occur when multiple reconnection
  attempts are triggered simultaneously or in rapid succession.

  Specifically, this tests the case where:
  1. A connection is established (:connected state)
  2. A reconnection attempt is triggered while the connection is already in a valid state
  3. The invalid state transition is handled gracefully
  """
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias WebsockexNova.Gun.ConnectionWrapper
  alias WebsockexNova.Test.Support.MockWebSockServer

  @websocket_path "/ws"
  @default_delay 100

  setup do
    {:ok, server_pid, port} = MockWebSockServer.start_link()

    on_exit(fn ->
      Process.sleep(@default_delay)

      try do
        if is_pid(server_pid) and Process.alive?(server_pid), do: MockWebSockServer.stop(server_pid)
      catch
        :exit, _ -> :ok
      end
    end)

    # Register this test process to receive all notifications
    Process.register(self(), :test_process)

    %{port: port, server_pid: server_pid}
  end

  @tag :reconnection_race
  test "multiple simultaneous reconnection attempts are handled gracefully", %{port: port} do
    log =
      capture_log(fn ->
        # Open a connection and get the Gun PID
        {:ok, conn} = ConnectionWrapper.open("localhost", port, @websocket_path, %{callback_pid: self(), transport: :tcp})
        state = ConnectionWrapper.get_state(conn)
        gun_pid = state.gun_pid
        assert is_pid(gun_pid)
        assert_connection_status(conn, :websocket_connected)

        # Clear any existing messages
        flush_mailbox()

        # Force it to disconnect
        Process.exit(gun_pid, :kill)

        # Wait for the disconnection to be detected
        assert_connection_status(conn, :disconnected, 2000)

        # Wait a moment for the first reconnection attempt to start
        Process.sleep(50)

        # Send multiple reconnect messages manually to simulate race condition
        for source <- [:timer, :manual_1, :manual_2, :manual_3] do
          send(conn.transport_pid, {:reconnect, source})
        end

        # Wait for reconnection to complete
        assert_connection_status(conn, :websocket_connected, 5000)

        # Check we get only one successful reconnection message
        assert_receive {:connection_reconnected, _reconnected_conn}, 5000

        # Ensure there are no unhandled errors
        refute_receive {:error, _, {:reconnect_failed, :invalid_transition, _}}, 500

        # Verify connection is still usable
        updated_state = ConnectionWrapper.get_state(conn)
        assert is_pid(updated_state.gun_pid)
        assert Process.alive?(conn.transport_pid)

        # Clean up
        ConnectionWrapper.close(conn)
      end)

    # The fix should prevent these errors from appearing in the logs
    refute log =~ "[error] [ERROR] :invalid_transition | %{to: :connecting, from: :connected}"
    refute log =~ "[error] [ERROR] :connection_failed | %{reason: :invalid_transition}"
  end

  # Helper function to assert connection status with a timeout
  defp assert_connection_status(conn, expected_status, timeout \\ 500) do
    assert_status_with_timeout(conn, expected_status, timeout, 0)
  end

  defp assert_status_with_timeout(conn, expected_status, timeout, elapsed) when elapsed >= timeout do
    state = ConnectionWrapper.get_state(conn)
    flunk("Connection status timeout: expected #{expected_status}, got #{state.status}")
  end

  defp assert_status_with_timeout(conn, expected_status, timeout, elapsed) do
    state = ConnectionWrapper.get_state(conn)

    if state.status == expected_status do
      true
    else
      sleep_time = min(50, timeout - elapsed)
      Process.sleep(sleep_time)
      assert_status_with_timeout(conn, expected_status, timeout, elapsed + sleep_time)
    end
  end

  # Helper function to flush all messages from the mailbox
  defp flush_mailbox do
    receive do
      _ -> flush_mailbox()
    after
      0 -> :ok
    end
  end
end
