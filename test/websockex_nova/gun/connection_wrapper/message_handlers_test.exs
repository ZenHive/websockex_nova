defmodule WebsockexNova.Gun.ConnectionWrapper.MessageHandlersTest do
  use ExUnit.Case, async: true

  alias WebsockexNova.Gun.ConnectionState
  alias WebsockexNova.Gun.ConnectionWrapper.MessageHandlers
  alias WebsockexNova.Telemetry.TelemetryEvents

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

  describe "telemetry events" do
    setup do
      test_pid = self()

      events = [
        TelemetryEvents.connection_open(),
        TelemetryEvents.connection_close(),
        TelemetryEvents.connection_websocket_upgrade(),
        TelemetryEvents.message_received(),
        TelemetryEvents.error_occurred()
      ]

      handler_id = make_ref()

      :telemetry.attach_many(
        handler_id,
        events,
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry_event, event, measurements, metadata})
        end,
        nil
      )

      on_exit(fn -> :telemetry.detach(handler_id) end)
      :ok
    end

    test "emits connection_open telemetry", %{state: state} do
      protocol = :http
      gun_pid = self()
      MessageHandlers.handle_connection_up(gun_pid, protocol, state)
      assert_receive {:telemetry_event, event, _meas, meta}, 100
      assert event == TelemetryEvents.connection_open()
      assert meta.connection_id == gun_pid
      assert meta.host == state.host
      assert meta.port == state.port
      assert meta.protocol == protocol
    end

    test "emits connection_close telemetry", %{state: state} do
      protocol = :http
      reason = :normal
      connected_state = ConnectionState.update_status(state, :connected)
      MessageHandlers.handle_connection_down(self(), protocol, reason, connected_state)
      assert_receive {:telemetry_event, event, _meas, meta}, 100
      assert event == TelemetryEvents.connection_close()
      assert meta.connection_id == connected_state.gun_pid
      assert meta.host == connected_state.host
      assert meta.port == connected_state.port
      assert meta.reason == reason
      assert meta.protocol == protocol
    end

    test "emits websocket_upgrade telemetry", %{state: state} do
      stream_ref = make_ref()
      headers = [{"sec-websocket-protocol", "json"}]
      state = ConnectionState.update_stream(state, stream_ref, :upgrading)
      MessageHandlers.handle_websocket_upgrade(self(), stream_ref, headers, state)
      assert_receive {:telemetry_event, event, _meas, meta}, 100
      assert event == TelemetryEvents.connection_websocket_upgrade()
      assert meta.connection_id == state.gun_pid
      assert meta.stream_ref == stream_ref
      assert meta.headers == headers
    end

    test "emits message_received telemetry", %{state: state} do
      stream_ref = make_ref()
      frame = {:text, "Hello, WebSocket!"}
      MessageHandlers.handle_websocket_frame(self(), stream_ref, frame, state)
      assert_receive {:telemetry_event, event, meas, meta}, 100
      assert event == TelemetryEvents.message_received()
      assert meta.connection_id == self()
      assert meta.stream_ref == stream_ref
      assert meta.frame_type == :text
      assert meas.size == byte_size("Hello, WebSocket!")
    end

    test "emits error_occurred telemetry", %{state: state} do
      stream_ref = make_ref()
      reason = :timeout
      MessageHandlers.handle_error(self(), stream_ref, reason, state)
      assert_receive {:telemetry_event, event, _meas, meta}, 100
      assert event == TelemetryEvents.error_occurred()
      assert meta.connection_id == state.gun_pid
      assert meta.stream_ref == stream_ref
      assert meta.reason == reason
      assert is_map(meta.context)
      assert meta.context.host == state.host
      assert meta.context.port == state.port
    end
  end
end
