defmodule WebsockexNova.Defaults.DefaultConnectionHandlerTest do
  use ExUnit.Case, async: true

  alias WebsockexNova.Defaults.DefaultConnectionHandler

  describe "DefaultConnectionHandler.connection_init/1" do
    test "initializes with empty options" do
      assert {:ok, state} = DefaultConnectionHandler.connection_init([])
      assert is_map(state)
      assert map_size(state) == 0
    end

    test "keeps provided state intact" do
      initial_state = %{user_data: "test", custom_field: 123}
      assert {:ok, ^initial_state} = DefaultConnectionHandler.connection_init(initial_state)
    end
  end

  describe "DefaultConnectionHandler.handle_connect/2" do
    test "stores connection info in the state" do
      conn_info = %{
        host: "example.com",
        port: 443,
        path: "/ws",
        protocol: "echo",
        transport: :tls
      }

      assert {:ok, state} = DefaultConnectionHandler.handle_connect(conn_info, %{})
      assert state.connection == conn_info
    end

    test "preserves existing state fields" do
      conn_info = %{host: "example.com", port: 443}
      existing_state = %{user_data: "important", settings: %{timeout: 5000}}

      assert {:ok, state} = DefaultConnectionHandler.handle_connect(conn_info, existing_state)
      assert state.connection == conn_info
      assert state.user_data == "important"
      assert state.settings.timeout == 5000
    end
  end

  describe "DefaultConnectionHandler.handle_disconnect/2" do
    test "handles remote disconnection with reconnect" do
      disconnect_reason = {:remote, 1000, "Normal closure"}
      state = %{reconnect_attempts: 0, max_reconnect_attempts: 3}

      assert {:reconnect, new_state} =
               DefaultConnectionHandler.handle_disconnect(disconnect_reason, state)

      assert new_state.reconnect_attempts == 1
      assert new_state.last_disconnect_reason == disconnect_reason
    end

    test "handles local disconnection without reconnect" do
      disconnect_reason = {:local, 1000, "Closed by client"}
      state = %{reconnect_attempts: 0}

      assert {:ok, new_state} =
               DefaultConnectionHandler.handle_disconnect(disconnect_reason, state)

      assert new_state.last_disconnect_reason == disconnect_reason
    end

    test "respects max reconnection attempts" do
      disconnect_reason = {:remote, 1000, "Normal closure"}
      state = %{reconnect_attempts: 3, max_reconnect_attempts: 3}

      assert {:ok, new_state} =
               DefaultConnectionHandler.handle_disconnect(disconnect_reason, state)

      assert new_state.reconnect_attempts == 3
      assert new_state.last_disconnect_reason == disconnect_reason
    end

    test "handles error disconnection with reconnect" do
      disconnect_reason = {:error, :timeout}
      state = %{reconnect_attempts: 0, max_reconnect_attempts: 3}

      assert {:reconnect, new_state} =
               DefaultConnectionHandler.handle_disconnect(disconnect_reason, state)

      assert new_state.reconnect_attempts == 1
      assert new_state.last_disconnect_reason == disconnect_reason
    end
  end

  describe "DefaultConnectionHandler.handle_frame/3" do
    test "handles text frames" do
      frame_type = :text
      frame_data = ~s({"type": "message", "content": "hello"})
      state = %{}

      assert {:ok, ^state} =
               DefaultConnectionHandler.handle_frame(frame_type, frame_data, state)
    end

    test "handles binary frames" do
      frame_type = :binary
      frame_data = <<1, 2, 3, 4>>
      state = %{}

      assert {:ok, ^state} =
               DefaultConnectionHandler.handle_frame(frame_type, frame_data, state)
    end

    test "automatically responds to ping with pong" do
      frame_type = :ping
      frame_data = "ping payload"
      state = %{}

      assert {:reply, :pong, "ping payload", ^state} =
               DefaultConnectionHandler.handle_frame(frame_type, frame_data, state)
    end

    test "handles pong frames" do
      frame_type = :pong
      frame_data = "pong payload"
      state = %{last_ping_sent: System.monotonic_time(:millisecond)}

      assert {:ok, new_state} =
               DefaultConnectionHandler.handle_frame(frame_type, frame_data, state)

      assert new_state.last_pong_received
      assert not Map.has_key?(new_state, :last_ping_sent)
    end

    test "handles close frames" do
      frame_type = :close
      frame_data = <<3, 232, "Closed">>
      state = %{}

      assert {:ok, ^state} =
               DefaultConnectionHandler.handle_frame(frame_type, frame_data, state)
    end
  end

  describe "DefaultConnectionHandler.handle_timeout/1" do
    test "attempts reconnection on timeout" do
      state = %{reconnect_attempts: 0, max_reconnect_attempts: 3}

      assert {:reconnect, new_state} = DefaultConnectionHandler.handle_timeout(state)
      assert new_state.reconnect_attempts == 1
    end

    test "respects max reconnection attempts on timeout" do
      state = %{reconnect_attempts: 3, max_reconnect_attempts: 3}

      assert {:stop, :max_reconnect_attempts_reached, new_state} =
               DefaultConnectionHandler.handle_timeout(state)

      assert new_state.reconnect_attempts == 3
    end
  end
end
