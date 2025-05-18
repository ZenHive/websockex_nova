defmodule WebsockexNova.ClientConnTest do
  use ExUnit.Case

  alias WebsockexNova.ClientConn
  alias WebsockexNova.ConnectionRegistry

  setup do
    # Create test PIDs and connection IDs
    test_pid1 =
      spawn(fn ->
        receive do
          _ -> :ok
        end
      end)

    test_pid2 =
      spawn(fn ->
        receive do
          _ -> :ok
        end
      end)

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
      # Ensure the process terminates
      Process.sleep(10)

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

  describe "Access behavior" do
    test "fetch/2 returns {:ok, value} for valid keys", %{client_conn: conn} do
      assert Access.fetch(conn, :transport) == {:ok, MockTransport}
      assert Access.fetch(conn, :adapter) == {:ok, MockAdapter}
      assert conn[:transport] == MockTransport
      assert conn[:adapter] == MockAdapter
    end

    test "fetch/2 returns :error for invalid keys", %{client_conn: conn} do
      assert Access.fetch(conn, :invalid_key) == :error
      assert conn[:invalid_key] == nil
    end

    test "get_and_update/3 updates values", %{client_conn: conn} do
      # Update adapter_state
      {old_value, updated_conn} =
        Access.get_and_update(conn, :adapter_state, fn current ->
          {current, Map.put(current, :test_key, "test_value")}
        end)

      assert old_value == %{}
      assert updated_conn.adapter_state == %{test_key: "test_value"}

      # Update extras
      {old_value, updated_conn} =
        Access.get_and_update(updated_conn, :extras, fn current ->
          {current, Map.put(current, :extra_key, "extra_value")}
        end)

      assert old_value == %{}
      assert updated_conn.extras == %{extra_key: "extra_value"}
    end

    test "get_and_update/3 with :pop returns current value", %{client_conn: conn} do
      # Add a value to extras first
      conn = %{conn | extras: %{test: "value"}}

      # Use :pop
      {popped, _updated_conn} = Access.get_and_update(conn, :extras, fn _ -> :pop end)

      assert popped == %{test: "value"}
    end

    test "pop/3 returns value and resets to default", %{client_conn: conn} do
      # Add values to test popping
      conn = %{conn | extras: %{test: "value"}, adapter_state: %{adapter: "state"}}

      # Pop extras
      {extras, conn_without_extras} = Access.pop(conn, :extras)
      assert extras == %{test: "value"}
      assert conn_without_extras.extras == %{}

      # Pop adapter_state
      {adapter_state, conn_without_adapter_state} = Access.pop(conn, :adapter_state)
      assert adapter_state == %{adapter: "state"}
      assert conn_without_adapter_state.adapter_state == %{}

      # Pop non-map field
      {transport, conn_without_transport} = Access.pop(conn, :transport)
      assert transport == MockTransport
      assert conn_without_transport.transport == nil
    end
  end

  # Mock modules for testing
  defmodule MockTransport do
    @moduledoc false
    def get_state(_), do: %{}
  end

  defmodule MockAdapter do
    @moduledoc false
  end
end
