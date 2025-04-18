defmodule WebsockexNova.Gun.ConnectionWrapper.MessageHandlersTest do
  use ExUnit.Case, async: true

  alias WebsockexNova.Gun.ConnectionState
  alias WebsockexNova.Gun.ConnectionWrapper.MessageHandlers

  defmodule MockCallbacks do
    @moduledoc false
    use GenServer

    def start_link do
      GenServer.start_link(__MODULE__, [])
    end

    def init(_) do
      {:ok, []}
    end

    def handle_info({:websockex_nova, message}, state) do
      # Store the messages in the state for checking in tests
      {:noreply, [message | state]}
    end

    def get_messages(pid) do
      GenServer.call(pid, :get_messages)
    end

    def handle_call(:get_messages, _from, messages) do
      {:reply, Enum.reverse(messages), messages}
    end

    def handle_call(:reset, _from, _messages) do
      {:reply, :ok, []}
    end

    def reset(pid) do
      GenServer.call(pid, :reset)
    end
  end

  setup do
    # Start the mock callbacks process
    {:ok, mock_pid} = MockCallbacks.start_link()
    state = ConnectionState.new("example.com", 443, %{callback_pid: mock_pid})
    %{state: state, mock_pid: mock_pid}
  end

  describe "connection lifecycle messages" do
    test "handle_connection_up/3 updates state and notifies callback", %{
      state: state,
      mock_pid: mock_pid
    } do
      protocol = :http
      gun_pid = self()

      result = MessageHandlers.handle_connection_up(gun_pid, protocol, state)

      # Verify state changes
      assert {:noreply, new_state} = result
      assert new_state.status == :connected

      # Verify callback was notified
      # Give the message time to be processed
      :timer.sleep(10)
      assert [message] = MockCallbacks.get_messages(mock_pid)
      assert message == {:connection_up, protocol}
    end

    test "handle_connection_down/4 updates state and notifies callback", %{
      state: state,
      mock_pid: mock_pid
    } do
      gun_pid = self()
      protocol = :http
      reason = :normal

      # Setup connected state
      connected_state = ConnectionState.update_status(state, :connected)

      result = MessageHandlers.handle_connection_down(gun_pid, protocol, reason, connected_state)

      # Verify state changes
      assert {:noreply, new_state} = result
      assert new_state.status == :disconnected
      assert new_state.last_error == reason

      # Verify callback was notified
      :timer.sleep(10)
      assert [message] = MockCallbacks.get_messages(mock_pid)
      assert message == {:connection_down, protocol, reason}
    end
  end

  describe "websocket messages" do
    test "handle_websocket_upgrade/4 updates state and notifies callback", %{
      state: state,
      mock_pid: mock_pid
    } do
      gun_pid = self()
      stream_ref = make_ref()
      headers = [{"sec-websocket-protocol", "json"}]

      # Setup stream in state
      state = ConnectionState.update_stream(state, stream_ref, :upgrading)

      result = MessageHandlers.handle_websocket_upgrade(gun_pid, stream_ref, headers, state)

      # Verify state changes
      assert {:noreply, new_state} = result
      assert new_state.status == :websocket_connected
      assert new_state.active_streams[stream_ref] == :websocket

      # Verify callback was notified
      :timer.sleep(10)
      assert [message] = MockCallbacks.get_messages(mock_pid)
      assert message == {:websocket_upgrade, stream_ref, headers}
    end

    test "handle_websocket_frame/4 notifies callback", %{state: state, mock_pid: mock_pid} do
      gun_pid = self()
      stream_ref = make_ref()
      frame = {:text, "Hello, WebSocket!"}

      result = MessageHandlers.handle_websocket_frame(gun_pid, stream_ref, frame, state)

      # Verify no state changes (returns same state)
      assert {:noreply, ^state} = result

      # Verify callback was notified
      :timer.sleep(10)
      assert [message] = MockCallbacks.get_messages(mock_pid)
      assert message == {:websocket_frame, stream_ref, frame}
    end
  end

  describe "error messages" do
    test "handle_error/4 updates state and notifies callback", %{state: state, mock_pid: mock_pid} do
      gun_pid = self()
      stream_ref = make_ref()
      reason = :timeout

      result = MessageHandlers.handle_error(gun_pid, stream_ref, reason, state)

      # Verify state changes
      assert {:noreply, new_state} = result
      assert new_state.last_error == reason

      # Verify callback was notified
      :timer.sleep(10)
      assert [message] = MockCallbacks.get_messages(mock_pid)
      assert message == {:error, stream_ref, reason}
    end
  end

  describe "http messages" do
    test "handle_http_response/5 notifies callback", %{state: state, mock_pid: mock_pid} do
      gun_pid = self()
      stream_ref = make_ref()
      is_fin = :fin
      status = 200
      headers = [{"content-type", "application/json"}]

      result =
        MessageHandlers.handle_http_response(gun_pid, stream_ref, is_fin, status, headers, state)

      # Verify no state changes (returns same state)
      assert {:noreply, ^state} = result

      # Verify callback was notified
      :timer.sleep(10)
      assert [message] = MockCallbacks.get_messages(mock_pid)
      assert message == {:http_response, stream_ref, is_fin, status, headers}
    end

    test "handle_http_data/5 notifies callback", %{state: state, mock_pid: mock_pid} do
      gun_pid = self()
      stream_ref = make_ref()
      is_fin = :fin
      data = ~s({"message":"Hello"})

      result = MessageHandlers.handle_http_data(gun_pid, stream_ref, is_fin, data, state)

      # Verify no state changes (returns same state)
      assert {:noreply, ^state} = result

      # Verify callback was notified
      :timer.sleep(10)
      assert [message] = MockCallbacks.get_messages(mock_pid)
      assert message == {:http_data, stream_ref, is_fin, data}
    end
  end

  describe "notification helper" do
    test "notify/3 sends message to callback process", %{state: state, mock_pid: mock_pid} do
      message = {:test_message, "Hello"}

      # Call the notify function directly
      :ok = MessageHandlers.notify(state.callback_pid, message)

      # Verify callback was notified
      :timer.sleep(10)
      assert [received_message] = MockCallbacks.get_messages(mock_pid)
      assert received_message == message
    end

    test "notify/3 handles nil callback pid", %{state: state} do
      # Modified state with nil callback_pid
      state = %{state | callback_pid: nil}
      message = {:test_message, "Hello"}

      # Should not raise any error
      assert :ok = MessageHandlers.notify(state.callback_pid, message)
    end
  end
end
