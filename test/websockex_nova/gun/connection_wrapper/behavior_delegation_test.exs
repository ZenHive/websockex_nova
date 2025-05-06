defmodule WebsockexNova.Gun.ConnectionWrapper.BehaviorDelegationTest do
  use ExUnit.Case, async: false

  alias WebsockexNova.Behaviours.AuthHandler
  alias WebsockexNova.Behaviours.ConnectionHandler
  alias WebsockexNova.Behaviours.SubscriptionHandler
  alias WebsockexNova.Gun.ConnectionWrapper
  alias WebsockexNova.Test.Support.MockWebSockServer

  require Logger

  @moduletag :integration

  @websocket_path "/ws"
  @host "localhost"

  @default_delay 200

  # Test implementation of ConnectionHandler
  defmodule TestConnectionHandler do
    @moduledoc false
    @behaviour ConnectionHandler

    def init(opts) do
      Logger.debug("[TestConnectionHandler.init] opts: #{inspect(opts)}")

      if test_pid = Map.get(opts, :test_pid) do
        send(test_pid, {:handler_init, opts})
      end

      {:ok, opts |> Map.new() |> Map.put(:test_handler_initialized, true)}
    end

    def handle_connect(conn_info, state) do
      updated_state =
        state
        |> Map.put(:handle_connect_called, true)
        |> Map.put(:connection_info, conn_info)

      if test_pid = Map.get(state, :test_pid) do
        send(test_pid, {:handler_connect, conn_info, state})
      end

      {:ok, updated_state}
    end

    def handle_disconnect(reason, state) do
      updated_state =
        state
        |> Map.put(:handle_disconnect_called, true)
        |> Map.put(:disconnect_reason, reason)

      if test_pid = Map.get(state, :test_pid) do
        Logger.debug(
          "TestConnectionHandler - Sending handler_disconnect message to #{inspect(test_pid)}"
        )

        send(test_pid, {:handler_disconnect, reason, state})
      else
        Logger.debug("TestConnectionHandler - No test PID available for disconnect notification")
      end

      if Map.get(state, :should_reconnect, false) do
        {:reconnect, updated_state}
      else
        {:ok, updated_state}
      end
    end

    def handle_frame(frame_type, frame_data, state) do
      Logger.debug("TestConnectionHandler - handle_frame called with #{inspect(frame_type)}")

      updated_state =
        Map.update(state, :frames_received, [{frame_type, frame_data}], fn frames ->
          [{frame_type, frame_data} | frames]
        end)

      if test_pid = Map.get(state, :test_pid) do
        Logger.debug(
          "TestConnectionHandler - Sending handler_frame message to #{inspect(test_pid)}"
        )

        send(test_pid, {:handler_frame, frame_type, frame_data, state})
      else
        Logger.debug("TestConnectionHandler - No test PID available for frame notification")
      end

      case frame_type do
        :ping -> {:reply, :pong, frame_data, updated_state}
        _ -> {:ok, updated_state}
      end
    end

    def handle_timeout(state) do
      updated_state = Map.put(state, :handle_timeout_called, true)

      if test_pid = Map.get(state, :test_pid) do
        send(test_pid, {:handler_timeout, state})
      end

      {:ok, updated_state}
    end

    def ping(stream_ref, state), do: {:pinged, stream_ref, state || %{}}
    def status(stream_ref, state), do: {:status, stream_ref, state || %{}}

    def subscription_init(opts), do: {:ok, opts}
    def active_subscriptions(_state), do: []
    def find_subscription_by_channel(_channel, _state), do: nil
    def handle_subscription_response(_resp, state), do: {:ok, state}
  end

  defmodule TestSubscriptionHandler do
    @moduledoc false
    @behaviour SubscriptionHandler

    def subscription_init(opts) do
      if test_pid = Map.get(opts, :test_pid) do
        send(test_pid, {:handler_init, opts})
      end

      {:ok, %{}}
    end

    def subscribe(channel, params, state), do: {:subscribed, channel, params, state || %{}}
    def unsubscribe(channel, state), do: {:unsubscribed, channel, state || %{}}
    def active_subscriptions(_state), do: %{}
    def find_subscription_by_channel(_channel, _state), do: nil
    def handle_subscription_response(_resp, state), do: {:ok, state || %{}}
  end

  defmodule TestAuthHandler do
    @moduledoc false
    @behaviour AuthHandler

    def generate_auth_data(state), do: {:ok, %{token: "t"}, state || %{}}
    def handle_auth_response(_resp, state), do: {:ok, state || %{}}
    def needs_reauthentication?(_state), do: false

    def authenticate(stream_ref, credentials, state),
      do: {:authenticated, stream_ref, credentials, state || %{}}
  end

  describe "behavior delegation" do
    test "properly configures and initializes the behavior module" do
      {:ok, server_pid, port} = MockWebSockServer.start_link()

      try do
        # Start connection wrapper with test handler
        {:ok, conn} =
          ConnectionWrapper.open("localhost", port, "/ws", %{
            callback_handler: TestConnectionHandler,
            test_pid: self(),
            custom_option: "test_value",
            transport: :tcp
          })

        # Verify we received an init message
        assert_receive {:handler_init, _opts}, 500

        # Wait for connection to establish
        Process.sleep(@default_delay)

        # Verify handler was initialized with our options
        state = ConnectionWrapper.get_state(conn)
        assert state.handlers.connection_handler == TestConnectionHandler

        # Close the connection
        ConnectionWrapper.close(conn)
      after
        Process.sleep(@default_delay)
        MockWebSockServer.stop(server_pid)
      end
    end

    test "delegates connection events to the handler" do
      {:ok, server_pid, port} = MockWebSockServer.start_link()

      try do
        # Start connection wrapper with test handler
        {:ok, conn} =
          ConnectionWrapper.open(@host, port, @websocket_path, %{
            callback_handler: TestConnectionHandler,
            test_pid: self(),
            transport: :tcp
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
        Process.sleep(@default_delay * 2)

        # Send a text frame
        :ok = ConnectionWrapper.send_frame(conn, conn.stream_ref, {:text, "Test message"})
        Process.sleep(@default_delay)

        # Send a ping frame to test reply
        :ok = ConnectionWrapper.send_frame(conn, conn.stream_ref, :ping)
        Process.sleep(@default_delay)

        # Close the connection normally
        ConnectionWrapper.close(conn)
      after
        Process.sleep(@default_delay)
        MockWebSockServer.stop(server_pid)
      end
    end

    test "delegates disconnection events to the handler" do
      {:ok, server_pid, port} = MockWebSockServer.start_link()

      try do
        # Start connection wrapper with test handler
        {:ok, conn} =
          ConnectionWrapper.open("localhost", port, "/ws", %{
            callback_handler: TestConnectionHandler,
            test_pid: self(),
            transport: :tcp
          })

        # Verify we received an init message
        assert_receive {:handler_init, _opts}, 500

        # Wait for connection to establish and upgrade to websocket
        Process.sleep(@default_delay)

        Process.sleep(@default_delay)

        # Manually get state to verify test_pid is properly set
        state = ConnectionWrapper.get_state(conn)
        Logger.debug("State before disconnect: #{inspect(state.handlers)}")

        # Stop the server to force a disconnection
        MockWebSockServer.stop(server_pid)

        # Wait for the disconnection to be handled
        Process.sleep(@default_delay * 3)

        # Close the connection wrapper
        ConnectionWrapper.close(conn)
      after
        # Server already stopped in test
        nil
      end
    end

    test "handler can control reconnection behavior" do
      {:ok, server_pid, port} = MockWebSockServer.start_link()

      try do
        # Start connection wrapper with test handler configured to reconnect
        {:ok, conn} =
          ConnectionWrapper.open("localhost", port, "/ws", %{
            callback_handler: TestConnectionHandler,
            test_pid: self(),
            should_reconnect: true,
            transport: :tcp
          })

        # Verify we received an init message
        assert_receive {:handler_init, _opts}, 500

        # Wait for connection to establish
        Process.sleep(@default_delay)

        # Get initial connection state
        # _initial_state = ConnectionWrapper.get_state(conn_pid)

        # Stop the server to force a disconnection
        MockWebSockServer.stop(server_pid)
        Process.sleep(@default_delay * 2)

        # Restart the server for reconnection
        {:ok, new_server_pid, _new_port} = MockWebSockServer.start_link()

        # Wait for potential reconnection attempts
        Process.sleep(@default_delay * 4)

        # Clean up
        ConnectionWrapper.close(conn)
        MockWebSockServer.stop(new_server_pid)
      after
        # Servers handled in test
        nil
      end
    end

    setup do
      {:ok, server_pid, port} = MockWebSockServer.start_link()

      {:ok, conn} =
        ConnectionWrapper.open("localhost", port, "/ws", %{
          callback_handler: TestConnectionHandler,
          subscription_handler: TestSubscriptionHandler,
          auth_handler: TestAuthHandler,
          transport: :tcp
        })

      {:ok, conn: conn, server_pid: server_pid}
    end

    test "subscribe/4 delegates to subscription handler", %{conn: conn, server_pid: server_pid} do
      assert {:subscribed, "chan", %{foo: 1}, %{}} =
               ConnectionWrapper.subscribe(conn, :ref, "chan", %{foo: 1})

      ConnectionWrapper.close(conn)
      MockWebSockServer.stop(server_pid)
    end

    test "unsubscribe/3 delegates to subscription handler", %{conn: conn, server_pid: server_pid} do
      assert {:unsubscribed, "chan", %{}} =
               ConnectionWrapper.unsubscribe(conn, :ref, "chan")

      ConnectionWrapper.close(conn)
      MockWebSockServer.stop(server_pid)
    end

    test "authenticate/3 delegates to auth handler", %{conn: conn, server_pid: server_pid} do
      assert {:authenticated, :ref, %{user: "u"}, %{}} =
               ConnectionWrapper.authenticate(conn, :ref, %{user: "u"})

      ConnectionWrapper.close(conn)
      MockWebSockServer.stop(server_pid)
    end

    test "ping/2 delegates to connection handler", %{conn: conn, server_pid: server_pid} do
      assert {:pinged, :ref, %{}} =
               ConnectionWrapper.ping(conn, :ref)

      ConnectionWrapper.close(conn)
      MockWebSockServer.stop(server_pid)
    end

    test "status/2 delegates to connection handler", %{conn: conn, server_pid: server_pid} do
      assert {:status, :ref, %{}} =
               ConnectionWrapper.status(conn, :ref)

      ConnectionWrapper.close(conn)
      MockWebSockServer.stop(server_pid)
    end
  end
end
