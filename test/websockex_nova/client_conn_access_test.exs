defmodule WebsockexNova.ClientConnAccessTest do
  use ExUnit.Case, async: true
  
  alias WebsockexNova.ClientConn
  
  setup do
    # Create a basic ClientConn struct for testing
    client_conn = %ClientConn{
      transport: MockTransport,
      transport_pid: self(),
      stream_ref: make_ref(),
      adapter: MockAdapter,
      adapter_state: %{test_key: "test_value"},
      connection_info: %{host: "example.com", port: 443},
      extras: %{custom_data: "custom_value"}
    }
    
    %{conn: client_conn}
  end
  
  describe "Access behavior implementation" do
    test "supports access via bracket notation with atom keys", %{conn: conn} do
      # Test reading values with bracket syntax
      assert conn[:transport] == MockTransport
      assert conn[:adapter] == MockAdapter
      assert conn[:adapter_state] == %{test_key: "test_value"}
      assert conn[:connection_info] == %{host: "example.com", port: 443}
      assert conn[:extras] == %{custom_data: "custom_value"}
      
      # Test non-existent keys
      assert conn[:non_existent_key] == nil
    end
    
    test "supports access via bracket notation with string keys", %{conn: conn} do
      # Test reading values with bracket syntax using string keys
      assert conn["transport"] == MockTransport
      assert conn["adapter"] == MockAdapter
      assert conn["adapter_state"] == %{test_key: "test_value"}
      assert conn["connection_info"] == %{host: "example.com", port: 443}
      assert conn["extras"] == %{custom_data: "custom_value"}
      
      # Test non-existent keys
      assert conn["non_existent_key"] == nil
    end
    
    test "supports Access.get/3 with atom keys", %{conn: conn} do
      # Test with default value for existing keys
      assert Access.get(conn, :transport, :default) == MockTransport
      assert Access.get(conn, :adapter_state, :default) == %{test_key: "test_value"}
      
      # Test with default value for non-existing keys
      assert Access.get(conn, :non_existent, :default) == :default
    end
    
    test "supports Access.get/3 with string keys", %{conn: conn} do
      # Test with default value for existing keys
      assert Access.get(conn, "transport", :default) == MockTransport
      assert Access.get(conn, "adapter_state", :default) == %{test_key: "test_value"}
      
      # Test with default value for non-existing keys
      assert Access.get(conn, "non_existent", :default) == :default
    end
    
    test "supports Access.fetch/2 with atom keys", %{conn: conn} do
      # Test successful fetch
      assert Access.fetch(conn, :transport) == {:ok, MockTransport}
      assert Access.fetch(conn, :adapter_state) == {:ok, %{test_key: "test_value"}}
      
      # Test fetch for non-existing key
      assert Access.fetch(conn, :non_existent) == :error
    end
    
    test "supports Access.fetch/2 with string keys", %{conn: conn} do
      # Test successful fetch
      assert Access.fetch(conn, "transport") == {:ok, MockTransport}
      assert Access.fetch(conn, "adapter_state") == {:ok, %{test_key: "test_value"}}
      
      # Test fetch for non-existing key
      assert Access.fetch(conn, "non_existent") == :error
    end
    
    test "supports Access.get_and_update/3 with atom keys", %{conn: conn} do
      # Update adapter_state
      {old_value, updated_conn} = Access.get_and_update(conn, :adapter_state, fn current ->
        {current, Map.put(current, :new_key, "new_value")}
      end)
      
      # Check old value returned
      assert old_value == %{test_key: "test_value"}
      
      # Check updated value in struct
      assert updated_conn.adapter_state == %{test_key: "test_value", new_key: "new_value"}
      
      # Test with :pop
      {value, _updated} = Access.get_and_update(conn, :adapter_state, fn _ -> :pop end)
      assert value == %{test_key: "test_value"}
    end
    
    test "supports Access.get_and_update/3 with string keys", %{conn: conn} do
      # Update adapter_state
      {old_value, updated_conn} = Access.get_and_update(conn, "adapter_state", fn current ->
        {current, Map.put(current, :new_key, "new_value")}
      end)
      
      # Check old value returned
      assert old_value == %{test_key: "test_value"}
      
      # Check updated value in struct
      assert updated_conn.adapter_state == %{test_key: "test_value", new_key: "new_value"}
      
      # Test with :pop
      {value, _updated} = Access.get_and_update(conn, "adapter_state", fn _ -> :pop end)
      assert value == %{test_key: "test_value"}
    end
    
    test "supports Access.pop/2 with atom keys", %{conn: conn} do
      # Pop adapter_state
      {value, updated_conn} = Access.pop(conn, :adapter_state)
      
      # Check the returned value
      assert value == %{test_key: "test_value"}
      
      # Check the updated struct (adapter_state should be reset to empty map)
      assert updated_conn.adapter_state == %{}
      
      # Pop a non-map field
      {transport, updated_conn} = Access.pop(conn, :transport)
      assert transport == MockTransport
      assert updated_conn.transport == nil
    end
    
    test "supports Access.pop/2 with string keys", %{conn: conn} do
      # Pop adapter_state
      {value, updated_conn} = Access.pop(conn, "adapter_state")
      
      # Check the returned value
      assert value == %{test_key: "test_value"}
      
      # Check the updated struct (adapter_state should be reset to empty map)
      assert updated_conn.adapter_state == %{}
      
      # Pop a non-map field
      {transport, updated_conn} = Access.pop(conn, "transport")
      assert transport == MockTransport
      assert updated_conn.transport == nil
    end
    
    test "supports nested access with put_in/update_in", %{conn: conn} do
      # Update nested map value
      updated_conn = put_in(conn[:adapter_state][:new_nested_key], "nested_value")
      
      # Check the updated struct
      assert updated_conn.adapter_state.new_nested_key == "nested_value"
      assert updated_conn.adapter_state.test_key == "test_value"
      
      # Update existing nested value
      updated_conn = update_in(conn[:adapter_state][:test_key], &String.upcase/1)
      
      # Check the updated value
      assert updated_conn.adapter_state.test_key == "TEST_VALUE"
    end
    
    test "supports nested access with get_in using atom keys", %{conn: conn} do
      # Get nested value
      value = get_in(conn, [:adapter_state, :test_key])
      
      # Check the value
      assert value == "test_value"
      
      # Try non-existing path
      value = get_in(conn, [:adapter_state, :non_existent])
      assert value == nil
    end
    
    test "nested access with string keys converts first-level keys", %{conn: conn} do
      # Top-level string keys are converted to atoms
      adapter_state = conn["adapter_state"]
      
      # After that, regular map access rules apply (atom keys)
      assert adapter_state.test_key == "test_value"
      
      # String keys don't work within the nested map
      assert get_in(adapter_state, ["test_key"]) == nil
      
      # But atom keys work
      assert get_in(adapter_state, [:test_key]) == "test_value"
    end
    
    test "nested access when mixing top-level string keys", %{conn: conn} do
      # Access top-level with string key
      adapter_state = conn["adapter_state"]
      
      # Then access nested value with atom key
      assert adapter_state[:test_key] == "test_value"
      
      # Or direct property access
      assert adapter_state.test_key == "test_value"
    end
  end
  
  # Mock modules for testing
  defmodule MockTransport do
  end
  
  defmodule MockAdapter do
  end
end