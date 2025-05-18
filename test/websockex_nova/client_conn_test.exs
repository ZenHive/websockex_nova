defmodule WebsockexNova.ClientConnTest do
  use ExUnit.Case
  
  alias WebsockexNova.ClientConn
  alias WebsockexNova.ConnectionRegistry

  setup do
    # Create test PIDs and connection IDs
    test_pid1 = spawn(fn -> receive do _ -> :ok end end)
    test_pid2 = spawn(fn -> receive do _ -> :ok end end)
    connection_id = make_ref()
    
    # Create a test ClientConn struct
    client_conn = %ClientConn{
      transport: MockTransport,
      transport_pid: test_pid1,
      stream_ref: make_ref(),
      connection_id: connection_id,
      adapter: MockAdapter
    }
    
    # Return test data
    %{
      pid1: test_pid1,
      pid2: test_pid2,
      connection_id: connection_id,
      client_conn: client_conn
    }
  end
  
  describe "get_current_transport_pid/1" do
    test "returns transport_pid from struct when connection_id is not registered", %{client_conn: conn, pid1: pid1} do
      # Ensure no registration exists
      ConnectionRegistry.unregister(conn.connection_id)
      
      # Should return the PID stored in the struct
      assert ClientConn.get_current_transport_pid(conn) == pid1
    end
    
    test "returns pid from registry when connection_id is registered", %{client_conn: conn, pid1: pid1, pid2: pid2} do
      # Register a different PID with the connection_id
      :ok = ConnectionRegistry.register(conn.connection_id, pid2)
      
      # Should return the PID from registry, not the one in the struct
      assert ClientConn.get_current_transport_pid(conn) == pid2
      assert ClientConn.get_current_transport_pid(conn) != pid1
    end
    
    test "falls back to struct's transport_pid when registry PID is not alive", %{client_conn: conn, pid1: pid1} do
      # Create a PID that's definitely not alive
      dead_pid = spawn(fn -> :ok end)
      Process.sleep(10) # Ensure the process terminates
      
      # Register the dead PID
      :ok = ConnectionRegistry.register(conn.connection_id, dead_pid)
      
      # Should fall back to the struct's PID
      assert ClientConn.get_current_transport_pid(conn) == pid1
    end
    
    test "handles nil connection_id gracefully", %{pid1: pid1} do
      # Create a conn with nil connection_id
      conn = %ClientConn{transport_pid: pid1, connection_id: nil}
      
      # Should return the struct's PID
      assert ClientConn.get_current_transport_pid(conn) == pid1
    end
  end
  
  # Mock modules for testing
  defmodule MockTransport do
    def get_state(_), do: %{}
  end
  
  defmodule MockAdapter do
  end
end