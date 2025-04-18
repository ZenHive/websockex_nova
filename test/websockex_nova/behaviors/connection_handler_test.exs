defmodule WebsockexNova.Behaviors.ConnectionHandlerTest do
  use ExUnit.Case, async: true

  # Define a mock module that implements the ConnectionHandler behavior
  defmodule MockConnectionHandler do
    @moduledoc false
    @behaviour WebsockexNova.Behaviors.ConnectionHandler

    def init(opts) do
      {:ok, opts}
    end

    def handle_connect(conn_info, state) do
      send(self(), {:connect, conn_info})
      {:ok, state}
    end

    def handle_disconnect(reason, state) do
      send(self(), {:disconnect, reason})
      {:reconnect, state}
    end

    def handle_frame(frame_type, frame_data, state) do
      send(self(), {:frame, frame_type, frame_data})
      {:ok, state}
    end
  end

  describe "ConnectionHandler behavior" do
    test "init/1 should initialize state" do
      initial_state = %{test: "value"}
      assert {:ok, ^initial_state} = MockConnectionHandler.init(initial_state)
    end

    test "handle_connect/2 should process connection info" do
      conn_info = %{host: "example.com", port: 443}
      assert {:ok, :test_state} = MockConnectionHandler.handle_connect(conn_info, :test_state)
      assert_received {:connect, ^conn_info}
    end

    test "handle_disconnect/2 should process disconnection" do
      reason = {:remote, 1000, "Normal closure"}

      assert {:reconnect, :test_state} =
               MockConnectionHandler.handle_disconnect(reason, :test_state)

      assert_received {:disconnect, ^reason}
    end

    test "handle_frame/3 should process WebSocket frames" do
      frame_type = :text
      frame_data = ~s({"type": "message"})

      assert {:ok, :test_state} =
               MockConnectionHandler.handle_frame(frame_type, frame_data, :test_state)

      assert_received {:frame, ^frame_type, ^frame_data}
    end
  end
end
