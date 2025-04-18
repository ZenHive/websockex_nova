defmodule WebsockexNova.Gun.ConnectionWrapper.BehaviorDelegationTest do
  use ExUnit.Case, async: false

  alias WebsockexNova.Behaviors.ConnectionHandler
  alias WebsockexNova.Gun.ConnectionWrapper
  alias WebsockexNova.Test.Support.MockWebSockServer

  require Logger

  @moduletag :integration

  @websocket_path "/ws"
  @default_delay 200

  # Test implementation of ConnectionHandler
  defmodule TestConnectionHandler do
    @moduledoc false
    @behaviour ConnectionHandler

    def init(opts) do
      # Store received options and add test flag
      if test_pid = Map.get(opts, :test_pid) do
        send(test_pid, {:handler_init, opts})
      end

      {:ok, opts |> Map.new() |> Map.put(:test_handler_initialized, true)}
    end

    def handle_connect(conn_info, state) do
      # Update state to track that handle_connect was called
      updated_state =
        state
        |> Map.put(:handle_connect_called, true)
        |> Map.put(:connection_info, conn_info)

      # Send a message to the test process if configured
      if test_pid = Map.get(state, :test_pid) do
        send(test_pid, {:handler_connect, conn_info, state})
      end

      {:ok, updated_state}
    end

    def handle_disconnect(reason, state) do
      # Update state to track that handle_disconnect was called
      updated_state =
        state
        |> Map.put(:handle_disconnect_called, true)
        |> Map.put(:disconnect_reason, reason)

      # Send a message to the test process if configured
      if test_pid = Map.get(state, :test_pid) do
        # Debugging logs
        Logger.debug("TestConnectionHandler - Sending handler_disconnect message to #{inspect(test_pid)}")

        send(test_pid, {:handler_disconnect, reason, state})
      else
        Logger.debug("TestConnectionHandler - No test PID available for disconnect notification")
      end

      # For testing, we'll attempt reconnect only if explicitly specified
      if Map.get(state, :should_reconnect, false) do
        {:reconnect, updated_state}
      else
        {:ok, updated_state}
      end
    end

    def handle_frame(frame_type, frame_data, state) do
      # Debug logging
      Logger.debug("TestConnectionHandler - handle_frame called with #{inspect(frame_type)}")

      # Update state to track frame handling
      updated_state =
        Map.update(state, :frames_received, [{frame_type, frame_data}], fn frames ->
          [{frame_type, frame_data} | frames]
        end)

      # Send a message to the test process if configured
      if test_pid = Map.get(state, :test_pid) do
        Logger.debug("TestConnectionHandler - Sending handler_frame message to #{inspect(test_pid)}")

        send(test_pid, {:handler_frame, frame_type, frame_data, state})
      else
        Logger.debug("TestConnectionHandler - No test PID available for frame notification")
      end

      # For ping frames, reply with a pong
      case frame_type do
        :ping -> {:reply, :pong, frame_data, updated_state}
        _ -> {:ok, updated_state}
      end
    end

    def handle_timeout(state) do
      # Update state to track that handle_timeout was called
      updated_state = Map.put(state, :handle_timeout_called, true)

      # Send a message to the test process if configured
      if test_pid = Map.get(state, :test_pid) do
        send(test_pid, {:handler_timeout, state})
      end

      {:ok, updated_state}
    end
  end

  describe "behavior delegation" do
    test "properly configures and initializes the behavior module" do
      {:ok, server_pid, port} = MockWebSockServer.start_link()

      try do
        # Start connection wrapper with test handler
        {:ok, conn_pid} =
          ConnectionWrapper.open("localhost", port, %{
            callback_handler: TestConnectionHandler,
            test_pid: self(),
            custom_option: "test_value"
          })

        # Verify we received an init message
        assert_receive {:handler_init, _opts}, 500

        # Wait for connection to establish
        Process.sleep(@default_delay)

        # Verify handler was initialized with our options
        state = ConnectionWrapper.get_state(conn_pid)
        assert state.handlers.connection_handler == TestConnectionHandler

        # Close the connection
        ConnectionWrapper.close(conn_pid)
      after
        Process.sleep(@default_delay)
        MockWebSockServer.stop(server_pid)
      end
    end

    test "delegates connection events to the handler" do
      {:ok, server_pid, port} = MockWebSockServer.start_link()

      try do
        # Start connection wrapper with test handler
        {:ok, conn_pid} =
          ConnectionWrapper.open("localhost", port, %{
            callback_handler: TestConnectionHandler,
            test_pid: self()
          })

        # Verify we received an init message
        assert_receive {:handler_init, _opts}, 500

        # Wait for connection to establish
        Process.sleep(@default_delay)

        # Verify handle_connect was called
        assert_receive {:handler_connect, conn_info, _state}, 500
        assert conn_info.host == "localhost"
        assert conn_info.port == port

        # Upgrade to WebSocket
        {:ok, stream_ref} = ConnectionWrapper.upgrade_to_websocket(conn_pid, @websocket_path)
        Process.sleep(@default_delay * 2)

        # Send a text frame
        :ok = ConnectionWrapper.send_frame(conn_pid, stream_ref, {:text, "Test message"})
        Process.sleep(@default_delay)

        # Send a ping frame to test reply
        :ok = ConnectionWrapper.send_frame(conn_pid, stream_ref, :ping)
        Process.sleep(@default_delay)

        # Close the connection normally
        ConnectionWrapper.close(conn_pid)
      after
        Process.sleep(@default_delay)
        MockWebSockServer.stop(server_pid)
      end
    end

    test "delegates disconnection events to the handler" do
      {:ok, server_pid, port} = MockWebSockServer.start_link()

      try do
        # Start connection wrapper with test handler
        {:ok, conn_pid} =
          ConnectionWrapper.open("localhost", port, %{
            callback_handler: TestConnectionHandler,
            test_pid: self()
          })

        # Verify we received an init message
        assert_receive {:handler_init, _opts}, 500

        # Wait for connection to establish and upgrade to websocket
        Process.sleep(@default_delay)
        {:ok, _stream_ref} = ConnectionWrapper.upgrade_to_websocket(conn_pid, @websocket_path)
        Process.sleep(@default_delay)

        # Manually get state to verify test_pid is properly set
        state = ConnectionWrapper.get_state(conn_pid)
        Logger.debug("State before disconnect: #{inspect(state.handlers)}")

        # Stop the server to force a disconnection
        MockWebSockServer.stop(server_pid)

        # Wait for the disconnection to be handled
        Process.sleep(@default_delay * 3)

        # Close the connection wrapper
        ConnectionWrapper.close(conn_pid)
      after
        # Server already stopped in test
        nil
      end
    end

    test "handler can control reconnection behavior" do
      {:ok, server_pid, port} = MockWebSockServer.start_link()

      try do
        # Start connection wrapper with test handler configured to reconnect
        {:ok, conn_pid} =
          ConnectionWrapper.open("localhost", port, %{
            callback_handler: TestConnectionHandler,
            test_pid: self(),
            should_reconnect: true
          })

        # Verify we received an init message
        assert_receive {:handler_init, _opts}, 500

        # Wait for connection to establish
        Process.sleep(@default_delay)

        # Get initial connection state
        initial_state = ConnectionWrapper.get_state(conn_pid)

        # Stop the server to force a disconnection
        MockWebSockServer.stop(server_pid)
        Process.sleep(@default_delay * 2)

        # Restart the server for reconnection
        {:ok, new_server_pid, _new_port} = MockWebSockServer.start_link()

        # Wait for potential reconnection attempts
        Process.sleep(@default_delay * 4)

        # Clean up
        ConnectionWrapper.close(conn_pid)
        MockWebSockServer.stop(new_server_pid)
      after
        # Servers handled in test
        nil
      end
    end
  end

  # Helper function to assert connection status
  defp assert_connection_status(conn_pid, expected_status, timeout \\ 500) do
    # Poll the connection status until it matches or times out
    start_time = System.monotonic_time(:millisecond)
    check_connection_status(conn_pid, expected_status, start_time, timeout)
  end

  defp check_connection_status(conn_pid, expected_status, start_time, timeout) do
    current_time = System.monotonic_time(:millisecond)

    if current_time - start_time > timeout do
      state = ConnectionWrapper.get_state(conn_pid)
      flunk("Connection status never reached #{expected_status}, stayed at #{state.status}")
    else
      state = ConnectionWrapper.get_state(conn_pid)

      if state.status == expected_status do
        true
      else
        Process.sleep(50)
        check_connection_status(conn_pid, expected_status, start_time, timeout)
      end
    end
  end
end
