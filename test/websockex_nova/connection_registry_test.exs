defmodule WebsockexNova.ConnectionRegistryTest do
  use ExUnit.Case

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

    connection_id1 = make_ref()
    connection_id2 = make_ref()

    # Return test data
    %{
      pid1: test_pid1,
      pid2: test_pid2,
      connection_id1: connection_id1,
      connection_id2: connection_id2
    }
  end

  describe "connection registry" do
    test "registers a connection ID with a transport PID", %{pid1: pid, connection_id1: connection_id} do
      assert :ok = ConnectionRegistry.register(connection_id, pid)
      assert {:ok, ^pid} = ConnectionRegistry.get_transport_pid(connection_id)
    end

    test "updates transport PID for an existing connection ID", %{pid1: pid1, pid2: pid2, connection_id1: connection_id} do
      # Register initial PID
      :ok = ConnectionRegistry.register(connection_id, pid1)
      assert {:ok, ^pid1} = ConnectionRegistry.get_transport_pid(connection_id)

      # Update with new PID
      :ok = ConnectionRegistry.register(connection_id, pid2)
      assert {:ok, ^pid2} = ConnectionRegistry.get_transport_pid(connection_id)
    end

    test "returns error for non-existent connection ID", %{connection_id1: connection_id} do
      assert {:error, :not_found} = ConnectionRegistry.get_transport_pid(connection_id)
    end

    test "unregisters a connection ID", %{pid1: pid, connection_id1: connection_id} do
      # Register
      :ok = ConnectionRegistry.register(connection_id, pid)
      assert {:ok, ^pid} = ConnectionRegistry.get_transport_pid(connection_id)

      # Unregister
      :ok = ConnectionRegistry.unregister(connection_id)
      assert {:error, :not_found} = ConnectionRegistry.get_transport_pid(connection_id)
    end

    test "updates transport PID via update_transport_pid", %{pid1: pid1, pid2: pid2, connection_id1: connection_id} do
      # Register initial PID
      :ok = ConnectionRegistry.register(connection_id, pid1)

      # Update with new PID
      assert :ok = ConnectionRegistry.update_transport_pid(connection_id, pid2)
      assert {:ok, ^pid2} = ConnectionRegistry.get_transport_pid(connection_id)
    end

    test "update_transport_pid returns error for non-existent connection ID", %{pid1: pid, connection_id1: connection_id} do
      assert {:error, :not_found} = ConnectionRegistry.update_transport_pid(connection_id, pid)
    end

    test "registers multiple connection IDs", %{pid1: pid1, pid2: pid2, connection_id1: id1, connection_id2: id2} do
      :ok = ConnectionRegistry.register(id1, pid1)
      :ok = ConnectionRegistry.register(id2, pid2)

      assert {:ok, ^pid1} = ConnectionRegistry.get_transport_pid(id1)
      assert {:ok, ^pid2} = ConnectionRegistry.get_transport_pid(id2)
    end
  end
end
