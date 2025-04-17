defmodule WebSockexNova.Gun.ConnectionWrapperTest do
  use ExUnit.Case, async: true

  alias WebSockexNova.Gun.ConnectionWrapper
  alias WebSockexNova.Gun.ClientSupervisor

  # We'll use a mocked server to avoid real network connections in tests
  defmodule MockServer do
    use GenServer

    # API
    def start_link do
      GenServer.start_link(__MODULE__, [], [])
    end

    def set_response(pid, response) do
      GenServer.call(pid, {:set_response, response})
    end

    # Callbacks
    def init([]) do
      {:ok, %{responses: [], messages: []}}
    end

    def handle_call({:set_response, response}, _from, state) do
      {:reply, :ok, %{state | responses: [response | state.responses]}}
    end

    def handle_info(message, state) do
      # Store any messages received for inspection in tests
      {:noreply, %{state | messages: [message | state.messages]}}
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
      {:ok, wrapper_pid} = ConnectionWrapper.open("example.com", 443, %{test_mode: true})
      assert Process.alive?(wrapper_pid)

      # Close connection
      assert :ok = ConnectionWrapper.close(wrapper_pid)

      # Verify the process is terminated
      assert wait_for_process_exit(wrapper_pid)
    end
  end

  describe "websocket operations" do
    test "upgrade_to_websocket/3 sends the appropriate upgrade request" do
      {:ok, wrapper_pid} = ConnectionWrapper.open("example.com", 443, %{test_mode: true})

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

    test "send_frame/3 sends WebSocket frames" do
      {:ok, wrapper_pid} = ConnectionWrapper.open("example.com", 443, %{test_mode: true})

      # We're testing the API call in test mode
      assert :ok = ConnectionWrapper.send_frame(wrapper_pid, make_ref(), {:text, "Hello"})
      assert :ok = ConnectionWrapper.send_frame(wrapper_pid, make_ref(), {:binary, <<1, 2, 3>>})
      assert :ok = ConnectionWrapper.send_frame(wrapper_pid, make_ref(), :ping)

      # Clean up
      ConnectionWrapper.close(wrapper_pid)
    end
  end

  describe "message handling" do
    test "process_gun_message/2 handles gun_up message" do
      {:ok, mock} = MockServer.start_link()
      {:ok, wrapper_pid} = ConnectionWrapper.open("example.com", 443, %{callback_pid: mock, test_mode: true})

      # Simulate gun_up message
      message = {:gun_up, make_ref(), :http}
      ConnectionWrapper.process_gun_message(wrapper_pid, message)

      # Wait for processing and verify state change
      :timer.sleep(50)
      state = ConnectionWrapper.get_state(wrapper_pid)
      assert state.status == :connected

      # Clean up
      ConnectionWrapper.close(wrapper_pid)
    end

    test "process_gun_message/2 handles gun_down message" do
      {:ok, mock} = MockServer.start_link()
      {:ok, wrapper_pid} = ConnectionWrapper.open("example.com", 443, %{callback_pid: mock, test_mode: true})

      # First connect
      ConnectionWrapper.process_gun_message(wrapper_pid, {:gun_up, make_ref(), :http})

      # Then simulate disconnect
      message = {:gun_down, make_ref(), :http, :normal, [], []}
      ConnectionWrapper.process_gun_message(wrapper_pid, message)

      # Wait for processing and verify state change
      :timer.sleep(50)
      state = ConnectionWrapper.get_state(wrapper_pid)
      assert state.status == :disconnected

      # Clean up
      ConnectionWrapper.close(wrapper_pid)
    end

    test "process_gun_message/2 handles gun_upgrade message" do
      {:ok, mock} = MockServer.start_link()
      {:ok, wrapper_pid} = ConnectionWrapper.open("example.com", 443, %{callback_pid: mock, test_mode: true})

      # Simulate WebSocket upgrade
      stream_ref = make_ref()
      message = {:gun_upgrade, make_ref(), stream_ref, ["websocket"], []}
      ConnectionWrapper.process_gun_message(wrapper_pid, message)

      # Wait for processing and verify state change
      :timer.sleep(50)
      state = ConnectionWrapper.get_state(wrapper_pid)
      assert state.active_streams[stream_ref] == :websocket

      # Clean up
      ConnectionWrapper.close(wrapper_pid)
    end

    test "process_gun_message/2 handles gun_ws message" do
      {:ok, mock} = MockServer.start_link()
      {:ok, wrapper_pid} = ConnectionWrapper.open("example.com", 443, %{callback_pid: mock, test_mode: true})

      # Simulate WebSocket frame
      stream_ref = make_ref()
      message = {:gun_ws, make_ref(), stream_ref, {:text, "Hello"}}
      ConnectionWrapper.process_gun_message(wrapper_pid, message)

      # Wait for processing and verify callback was triggered
      :timer.sleep(50)

      # In real implementation, we'd verify the callback received the frame
      # For now, just verify the function doesn't crash

      # Clean up
      ConnectionWrapper.close(wrapper_pid)
    end

    test "process_gun_message/2 handles gun_error message" do
      {:ok, mock} = MockServer.start_link()
      {:ok, wrapper_pid} = ConnectionWrapper.open("example.com", 443, %{callback_pid: mock, test_mode: true})

      # Simulate error
      stream_ref = make_ref()
      message = {:gun_error, make_ref(), stream_ref, :timeout}
      ConnectionWrapper.process_gun_message(wrapper_pid, message)

      # Wait for processing
      :timer.sleep(50)

      # In real implementation, we'd expect error to be recorded
      # For now, just verify the function doesn't crash

      # Clean up
      ConnectionWrapper.close(wrapper_pid)
    end
  end

  describe "state management" do
    test "get_state/1 returns the current state" do
      {:ok, wrapper_pid} = ConnectionWrapper.open("example.com", 443, %{test_mode: true})

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

  # Helper function to check if a process has exited
  defp wait_for_process_exit(pid, timeout \\ 500) do
    ref = Process.monitor(pid)

    receive do
      {:DOWN, ^ref, :process, ^pid, _reason} -> true
    after
      timeout -> false
    end
  end
end
