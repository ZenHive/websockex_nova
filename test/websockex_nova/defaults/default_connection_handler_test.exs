defmodule WebsockexNova.Defaults.DefaultConnectionHandlerTest do
  use ExUnit.Case, async: true

  alias WebsockexNova.ClientConn
  alias WebsockexNova.Defaults.DefaultConnectionHandler

  describe "DefaultConnectionHandler.init/1" do
    test "initializes with empty options" do
      assert {:ok, conn} = DefaultConnectionHandler.init([])
      assert %ClientConn{} = conn
    end

    test "keeps provided state intact" do
      initial_state = %{user_data: "test", custom_field: 123}
      assert {:ok, conn} = DefaultConnectionHandler.init(initial_state)
      assert %ClientConn{} = conn
      assert conn.connection_handler_settings[:user_data] == "test"
      assert conn.connection_handler_settings[:custom_field] == 123
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

      conn = %ClientConn{}
      assert {:ok, updated_conn} = DefaultConnectionHandler.handle_connect(conn_info, conn)
      assert updated_conn.connection_info == conn_info
      assert updated_conn.reconnect_attempts == 0
      assert Map.has_key?(updated_conn.extras, :connected_at)
    end

    test "preserves existing state fields" do
      conn_info = %{host: "example.com", port: 443}
      conn = %ClientConn{connection_handler_settings: %{user_data: "important", settings: %{timeout: 5000}}}
      assert {:ok, updated_conn} = DefaultConnectionHandler.handle_connect(conn_info, conn)
      assert updated_conn.connection_info == conn_info
      assert updated_conn.connection_handler_settings[:user_data] == "important"
      assert updated_conn.connection_handler_settings[:settings][:timeout] == 5000
    end
  end

  describe "DefaultConnectionHandler.handle_disconnect/2" do
    test "handles remote disconnection with reconnect" do
      disconnect_reason = {:remote, 1000, "Normal closure"}
      conn = %ClientConn{reconnect_attempts: 0, extras: %{max_reconnect_attempts: 3}}

      assert {:reconnect, new_conn} =
               DefaultConnectionHandler.handle_disconnect(disconnect_reason, conn)

      assert new_conn.reconnect_attempts == 1
      assert new_conn.extras[:last_disconnect_reason] == disconnect_reason
    end

    test "handles local disconnection without reconnect" do
      disconnect_reason = {:local, 1000, "Closed by client"}
      conn = %ClientConn{reconnect_attempts: 0}

      assert {:ok, new_conn} =
               DefaultConnectionHandler.handle_disconnect(disconnect_reason, conn)

      assert new_conn.extras[:last_disconnect_reason] == disconnect_reason
    end

    test "respects max reconnection attempts" do
      disconnect_reason = {:remote, 1000, "Normal closure"}
      conn = %ClientConn{reconnect_attempts: 3, extras: %{max_reconnect_attempts: 3}}

      assert {:ok, new_conn} =
               DefaultConnectionHandler.handle_disconnect(disconnect_reason, conn)

      assert new_conn.reconnect_attempts == 3
      assert new_conn.extras[:last_disconnect_reason] == disconnect_reason
    end

    test "handles error disconnection with reconnect" do
      disconnect_reason = {:error, :timeout}
      conn = %ClientConn{reconnect_attempts: 0, extras: %{max_reconnect_attempts: 3}}

      assert {:reconnect, new_conn} =
               DefaultConnectionHandler.handle_disconnect(disconnect_reason, conn)

      assert new_conn.reconnect_attempts == 1
      assert new_conn.extras[:last_disconnect_reason] == disconnect_reason
    end
  end

  describe "DefaultConnectionHandler.handle_frame/3" do
    test "handles text frames" do
      frame_type = :text
      frame_data = ~s({"type": "message", "content": "hello"})
      conn = %ClientConn{}

      assert {:ok, ^conn} =
               DefaultConnectionHandler.handle_frame(frame_type, frame_data, conn)
    end

    test "handles binary frames" do
      frame_type = :binary
      frame_data = <<1, 2, 3, 4>>
      conn = %ClientConn{}

      assert {:ok, ^conn} =
               DefaultConnectionHandler.handle_frame(frame_type, frame_data, conn)
    end

    test "automatically responds to ping with pong" do
      frame_type = :ping
      frame_data = "ping payload"
      conn = %ClientConn{}

      assert {:reply, :pong, "ping payload", ^conn} =
               DefaultConnectionHandler.handle_frame(frame_type, frame_data, conn)
    end

    test "handles pong frames" do
      frame_type = :pong
      frame_data = "pong payload"
      conn = %ClientConn{extras: %{last_ping_sent: System.monotonic_time(:millisecond)}}

      assert {:ok, new_conn} =
               DefaultConnectionHandler.handle_frame(frame_type, frame_data, conn)

      assert new_conn.extras[:last_pong_received]
      refute Map.has_key?(new_conn.extras, :last_ping_sent)
    end

    test "handles close frames" do
      frame_type = :close
      frame_data = <<3, 232, "Closed">>
      conn = %ClientConn{}

      assert {:ok, ^conn} =
               DefaultConnectionHandler.handle_frame(frame_type, frame_data, conn)
    end
  end

  describe "DefaultConnectionHandler.handle_timeout/1" do
    test "attempts reconnection on timeout" do
      conn = %ClientConn{reconnect_attempts: 0, extras: %{max_reconnect_attempts: 3}}
      assert {:reconnect, new_conn} = DefaultConnectionHandler.handle_timeout(conn)
      assert new_conn.reconnect_attempts == 1
    end

    test "respects max reconnection attempts on timeout" do
      conn = %ClientConn{reconnect_attempts: 3, extras: %{max_reconnect_attempts: 3}}

      assert {:stop, :max_reconnect_attempts_reached, new_conn} =
               DefaultConnectionHandler.handle_timeout(conn)

      assert new_conn.reconnect_attempts == 3
    end
  end
end
