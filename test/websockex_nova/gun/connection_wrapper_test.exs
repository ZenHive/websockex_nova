defmodule WebsockexNova.Gun.ConnectionWrapperTest do
  use ExUnit.Case, async: false
  require Logger

  alias WebsockexNova.Gun.ConnectionWrapper
  alias WebsockexNova.Test.Support.MockWebSockServer

  @moduletag :integration

  @websocket_path "/ws"
  @default_delay 100

  test "basic connection and WebSocket functionality" do
    # Start a mock WebSock server
    {:ok, server_pid, port} = MockWebSockServer.start_link()

    try do
      # Start connection wrapper
      {:ok, conn_pid} = ConnectionWrapper.open("localhost", port)

      # Allow time for connection to establish
      Process.sleep(@default_delay)

      # Verify initial connection state
      state = ConnectionWrapper.get_state(conn_pid)
      assert state.status == :connected
      assert is_pid(state.gun_pid)

      # Upgrade to WebSocket
      {:ok, stream_ref} = ConnectionWrapper.upgrade_to_websocket(conn_pid, @websocket_path)
      Process.sleep(@default_delay * 2)

      # Verify WebSocket connection
      updated_state = ConnectionWrapper.get_state(conn_pid)
      assert updated_state.status == :websocket_connected
      assert Map.get(updated_state.active_streams, stream_ref) == :websocket

      # Send a message
      test_message = "Test message"
      :ok = ConnectionWrapper.send_frame(conn_pid, stream_ref, {:text, test_message})
      Process.sleep(@default_delay)

      # Properly close the connection
      ConnectionWrapper.close(conn_pid)
      Process.sleep(@default_delay)
    after
      # Make sure server is stopped
      Process.sleep(@default_delay)
      MockWebSockServer.stop(server_pid)
    end
  end

  test "handles different frame types" do
    {:ok, server_pid, port} = MockWebSockServer.start_link()

    try do
      # Start connection wrapper with callback to self
      {:ok, conn_pid} = ConnectionWrapper.open("localhost", port, %{callback_pid: self()})
      Process.sleep(@default_delay)

      # Upgrade to WebSocket
      {:ok, stream_ref} = ConnectionWrapper.upgrade_to_websocket(conn_pid, @websocket_path)
      Process.sleep(@default_delay * 2)

      # Test text frame
      :ok = ConnectionWrapper.send_frame(conn_pid, stream_ref, {:text, "Text message"})
      Process.sleep(@default_delay)

      # Test binary frame
      :ok = ConnectionWrapper.send_frame(conn_pid, stream_ref, {:binary, <<1, 2, 3, 4, 5>>})
      Process.sleep(@default_delay)

      # Test ping frame
      :ok = ConnectionWrapper.send_frame(conn_pid, stream_ref, :ping)
      Process.sleep(@default_delay)

      # Test pong frame
      :ok = ConnectionWrapper.send_frame(conn_pid, stream_ref, :pong)
      Process.sleep(@default_delay)

      # Properly close the connection
      ConnectionWrapper.close(conn_pid)
      Process.sleep(@default_delay)
    after
      Process.sleep(@default_delay)
      MockWebSockServer.stop(server_pid)
    end
  end

  test "handles invalid stream references gracefully" do
    {:ok, server_pid, port} = MockWebSockServer.start_link()

    try do
      # Start connection wrapper
      {:ok, conn_pid} = ConnectionWrapper.open("localhost", port)
      Process.sleep(@default_delay)

      # Create an invalid stream reference
      invalid_stream_ref = make_ref()

      # Try to send a frame with an invalid stream reference
      result = ConnectionWrapper.send_frame(conn_pid, invalid_stream_ref, {:text, "test"})
      assert result == {:error, :stream_not_found}

      # Properly close the connection
      ConnectionWrapper.close(conn_pid)
      Process.sleep(@default_delay)
    after
      Process.sleep(@default_delay)
      MockWebSockServer.stop(server_pid)
    end
  end

  test "transfers ownership of Gun process (T2.13)" do
    # Start a mock WebSock server
    {:ok, server_pid, port} = MockWebSockServer.start_link()

    try do
      # Create a test process to receive Gun messages after ownership transfer
      test_receiver = spawn_link(fn -> ownership_transfer_test_process() end)

      # Start connection wrapper
      {:ok, conn_pid} = ConnectionWrapper.open("localhost", port)
      Process.sleep(@default_delay)

      # Get current state
      state_before = ConnectionWrapper.get_state(conn_pid)
      assert is_pid(state_before.gun_pid)

      # Extract the gun_pid for verification
      gun_pid = state_before.gun_pid

      # Get initial monitor reference
      gun_monitor_ref_before = state_before.gun_monitor_ref
      assert is_reference(gun_monitor_ref_before)

      # Transfer ownership to our test process
      :ok = ConnectionWrapper.transfer_ownership(conn_pid, test_receiver)
      Process.sleep(@default_delay)

      # Get updated state
      state_after = ConnectionWrapper.get_state(conn_pid)

      # Monitor ref should be different after transfer
      refute gun_monitor_ref_before == state_after.gun_monitor_ref

      # Gun pid should remain the same
      assert gun_pid == state_after.gun_pid

      # Properly close the connection
      ConnectionWrapper.close(conn_pid)
      Process.sleep(@default_delay)
    after
      Process.sleep(@default_delay)
      MockWebSockServer.stop(server_pid)
    end
  end

  # Helper for ownership transfer test
  defp ownership_transfer_test_process do
    receive do
      _ -> ownership_transfer_test_process()
    end
  end
end
