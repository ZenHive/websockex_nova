defmodule WebsockexNova.Gun.ConnectionWrapperTest do
  use ExUnit.Case, async: true

  alias WebsockexNova.Gun.ConnectionWrapper
  alias WebsockexNova.Test.Support.MockWebSockServer

  # Setup and helper functions for testing
  setup do
    # Start a MockWebSockServer for tests that need a real WebSocket server
    {:ok, server_pid, port} = MockWebSockServer.start_link()

    # Add port and hostname to test context
    {:ok,
     %{
       server_pid: server_pid,
       server_port: port,
       server_host: "localhost",
       path: "/ws"
     }}
  end

  # Helper function to create a connection wrapper in test mode
  defp start_test_connection(opts \\ %{}) do
    default_opts = %{test_mode: true}
    merged_opts = Map.merge(default_opts, opts)
    ConnectionWrapper.open("example.com", 443, merged_opts)
  end

  # Helper function to create a real connection wrapper to MockWebSockServer
  defp start_real_connection(ctx, opts \\ %{}) do
    default_opts = %{
      transport: :tcp,
      protocols: [:http],
      retry: 1,
      test_mode: false
    }

    merged_opts = Map.merge(default_opts, opts)
    ConnectionWrapper.open(ctx.server_host, ctx.server_port, merged_opts)
  end

  # Helper function to wait for process exit
  defp wait_for_process_exit(pid, timeout \\ 500) do
    ref = Process.monitor(pid)

    receive do
      {:DOWN, ^ref, :process, ^pid, _reason} -> true
    after
      timeout -> false
    end
  end

  describe "connection lifecycle" do
    test "open/4 establishes a connection to the server" do
      # Use test_mode to avoid real network connections
      host = "example.com"
      port = 443
      opts = %{transport: :tls, test_mode: true}

      assert {:ok, wrapper_pid} = ConnectionWrapper.open(host, port, opts)
      assert is_pid(wrapper_pid)

      # Verify the wrapper process is alive
      assert Process.alive?(wrapper_pid)

      # Clean up
      ConnectionWrapper.close(wrapper_pid)
    end

    test "close/1 disconnects from the server" do
      # Open connection in test mode
      {:ok, wrapper_pid} = start_test_connection()
      assert Process.alive?(wrapper_pid)

      # Close connection
      assert :ok = ConnectionWrapper.close(wrapper_pid)

      # Verify the process is terminated
      assert wait_for_process_exit(wrapper_pid)
    end

    test "connection to mock websocket server works",
         %{server_host: _host, server_port: _port} = ctx do
      # Use a real connection to the mock server
      {:ok, wrapper_pid} = start_real_connection(ctx)

      # Wait for connection establishment
      :timer.sleep(50)
      state = ConnectionWrapper.get_state(wrapper_pid)

      # Verify connection is established
      assert state.status in [:connected, :connecting]
      assert is_pid(state.gun_pid)

      # Clean up
      ConnectionWrapper.close(wrapper_pid)
      MockWebSockServer.stop(ctx.server_pid)
    end
  end

  describe "websocket operations" do
    test "upgrade_to_websocket/3 sends the appropriate upgrade request" do
      {:ok, wrapper_pid} = start_test_connection()

      # Set the connection as connected for testing
      ConnectionWrapper.set_status(wrapper_pid, :connected)

      # Request WebSocket upgrade
      path = "/websocket"
      headers = [{"authorization", "Bearer token123"}]

      assert {:ok, stream_ref} =
               ConnectionWrapper.upgrade_to_websocket(wrapper_pid, path, headers)

      # Verify stream_ref is returned
      assert is_reference(stream_ref)

      # Clean up
      ConnectionWrapper.close(wrapper_pid)
    end

    test "upgrade_to_websocket/3 with real server",
         %{server_host: _host, server_port: _port, path: path} = ctx do
      {:ok, wrapper_pid} = start_real_connection(ctx)

      # Wait for connection to be established
      :timer.sleep(100)

      # Request WebSocket upgrade
      headers = [{"authorization", "Bearer token123"}]
      {:ok, stream_ref} = ConnectionWrapper.upgrade_to_websocket(wrapper_pid, path, headers)

      # Verify stream_ref is returned
      assert is_reference(stream_ref)

      # Wait for the upgrade to complete
      :timer.sleep(100)
      state = ConnectionWrapper.get_state(wrapper_pid)

      # Verify the stream is tracked correctly
      assert Map.has_key?(state.active_streams, stream_ref)

      # Clean up
      ConnectionWrapper.close(wrapper_pid)
      MockWebSockServer.stop(ctx.server_pid)
    end

    test "send_frame/3 sends WebSocket frames" do
      {:ok, wrapper_pid} = start_test_connection()

      # We're testing the API call in test mode
      assert :ok = ConnectionWrapper.send_frame(wrapper_pid, make_ref(), {:text, "Hello"})
      assert :ok = ConnectionWrapper.send_frame(wrapper_pid, make_ref(), {:binary, <<1, 2, 3>>})
      assert :ok = ConnectionWrapper.send_frame(wrapper_pid, make_ref(), :ping)

      # Clean up
      ConnectionWrapper.close(wrapper_pid)
    end

    test "send_frame/3 with real server",
         %{server_host: _host, server_port: _port, path: path} = ctx do
      {:ok, wrapper_pid} = start_real_connection(ctx)

      # Wait for connection to be established
      :timer.sleep(100)

      # Request WebSocket upgrade
      {:ok, stream_ref} = ConnectionWrapper.upgrade_to_websocket(wrapper_pid, path, [])

      # Wait for the upgrade to complete
      :timer.sleep(100)

      # Send a text frame
      test_message = "Hello from test"
      :ok = ConnectionWrapper.send_frame(wrapper_pid, stream_ref, {:text, test_message})

      # Wait for the message to be processed
      :timer.sleep(50)

      # Verify the message was received by the server
      messages = MockWebSockServer.get_received_messages(ctx.server_pid)

      assert Enum.any?(messages, fn {_pid, type, message} ->
               type == :text && message == test_message
             end)

      # Clean up
      ConnectionWrapper.close(wrapper_pid)
      MockWebSockServer.stop(ctx.server_pid)
    end
  end

  describe "message handling" do
    test "process_gun_message/2 handles gun_up message" do
      # Create a callback pid to receive messages
      parent = self()
      callback_pid = spawn_link(fn -> message_receiver(parent, []) end)

      {:ok, wrapper_pid} =
        start_test_connection(%{callback_pid: callback_pid})

      # Simulate gun_up message
      gun_pid = make_ref()
      message = {:gun_up, gun_pid, :http}
      ConnectionWrapper.process_gun_message(wrapper_pid, message)

      # Wait for processing and verify state change
      :timer.sleep(50)
      state = ConnectionWrapper.get_state(wrapper_pid)
      assert state.status == :connected

      # Clean up
      ConnectionWrapper.close(wrapper_pid)

      # Check callback received the message
      send(callback_pid, :get_messages)

      assert_receive {:messages, messages}

      assert Enum.any?(messages, fn msg ->
               match?({:websockex_nova, {:connection_up, :http}}, msg)
             end)
    end

    test "process_gun_message/2 handles gun_down message" do
      # Create a callback pid to receive messages
      parent = self()
      callback_pid = spawn_link(fn -> message_receiver(parent, []) end)

      {:ok, wrapper_pid} =
        start_test_connection(%{callback_pid: callback_pid})

      # First connect
      gun_pid = make_ref()
      ConnectionWrapper.process_gun_message(wrapper_pid, {:gun_up, gun_pid, :http})

      # Then simulate disconnect
      message = {:gun_down, gun_pid, :http, :normal, [], []}
      ConnectionWrapper.process_gun_message(wrapper_pid, message)

      # Wait for processing and verify state change
      :timer.sleep(50)
      state = ConnectionWrapper.get_state(wrapper_pid)
      assert state.status == :disconnected

      # Clean up
      ConnectionWrapper.close(wrapper_pid)

      # Check callback received the message
      send(callback_pid, :get_messages)

      assert_receive {:messages, messages}

      assert Enum.any?(messages, fn msg ->
               match?({:websockex_nova, {:connection_down, :http, :normal}}, msg)
             end)
    end

    test "process_gun_message/2 handles gun_upgrade message" do
      # Create a callback pid to receive messages
      parent = self()
      callback_pid = spawn_link(fn -> message_receiver(parent, []) end)

      {:ok, wrapper_pid} =
        start_test_connection(%{callback_pid: callback_pid})

      # Simulate WebSocket upgrade
      gun_pid = make_ref()
      stream_ref = make_ref()
      fake_headers = [{"upgrade", "websocket"}, {"connection", "upgrade"}]
      message = {:gun_upgrade, gun_pid, stream_ref, ["websocket"], fake_headers}
      ConnectionWrapper.process_gun_message(wrapper_pid, message)

      # Wait for processing and verify state change
      :timer.sleep(50)
      state = ConnectionWrapper.get_state(wrapper_pid)
      assert state.active_streams[stream_ref] == :websocket

      # Clean up
      ConnectionWrapper.close(wrapper_pid)

      # Check callback received the message
      send(callback_pid, :get_messages)

      assert_receive {:messages, messages}

      assert Enum.any?(messages, fn msg ->
               match?({:websockex_nova, {:websocket_upgrade, ^stream_ref, _}}, msg)
             end)
    end

    test "process_gun_message/2 handles gun_ws message" do
      # Create a callback pid to receive messages
      parent = self()
      callback_pid = spawn_link(fn -> message_receiver(parent, []) end)

      {:ok, wrapper_pid} =
        start_test_connection(%{callback_pid: callback_pid})

      # Simulate WebSocket frame
      gun_pid = make_ref()
      stream_ref = make_ref()
      text_content = "Hello WebSocket"
      message = {:gun_ws, gun_pid, stream_ref, {:text, text_content}}
      ConnectionWrapper.process_gun_message(wrapper_pid, message)

      # Wait for processing
      :timer.sleep(50)

      # Clean up
      ConnectionWrapper.close(wrapper_pid)

      # Check callback received the frame
      send(callback_pid, :get_messages)

      assert_receive {:messages, messages}

      assert Enum.any?(messages, fn msg ->
               match?(
                 {:websockex_nova, {:websocket_frame, ^stream_ref, {:text, ^text_content}}},
                 msg
               )
             end)
    end

    test "process_gun_message/2 handles gun_error message" do
      # Create a callback pid to receive messages
      parent = self()
      callback_pid = spawn_link(fn -> message_receiver(parent, []) end)

      {:ok, wrapper_pid} =
        start_test_connection(%{callback_pid: callback_pid})

      # Simulate error
      gun_pid = make_ref()
      stream_ref = make_ref()
      error_reason = :timeout
      message = {:gun_error, gun_pid, stream_ref, error_reason}
      ConnectionWrapper.process_gun_message(wrapper_pid, message)

      # Wait for processing
      :timer.sleep(50)

      # Clean up
      ConnectionWrapper.close(wrapper_pid)

      # Check callback received the error
      send(callback_pid, :get_messages)

      assert_receive {:messages, messages}

      assert Enum.any?(messages, fn msg ->
               match?({:websockex_nova, {:error, ^stream_ref, ^error_reason}}, msg)
             end)
    end

    test "real connection receives messages from server",
         %{server_host: _host, server_port: _port, path: path} = ctx do
      # Create a callback pid to receive messages
      parent = self()
      callback_pid = spawn_link(fn -> message_receiver(parent, []) end)

      {:ok, wrapper_pid} = start_real_connection(ctx, %{callback_pid: callback_pid})

      # Wait for connection to be established
      :timer.sleep(100)

      # Request WebSocket upgrade
      {:ok, stream_ref} = ConnectionWrapper.upgrade_to_websocket(wrapper_pid, path, [])

      # Wait for the upgrade to complete
      :timer.sleep(100)

      # Send a message from the server to the client
      test_message = "Hello from server"
      MockWebSockServer.broadcast_text(ctx.server_pid, test_message)

      # Wait for message processing
      :timer.sleep(100)

      # Check callback received the message
      send(callback_pid, :get_messages)

      # Clean up
      ConnectionWrapper.close(wrapper_pid)
      MockWebSockServer.stop(ctx.server_pid)

      assert_receive {:messages, messages}

      assert Enum.any?(messages, fn msg ->
               case msg do
                 {:websockex_nova, {:websocket_frame, ^stream_ref, {:text, ^test_message}}} ->
                   true

                 _ ->
                   false
               end
             end)
    end
  end

  describe "state management" do
    test "get_state/1 returns the current state" do
      {:ok, wrapper_pid} = start_test_connection()

      # Get initial state
      state = ConnectionWrapper.get_state(wrapper_pid)
      assert is_map(state)
      assert state.host == "example.com"
      assert state.port == 443
      assert state.status == :initialized

      # Clean up
      ConnectionWrapper.close(wrapper_pid)
    end
  end

  describe "resource cleanup" do
    test "stream references are properly cleaned up on disconnect" do
      # Create a callback pid to receive messages
      parent = self()
      callback_pid = spawn_link(fn -> message_receiver(parent, []) end)

      {:ok, wrapper_pid} =
        start_test_connection(%{callback_pid: callback_pid})

      # First set the connection as connected
      ConnectionWrapper.set_status(wrapper_pid, :connected)

      # Create several stream references
      {:ok, stream_ref1} = ConnectionWrapper.upgrade_to_websocket(wrapper_pid, "/ws1", [])
      {:ok, stream_ref2} = ConnectionWrapper.upgrade_to_websocket(wrapper_pid, "/ws2", [])
      {:ok, stream_ref3} = ConnectionWrapper.upgrade_to_websocket(wrapper_pid, "/ws3", [])

      # Simulate WebSocket upgrade for all streams
      gun_pid = make_ref()

      ConnectionWrapper.process_gun_message(
        wrapper_pid,
        {:gun_upgrade, gun_pid, stream_ref1, ["websocket"], []}
      )

      ConnectionWrapper.process_gun_message(
        wrapper_pid,
        {:gun_upgrade, gun_pid, stream_ref2, ["websocket"], []}
      )

      ConnectionWrapper.process_gun_message(
        wrapper_pid,
        {:gun_upgrade, gun_pid, stream_ref3, ["websocket"], []}
      )

      # Verify streams are tracked
      :timer.sleep(50)
      state = ConnectionWrapper.get_state(wrapper_pid)
      assert map_size(state.active_streams) == 3

      # Simulate disconnect with killed streams
      ConnectionWrapper.process_gun_message(
        wrapper_pid,
        {:gun_down, gun_pid, :http, :normal, [stream_ref1, stream_ref2], []}
      )

      # Verify streams are cleaned up
      :timer.sleep(50)
      state = ConnectionWrapper.get_state(wrapper_pid)
      assert Map.get(state.active_streams, stream_ref1) == nil
      assert Map.get(state.active_streams, stream_ref2) == nil
      assert Map.get(state.active_streams, stream_ref3) != nil

      # Clean up
      ConnectionWrapper.close(wrapper_pid)
    end

    test "all stream references are cleaned up on close" do
      # Create a callback pid to receive messages
      parent = self()
      callback_pid = spawn_link(fn -> message_receiver(parent, []) end)

      {:ok, wrapper_pid} =
        start_test_connection(%{callback_pid: callback_pid})

      # Set up connection with streams
      ConnectionWrapper.set_status(wrapper_pid, :connected)

      # Add multiple streams
      {:ok, stream_ref1} = ConnectionWrapper.upgrade_to_websocket(wrapper_pid, "/ws1", [])
      {:ok, stream_ref2} = ConnectionWrapper.upgrade_to_websocket(wrapper_pid, "/ws2", [])

      # State check immediately after creating streams
      :timer.sleep(50)
      state_after_creation = ConnectionWrapper.get_state(wrapper_pid)
      assert map_size(state_after_creation.active_streams) == 2
      assert Map.has_key?(state_after_creation.active_streams, stream_ref1)
      assert Map.has_key?(state_after_creation.active_streams, stream_ref2)

      # Close connection
      ConnectionWrapper.close(wrapper_pid)

      # Give it time to clean up
      :timer.sleep(50)

      # Verify process terminated (which implies resources were cleaned)
      assert wait_for_process_exit(wrapper_pid)
    end

    test "resources are cleaned up on error conditions" do
      # Create a callback pid to receive messages
      parent = self()
      callback_pid = spawn_link(fn -> message_receiver(parent, []) end)

      {:ok, wrapper_pid} =
        start_test_connection(%{callback_pid: callback_pid})

      # Set up connection with streams
      ConnectionWrapper.set_status(wrapper_pid, :connected)

      # Add a stream
      {:ok, stream_ref} = ConnectionWrapper.upgrade_to_websocket(wrapper_pid, "/ws", [])

      # State check immediately after creating stream
      :timer.sleep(50)
      state_after_creation = ConnectionWrapper.get_state(wrapper_pid)
      assert map_size(state_after_creation.active_streams) == 1
      assert Map.has_key?(state_after_creation.active_streams, stream_ref)

      # Simulate a gun error on the stream
      gun_pid = make_ref()

      ConnectionWrapper.process_gun_message(
        wrapper_pid,
        {:gun_error, gun_pid, stream_ref, :timeout}
      )

      # Verify stream is removed
      :timer.sleep(50)
      state = ConnectionWrapper.get_state(wrapper_pid)
      assert Map.get(state.active_streams, stream_ref) == nil

      # Clean up
      ConnectionWrapper.close(wrapper_pid)
    end

    test "gun connection is terminated when wrapper is closed" do
      # Skip this test in test_mode since we don't actually create Gun connections
      # This test would be more comprehensive with a mock Gun module
      {:ok, wrapper_pid} = start_test_connection()

      # Mock a Gun connection
      fake_gun_pid = spawn(fn -> Process.sleep(10000) end)

      # Manually set the gun_pid in the state
      :sys.replace_state(wrapper_pid, fn state ->
        %{state | gun_pid: fake_gun_pid}
      end)

      # Monitor the fake gun process
      ref = Process.monitor(fake_gun_pid)

      # Close the wrapper
      ConnectionWrapper.close(wrapper_pid)

      # Verify the gun process is terminated
      assert_receive {:DOWN, ^ref, :process, ^fake_gun_pid, _reason}, 500
      assert wait_for_process_exit(wrapper_pid)
    end

    test "real gun process is terminated when wrapper is closed",
         %{server_host: _host, server_port: _port, path: _path} = ctx do
      {:ok, wrapper_pid} = start_real_connection(ctx)

      # Wait for connection to be established
      :timer.sleep(100)

      # Get the gun_pid
      state = ConnectionWrapper.get_state(wrapper_pid)
      assert is_pid(state.gun_pid)
      gun_pid = state.gun_pid

      # Monitor the gun process
      ref = Process.monitor(gun_pid)

      # Close the wrapper
      ConnectionWrapper.close(wrapper_pid)

      # Verify the gun process is terminated
      assert_receive {:DOWN, ^ref, :process, ^gun_pid, _reason}, 500

      # Clean up the server
      MockWebSockServer.stop(ctx.server_pid)
    end
  end

  describe "gun process ownership" do
    test "gun process ownership can be transferred",
         %{server_host: _host, server_port: _port, path: _path} = ctx do
      # Create a process to be the new owner
      parent = self()
      new_owner = spawn_link(fn -> gun_process_receiver(parent) end)

      # Start a connection with the MockWebSockServer
      {:ok, wrapper_pid} = start_real_connection(ctx)

      # Wait for connection to be established
      :timer.sleep(100)

      # Get the gun_pid
      state = ConnectionWrapper.get_state(wrapper_pid)
      assert is_pid(state.gun_pid)
      gun_pid = state.gun_pid

      # Transfer ownership to the new_owner
      :ok = :gun.set_owner(gun_pid, new_owner)

      # Send a WebSocket upgrade - the new owner should receive the response
      headers = []
      path = ctx.path
      :gun.ws_upgrade(gun_pid, path, headers)

      # Wait for the new owner to receive the upgrade
      :timer.sleep(100)

      # Ask the new owner what messages it received
      send(new_owner, :get_messages)

      # Verify the new owner received messages
      assert_receive {:gun_messages, messages}

      # There should be an upgrade message
      assert Enum.any?(messages, fn msg ->
               case msg do
                 {:gun_upgrade, ^gun_pid, _ref, ["websocket"], _headers} -> true
                 _ -> false
               end
             end)

      # Clean up
      send(new_owner, :stop)
      ConnectionWrapper.close(wrapper_pid)
      MockWebSockServer.stop(ctx.server_pid)
    end
  end

  # Helper function to collect messages for testing callbacks
  defp message_receiver(parent, messages) do
    receive do
      :get_messages ->
        send(parent, {:messages, messages})
        message_receiver(parent, messages)

      :stop ->
        send(parent, {:messages, messages})

      msg ->
        message_receiver(parent, [msg | messages])
    end
  end

  # Helper function to receive Gun messages for ownership tests
  defp gun_process_receiver(parent) do
    receive do
      :get_messages ->
        send(parent, {:gun_messages, Process.info(self(), :messages)})
        gun_process_receiver(parent)

      :stop ->
        :ok

      _msg ->
        gun_process_receiver(parent)
    end
  end
end
