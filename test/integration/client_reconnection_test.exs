defmodule WebsockexNova.Integration.ClientReconnectionTest do
  @moduledoc """
  Integration tests for client reconnection functionality.
  
  These tests verify that:
  1. When a connection is lost, the client automatically reconnects
  2. The original client connection object is updated with new transport info
  3. Client operations can continue using the original connection object
  4. State (subscriptions, etc.) is preserved after reconnection
  """
  use ExUnit.Case, async: false

  alias WebsockexNova.Client
  # We need this alias for typespecs
  alias WebsockexNova.ClientConn
  alias WebsockexNova.Test.Support.MockWebSockServer
  alias WebsockexNova.Test.Support.TestAdapter

  @websocket_path "/ws"
  @default_delay 100
  @reconnect_timeout 5000

  setup do
    {:ok, server_pid} = MockWebSockServer.start_link()
    port = MockWebSockServer.get_port(server_pid)
    
    MockWebSockServer.set_handler(server_pid, fn
      {:text, "ping"} -> {:reply, {:text, "pong"}}
      {:text, "subscribe:" <> channel} -> {:reply, {:text, "subscribed:" <> channel}}
      {:text, "unsubscribe:" <> channel} -> {:reply, {:text, "unsubscribed:" <> channel}}
      {:text, "authenticate"} -> {:reply, {:text, "authenticated"}}
      {:text, msg} -> {:reply, {:text, "echo:" <> msg}}
    end)

    on_exit(fn ->
      if Process.alive?(server_pid), do: GenServer.stop(server_pid)
    end)

    %{port: port, server_pid: server_pid}
  end

  test "client maintains connection object during reconnection", %{port: port, server_pid: server_pid} do
    # Connect with reconnection enabled
    {:ok, conn} = connect_client(port)
    
    # Store original connection info
    original_transport_pid = conn.transport_pid
    original_stream_ref = conn.stream_ref
    
    # Verify basic operations work before disconnect
    assert {:ok, _} = Client.send_text(conn, "ping")
    assert {:ok, _} = Client.subscribe(conn, "test_channel")
    assert {:ok, _} = Client.authenticate(conn, %{}, %{})
    
    # Force disconnect by stopping the server
    MockWebSockServer.stop(server_pid)
    Process.sleep(100)
    
    # Restart the server to allow reconnection
    {:ok, new_server_pid, ^port} = MockWebSockServer.start_link(port)
    
    # Set the same handler
    MockWebSockServer.set_handler(new_server_pid, fn
      {:text, "ping"} -> {:reply, {:text, "pong"}}
      {:text, "subscribe:" <> channel} -> {:reply, {:text, "subscribed:" <> channel}}
      {:text, "unsubscribe:" <> channel} -> {:reply, {:text, "unsubscribed:" <> channel}}
      {:text, "authenticate"} -> {:reply, {:text, "authenticated"}}
      {:text, msg} -> {:reply, {:text, "echo:" <> msg}}
    end)
    
    # Wait for reconnection to complete
    wait_for_reconnection(conn)
    
    # Verify connection has been updated
    refute conn.transport_pid == original_transport_pid
    refute conn.stream_ref == original_stream_ref
    assert Process.alive?(conn.transport_pid)
    
    # Verify client operations still work with the updated connection
    assert {:ok, _} = Client.send_text(conn, "ping")
    assert {:ok, _} = Client.subscribe(conn, "another_channel")
    assert {:ok, _} = Client.authenticate(conn, %{}, %{})
    
    # Verify callback was called
    assert_received {:connection_reconnected, reconnected_conn}
    assert reconnected_conn.transport_pid == conn.transport_pid
    assert reconnected_conn.stream_ref == conn.stream_ref
    
    # Clean up
    Client.close(conn)
  end

  test "client preserves adapter state during reconnection", %{port: port, server_pid: server_pid} do
    # Connect with custom adapter state
    initial_adapter_state = %{
      subscriptions: %{"initial_channel" => %{id: 1}},
      auth_status: :authenticated,
      credentials: %{api_key: "test_key"}
    }
    
    {:ok, conn} = connect_client(port, initial_adapter_state)
    
    # Force disconnect by stopping the server
    MockWebSockServer.stop(server_pid)
    Process.sleep(100)
    
    # Restart the server to allow reconnection
    {:ok, new_server_pid, ^port} = MockWebSockServer.start_link(port)
    
    # Set the same handler
    MockWebSockServer.set_handler(new_server_pid, fn
      {:text, _} -> {:reply, {:text, "ok"}}
    end)
    
    # Wait for reconnection to complete
    wait_for_reconnection(conn)
    
    # Verify adapter state was preserved
    assert conn.adapter_state.subscriptions == %{"initial_channel" => %{id: 1}}
    assert conn.adapter_state.auth_status == :authenticated
    assert conn.adapter_state.credentials == %{api_key: "test_key"}
    
    # Clean up
    Client.close(conn)
  end

  # Helper functions
  
  defp connect_client(port, adapter_state \\ %{}) do
    test_pid = self()
    
    Client.connect(TestAdapter, %{
      host: "localhost",
      port: port,
      path: @websocket_path,
      transport: :tcp,
      adapter_state: adapter_state,
      callback_pid: test_pid,
      # Enable reconnection
      retry: 5,
      reconnect: true,
      backoff_type: :linear,
      base_backoff: 300,
      # Ensure options are passed correctly
      transport_opts: %{}
    })
  end
  
  defp wait_for_reconnection(_conn, timeout \\ @reconnect_timeout) do
    test_pid = self()
    ref = make_ref()
    
    # Set up a process to wait for the reconnection message
    spawn(fn ->
      # Not using start_time since we have a fixed timeout
      _start_time = System.monotonic_time(:millisecond)
      
      receive do
        {:connection_reconnected, _reconnected_conn} ->
          send(test_pid, {ref, :reconnected})
      after
        timeout ->
          send(test_pid, {ref, :timeout})
      end
    end)
    
    # Wait for the message or timeout
    receive do
      {^ref, :reconnected} -> 
        # Give a bit of extra time for all processes to stabilize
        Process.sleep(@default_delay * 2)
        :ok
      {^ref, :timeout} -> 
        flunk("Timed out waiting for reconnection")
    after
      timeout + 1000 -> 
        flunk("Timed out waiting for reconnection message")
    end
  end
end