defmodule WebsockexNova.Gun.Helpers.StateSyncHelpersTest do
  use ExUnit.Case, async: true

  alias WebsockexNova.ClientConn
  alias WebsockexNova.Defaults.DefaultAuthHandler
  alias WebsockexNova.Defaults.DefaultConnectionHandler
  alias WebsockexNova.Gun.ConnectionState
  alias WebsockexNova.Gun.ConnectionWrapper
  alias WebsockexNova.Gun.Helpers.StateSyncHelpers

  describe "extract_transport_state/1" do
    test "extracts only transport-related fields from ClientConn" do
      # Create a ClientConn with both transport and session state
      client_conn = %ClientConn{
        transport: ConnectionWrapper,
        transport_pid: self(),
        connection_info: %{
          host: "example.com",
          port: 443,
          path: "/ws",
          transport: :tls,
          ws_opts: %{compress: true},
          connection_handler: DefaultConnectionHandler,
          auth_handler: DefaultAuthHandler
        },
        # Session state that should not be copied
        auth_status: :authenticated,
        access_token: "secret-token",
        credentials: %{api_key: "key", secret: "secret"},
        subscriptions: %{"topic1" => %{id: "sub1"}}
      }

      # Extract transport state
      transport_state = StateSyncHelpers.extract_transport_state(client_conn)

      # Verify transport fields were extracted
      assert transport_state.host == "example.com"
      assert transport_state.port == 443
      assert transport_state.path == "/ws"
      assert transport_state.transport == :tls
      assert transport_state.ws_opts == %{compress: true}

      # Verify handler modules were extracted
      assert transport_state.handlers.connection_handler == DefaultConnectionHandler
      assert transport_state.handlers.auth_handler == DefaultAuthHandler

      # Verify session state was NOT extracted
      refute Map.has_key?(transport_state, :auth_status)
      refute Map.has_key?(transport_state, :access_token)
      refute Map.has_key?(transport_state, :credentials)
      refute Map.has_key?(transport_state, :subscriptions)
    end

    test "handles missing or nil fields gracefully" do
      # Create a minimal ClientConn
      client_conn = %ClientConn{
        transport_pid: self()
      }

      # Extract transport state
      transport_state = StateSyncHelpers.extract_transport_state(client_conn)

      # Verify it doesn't crash and returns defaults
      assert is_map(transport_state)
      assert is_map(transport_state.handlers)
      assert Map.has_key?(transport_state, :host)
      assert Map.has_key?(transport_state, :port)
    end
  end

  describe "update_client_conn_from_transport/2" do
    test "updates ClientConn with transport-level info from ConnectionState" do
      # Create test state
      client_conn = %ClientConn{
        transport: ConnectionWrapper,
        connection_info: %{},
        auth_status: :authenticated,
        access_token: "token"
      }

      conn_state = %ConnectionState{
        gun_pid: self(),
        status: :connected,
        last_error: {:error, :test},
        active_streams: %{make_ref() => %{status: :websocket}}
      }

      # Update client_conn from conn_state
      updated_client_conn = StateSyncHelpers.update_client_conn_from_transport(client_conn, conn_state)

      # Verify transport fields were updated
      assert updated_client_conn.transport_pid == self()
      assert updated_client_conn.last_error == {:error, :test}
      assert updated_client_conn.connection_info.status == :connected
      assert is_reference(updated_client_conn.stream_ref)

      # Verify session state was preserved
      assert updated_client_conn.auth_status == :authenticated
      assert updated_client_conn.access_token == "token"
    end
  end

  describe "sync_connection_state_from_client/2" do
    test "updates ConnectionState with config from ClientConn without copying session state" do
      # Create test state
      client_conn = %ClientConn{
        connection_info: %{
          host: "example.com",
          port: 443,
          path: "/ws",
          connection_handler: DefaultConnectionHandler
        },
        auth_status: :authenticated,
        access_token: "token"
      }

      conn_state = %ConnectionState{
        gun_pid: self(),
        host: "old-host.com",
        port: 80,
        status: :connected
      }

      # Sync conn_state from client_conn
      updated_conn_state = StateSyncHelpers.sync_connection_state_from_client(conn_state, client_conn)

      # Verify transport config was updated
      assert updated_conn_state.host == "example.com"
      assert updated_conn_state.port == 443
      assert updated_conn_state.path == "/ws"
      assert updated_conn_state.handlers.connection_handler == DefaultConnectionHandler

      # Verify Gun-specific state was preserved
      assert updated_conn_state.gun_pid == self()
      assert updated_conn_state.status == :connected

      # Verify session state was NOT copied
      refute Map.has_key?(updated_conn_state, :auth_status)
      refute Map.has_key?(updated_conn_state, :access_token)
    end
  end

  describe "sync_client_conn_from_connection/2" do
    test "updates ClientConn with latest transport state while preserving session state" do
      # Create test state
      client_conn = %ClientConn{
        connection_info: %{old_key: "value"},
        auth_status: :authenticated,
        access_token: "token"
      }

      conn_state = %ConnectionState{
        gun_pid: self(),
        host: "example.com",
        port: 443,
        path: "/ws",
        status: :websocket_connected,
        last_error: {:error, :test},
        active_streams: %{make_ref() => %{status: :websocket}}
      }

      # Sync client_conn from conn_state
      updated_client_conn = StateSyncHelpers.sync_client_conn_from_connection(client_conn, conn_state)

      # Verify transport state was updated
      assert updated_client_conn.transport_pid == self()
      assert updated_client_conn.last_error == {:error, :test}
      assert updated_client_conn.connection_info.host == "example.com"
      assert updated_client_conn.connection_info.port == 443
      assert updated_client_conn.connection_info.path == "/ws"
      assert updated_client_conn.connection_info.status == :websocket_connected
      assert is_reference(updated_client_conn.stream_ref)

      # Verify existing fields were preserved
      assert updated_client_conn.connection_info.old_key == "value"
      assert updated_client_conn.auth_status == :authenticated
      assert updated_client_conn.access_token == "token"
    end
  end

  describe "sync_handler_modules/2" do
    test "updates ClientConn connection_info with handler modules from ConnectionState" do
      # Create test state
      client_conn = %ClientConn{
        connection_info: %{
          existing_key: "value",
          connection_handler: nil
        }
      }

      conn_state = %ConnectionState{
        handlers: %{
          connection_handler: DefaultConnectionHandler,
          auth_handler: DefaultAuthHandler,
          message_handler: nil
        }
      }

      # Sync handler modules from conn_state to client_conn
      updated_client_conn = StateSyncHelpers.sync_handler_modules(client_conn, conn_state)

      # Verify handler modules were updated in connection_info
      assert updated_client_conn.connection_info.connection_handler == DefaultConnectionHandler
      assert updated_client_conn.connection_info.auth_handler == DefaultAuthHandler

      # Verify that nil modules are not copied over
      refute Map.has_key?(updated_client_conn.connection_info, :message_handler)

      # Verify existing fields were preserved
      assert updated_client_conn.connection_info.existing_key == "value"
    end

    test "handles nil handlers in ConnectionState gracefully" do
      # Create test state
      client_conn = %ClientConn{
        connection_info: %{existing_key: "value"}
      }

      conn_state = %ConnectionState{
        handlers: nil
      }

      # Sync handler modules with nil handlers
      updated_client_conn = StateSyncHelpers.sync_handler_modules(client_conn, conn_state)

      # Verify no changes were made
      assert updated_client_conn.connection_info.existing_key == "value"
      assert map_size(updated_client_conn.connection_info) == 1
    end

    test "handles nil connection_info in ClientConn gracefully" do
      # Create test state
      client_conn = %ClientConn{
        connection_info: nil
      }

      conn_state = %ConnectionState{
        handlers: %{
          connection_handler: DefaultConnectionHandler
        }
      }

      # Sync handler modules with nil connection_info
      updated_client_conn = StateSyncHelpers.sync_handler_modules(client_conn, conn_state)

      # Verify handler was added to new connection_info map
      assert updated_client_conn.connection_info.connection_handler == DefaultConnectionHandler
      assert map_size(updated_client_conn.connection_info) == 1
    end
  end

  describe "create_client_conn/2" do
    test "creates a new ClientConn from ConnectionState when client_conn is nil" do
      # Create test state
      conn_state = %ConnectionState{
        gun_pid: self(),
        host: "example.com",
        port: 443,
        path: "/ws",
        status: :connected,
        callback_pid: self(),
        handlers: %{
          connection_handler: DefaultConnectionHandler
        }
      }

      # Create new client_conn
      client_conn = StateSyncHelpers.create_client_conn(nil, conn_state)

      # Verify client_conn has correct structure
      assert %ClientConn{} = client_conn
      assert client_conn.transport_pid == self()
      assert client_conn.connection_info.host == "example.com"
      assert client_conn.connection_info.port == 443
      assert client_conn.connection_info.connection_handler == DefaultConnectionHandler
      assert MapSet.member?(client_conn.callback_pids, self())
    end

    test "updates existing ClientConn with ConnectionState when client_conn is provided" do
      # Create test state
      existing_conn = %ClientConn{
        auth_status: :authenticated,
        access_token: "token",
        connection_info: %{old_setting: true}
      }

      conn_state = %ConnectionState{
        gun_pid: self(),
        host: "example.com",
        port: 443,
        status: :connected
      }

      # Update existing client_conn
      updated_conn = StateSyncHelpers.create_client_conn(existing_conn, conn_state)

      # Verify transport state was updated
      assert updated_conn.transport_pid == self()
      assert updated_conn.connection_info.host == "example.com"
      assert updated_conn.connection_info.port == 443
      assert updated_conn.connection_info.status == :connected

      # Verify session state was preserved
      assert updated_conn.auth_status == :authenticated
      assert updated_conn.access_token == "token"
      assert updated_conn.connection_info.old_setting == true
    end
  end

  describe "register_callback/3 and unregister_callback/3" do
    test "registers and unregisters callbacks in both structures" do
      # Create test state
      client_conn = %ClientConn{
        callback_pids: MapSet.new()
      }

      conn_state = %ConnectionState{
        callback_pid: nil
      }

      # Register callback
      {updated_client, updated_state} = StateSyncHelpers.register_callback(client_conn, conn_state, self())

      # Verify callback was registered
      assert MapSet.member?(updated_client.callback_pids, self())
      assert updated_state.callback_pid == self()

      # Unregister callback
      {final_client, final_state} = StateSyncHelpers.unregister_callback(updated_client, updated_state, self())

      # Verify callback was unregistered
      refute MapSet.member?(final_client.callback_pids, self())
      assert final_state.callback_pid == nil
    end
  end
end
