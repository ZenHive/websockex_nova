defmodule WebsockexNova.Gun.BehaviorBridgeTest do
  use ExUnit.Case, async: true

  alias WebsockexNova.Gun.BehaviorBridge
  alias WebsockexNova.Gun.ConnectionState

  # Create test implementations of the behaviours
  defmodule TestConnectionHandler do
    @moduledoc false
    @behaviour WebsockexNova.Behaviours.ConnectionHandler

    @impl true
    def init(opts) do
      # Store test process PID for sending messages back
      state = %{
        events: [],
        test_pid: opts[:test_pid]
      }

      {:ok, state}
    end

    @impl true
    def status(stream_ref, state) do
      {:status, stream_ref, state}
    end

    @impl true
    def handle_connect(conn_info, state) do
      # Record the event and notify the test process
      state = Map.update!(state, :events, &[{:connect, conn_info} | &1])
      send(state.test_pid, {:handler_event, :connect, conn_info})
      {:ok, state}
    end

    @impl true
    def handle_disconnect(reason, state) do
      # Record the event and notify the test process
      state = Map.update!(state, :events, &[{:disconnect, reason} | &1])
      send(state.test_pid, {:handler_event, :disconnect, reason})

      # Return reconnect if specified in opts
      if Map.get(state, :should_reconnect, false) do
        {:reconnect, state}
      else
        {:ok, state}
      end
    end

    @impl true
    def handle_frame(frame_type, frame_data, state) do
      # Record the event and notify the test process
      state = Map.update!(state, :events, &[{:frame, frame_type, frame_data} | &1])
      send(state.test_pid, {:handler_event, :frame, {frame_type, frame_data}})

      # Send a response if should_reply is set
      if Map.get(state, :should_reply, false) do
        {:reply, :text, "response", state}
      else
        {:ok, state}
      end
    end

    @impl true
    def handle_timeout(state) do
      # Record the event and notify the test process
      state = Map.update!(state, :events, &[{:timeout} | &1])
      send(state.test_pid, {:handler_event, :timeout})
      {:ok, state}
    end
  end

  defmodule TestMessageHandler do
    @moduledoc false
    @behaviour WebsockexNova.Behaviours.MessageHandler

    @impl true
    def handle_message(message, state) do
      # Record the event and notify the test process
      send(state.test_pid, {:handler_event, :message, message})

      # Send a response if should_reply is set
      if Map.get(state, :should_reply, false) do
        {:reply, {:response, message}, state}
      else
        {:ok, state}
      end
    end

    @impl true
    def validate_message(message) do
      # Simply pass through the message
      {:ok, message}
    end

    @impl true
    def message_type(message) when is_map(message) do
      # Extract the type field or default to :unknown
      Map.get(message, "type", :unknown)
    end

    def message_type(_) do
      :unknown
    end

    @impl true
    def encode_message({:response, message}, _state) do
      # Encode as a JSON response
      data = Jason.encode!(%{response: true, original: message})
      {:ok, :text, data}
    end

    def encode_message(message, _state) do
      # Default encoding of messages
      {:ok, :text, Jason.encode!(message)}
    end
  end

  defmodule TestErrorHandler do
    @moduledoc false
    @behaviour WebsockexNova.Behaviours.ErrorHandler

    @impl true
    def handle_error(error, context, state) do
      # Record the event and notify the test process
      send(state.test_pid, {:handler_event, :error, {error, context}})

      # Different handling based on error type
      case error do
        :critical_error ->
          {:stop, :critical_error, state}

        :transient_error ->
          {:retry, 100, state}

        _ ->
          {:ok, state}
      end
    end

    @impl true
    def should_reconnect?(error, attempt, state) do
      # Record the event and notify the test process
      send(state.test_pid, {:handler_event, :should_reconnect, {error, attempt}})

      case error do
        :critical_error -> {false, nil}
        _ -> {attempt <= 3, 100 * attempt}
      end
    end

    @impl true
    def log_error(error_type, context, state) do
      # Record the event and notify the test process
      send(state.test_pid, {:handler_event, :log_error, {error_type, context}})
      :ok
    end
  end

  setup do
    # Setup initial connection state with test behavior handlers
    test_pid = self()

    {:ok, conn_handler_state} = TestConnectionHandler.init(test_pid: test_pid)

    message_handler_state = %{
      test_pid: test_pid,
      should_reply: false
    }

    error_handler_state = %{
      test_pid: test_pid
    }

    state =
      "example.com"
      |> ConnectionState.new(8080, %{})
      |> ConnectionState.update_status(:connecting)
      |> ConnectionState.update_handlers(%{
        connection_handler: TestConnectionHandler,
        connection_handler_state: conn_handler_state,
        message_handler: TestMessageHandler,
        message_handler_state: message_handler_state,
        error_handler: TestErrorHandler,
        error_handler_state: error_handler_state
      })

    %{
      state: state,
      test_pid: test_pid
    }
  end

  describe "gun_to_behavior routing" do
    test "routes connection events to the connection handler", %{state: state} do
      # Create a gun_up message and route it through the bridge
      protocol = :http
      result = BehaviorBridge.handle_gun_up("gun_pid", protocol, state)

      # Verify that the connection handler was called
      assert_receive {:handler_event, :connect, conn_info}
      assert conn_info.protocol == protocol

      # Verify the state was updated
      assert {:noreply, updated_state} = result
      assert updated_state.status == :connected
    end

    test "routes disconnection events to the connection handler", %{state: state} do
      # First transition to connected state
      protocol = :http
      {:noreply, connected_state} = BehaviorBridge.handle_gun_up("gun_pid", protocol, state)

      # Create a gun_down message and route it through the bridge
      reason = :normal
      result = BehaviorBridge.handle_gun_down("gun_pid", protocol, reason, connected_state, [], [])

      # Verify that the connection handler was called
      assert_receive {:handler_event, :disconnect, disconnect_reason}
      assert disconnect_reason == {:remote, 1000, "Connection closed normally"}

      # Verify the state was updated
      assert {:noreply, updated_state} = result
      assert updated_state.status == :disconnected
    end

    test "routes WebSocket frames to the connection handler", %{state: state} do
      # Create a websocket frame message and route it through the bridge
      frame_data = "Hello, world!"

      result =
        BehaviorBridge.handle_websocket_frame("gun_pid", "stream_ref", {:text, frame_data}, state)

      # Verify that the connection handler was called with the frame
      assert_receive {:handler_event, :frame, {:text, ^frame_data}}

      # Verify the state was maintained
      assert {:noreply, _updated_state} = result
    end

    test "processes text frame data through message handler", %{state: state} do
      # Create a JSON message and route it through the bridge
      json_data = Jason.encode!(%{"type" => "test", "data" => "value"})

      result =
        BehaviorBridge.handle_websocket_frame("gun_pid", "stream_ref", {:text, json_data}, state)

      # Verify the message handler was called with the decoded message
      assert_receive {:handler_event, :message, message}
      assert message["type"] == "test"
      assert message["data"] == "value"

      # Verify the state was maintained
      assert {:noreply, _updated_state} = result
    end

    test "sends a response when handlers return reply", %{state: state} do
      # Update state to make handlers reply
      conn_handler_state = Map.put(state.handlers.connection_handler_state, :should_reply, true)
      state = put_in(state.handlers.connection_handler_state, conn_handler_state)

      # Route a frame through the bridge
      result =
        BehaviorBridge.handle_websocket_frame("gun_pid", "stream_ref", {:text, "test"}, state)

      # Verify a reply was produced - note the 5-element tuple pattern
      assert {:reply, :text, "response", _updated_state, "stream_ref"} = result
    end

    test "handles errors through the error handler", %{state: state} do
      # Create an error situation
      error = :connection_error
      context = %{reason: :timeout}
      result = BehaviorBridge.handle_error(error, context, state)

      # Verify the error handler was called
      assert_receive {:handler_event, :error, {^error, ^context}}
      assert_receive {:handler_event, :log_error, {^error, ^context}}

      # Verify the state was maintained
      assert {:noreply, _updated_state} = result
    end

    test "stops the process when error handler returns stop", %{state: state} do
      # Create a critical error
      error = :critical_error
      context = %{reason: :authentication_failed}
      result = BehaviorBridge.handle_error(error, context, state)

      # Verify the error handler was called
      assert_receive {:handler_event, :error, {^error, ^context}}

      # Verify the process is stopped
      assert {:stop, :critical_error, _updated_state} = result
    end
  end
end
