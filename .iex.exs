# WebsockexNew Interactive Testing
# ================================
# 
# This file sets up an interactive environment for testing WebsockexNew library components.
# It provides convenience functions for testing WebSocket connections, subscriptions,
# reconnection logic, and various error scenarios.
#
# Quick Start:
#   iex -S mix
#   WebsockexNewTest.quick_test()

defmodule WebsockexNewTest do
  @moduledoc """
  Interactive testing module for WebsockexNew library.
  
  ## Quick Start
  
      # Basic connection test
      WebsockexNewTest.quick_test()
      
      # Connect with custom options
      client = WebsockexNewTest.connect(timeout: 10_000)
      
      # Subscribe to channels
      WebsockexNewTest.subscribe(client, ["deribit_price_index.btc_usd"])
      
      # Send custom messages
      WebsockexNewTest.send_json(client, %{method: "public/test"})
  """
  
  alias WebsockexNew.{Client, Config}
  
  @deribit_test_url "wss://test.deribit.com/ws/api/v2"
  
  def connect(opts \\ []) do
    IO.puts("🔌 Connecting to Deribit test server...")
    
    case Client.connect(@deribit_test_url, opts) do
      {:ok, client} ->
        IO.puts("✅ Connected successfully!")
        IO.puts("   Client PID: #{inspect(client.server_pid)}")
        IO.puts("   Gun PID: #{inspect(client.gun_pid)}")
        IO.puts("   Stream: #{inspect(client.stream_ref)}")
        client
        
      {:error, reason} ->
        IO.puts("❌ Connection failed: #{inspect(reason)}")
        nil
    end
  end
  
  def quick_test do
    IO.puts("""
    🚀 Running WebsockexNew Quick Test
    ==================================
    """)
    
    # Connect
    client = connect()
    
    if client do
      # Test basic message
      IO.puts("\n📤 Sending test message...")
      send_json(client, %{
        "jsonrpc" => "2.0",
        "method" => "public/test",
        "params" => %{},
        "id" => 1
      })
      
      # Subscribe to a channel
      IO.puts("\n📡 Subscribing to BTC price index...")
      subscribe(client, ["deribit_price_index.btc_usd"])
      
      # Wait a bit to see some messages
      IO.puts("\n⏳ Waiting 5 seconds to observe messages...")
      :timer.sleep(5000)
      
      # Close
      IO.puts("\n🔌 Closing connection...")
      Client.close(client)
      IO.puts("✅ Test completed!")
    else
      IO.puts("❌ Test aborted - connection failed")
    end
    
    :ok
  end
  
  def subscribe(client, channels) when is_list(channels) do
    IO.puts("📡 Subscribing to channels: #{inspect(channels)}")
    
    case Client.subscribe(client, channels) do
      :ok ->
        IO.puts("✅ Subscription request sent")
        :ok
        
      {:error, reason} ->
        IO.puts("❌ Subscription failed: #{inspect(reason)}")
        {:error, reason}
    end
  end
  
  def send_json(client, message) when is_map(message) do
    json = Jason.encode!(message)
    IO.puts("📤 Sending JSON: #{json}")
    
    case Client.send_message(client, json) do
      :ok ->
        IO.puts("✅ Message sent")
        :ok
        
      {:error, reason} ->
        IO.puts("❌ Send failed: #{inspect(reason)}")
        {:error, reason}
    end
  end
  
  def test_error_scenarios do
    IO.puts("🧪 Testing error scenarios...")
    
    # Test invalid URL
    IO.puts("\n1. Testing invalid URL...")
    {:error, reason} = Client.connect("not-a-url")
    IO.puts("   ✅ Got expected error: #{inspect(reason)}")
    
    # Test connection timeout
    IO.puts("\n2. Testing connection timeout...")
    {:error, reason} = Client.connect(@deribit_test_url, timeout: 1)
    IO.puts("   ✅ Got expected error: #{inspect(reason)}")
    
    # Test send on disconnected client
    IO.puts("\n3. Testing send on closed connection...")
    {:ok, client} = Client.connect(@deribit_test_url)
    Client.close(client)
    :timer.sleep(100)
    result = Client.send_message(client, "test")
    IO.puts("   ✅ Got expected result: #{inspect(result)}")
    
    IO.puts("\n✅ All error scenarios passed!")
  end
  
  def monitor_connection(client) do
    IO.puts("👁️  Monitoring connection state...")
    spawn(fn -> 
      monitor_loop(client)
    end)
  end
  
  defp monitor_loop(client) do
    state = Client.get_state(client)
    IO.puts("[#{DateTime.utc_now() |> DateTime.to_string()}] Connection state: #{state}")
    :timer.sleep(5000)
    monitor_loop(client)
  end
  
  def test_internal_reconnection do
    IO.puts("🔄 Testing internal reconnection...")
    IO.puts("Note: Client GenServer now handles reconnection internally")
    IO.puts("Kill the Gun process and watch the Client reconnect automatically")
    
    client = connect()
    if client do
      IO.puts("📍 Client GenServer PID: #{inspect(client.server_pid)}")
      IO.puts("📍 Gun PID: #{inspect(client.gun_pid)}")
      IO.puts("\nTry: Process.exit(client.gun_pid, :kill)")
      IO.puts("Then check: Client.get_state(client)")
      client
    end
  end
  
  def close(client) when is_map(client) do
    IO.puts("🔌 Closing connection...")
    Client.close(client)
    IO.puts("✅ Connection closed")
    :ok
  end
  
  def help do
    IO.puts("""
    WebsockexNew Interactive Testing
    ================================
    
    Quick Start:
      client = WebsockexNewTest.connect()
      WebsockexNewTest.quick_test()
    
    Connection Management:
      WebsockexNewTest.connect()                             # Connect with defaults
      WebsockexNewTest.connect(timeout: 10_000)              # Connect with options
      WebsockexNewTest.close(client)                         # Close connection
    
    Message Operations:
      WebsockexNewTest.send_json(client, %{method: "test"})  # Send JSON message
      WebsockexNewTest.subscribe(client, ["channel"])        # Subscribe to channels
    
    Testing & Monitoring:
      WebsockexNewTest.test_error_scenarios()                # Test error handling
      WebsockexNewTest.monitor_connection(client)            # Monitor connection state
    
    Internal Reconnection Testing:
      WebsockexNewTest.test_internal_reconnection()          # Test Client's internal reconnection
    
    Direct API:
      WebsockexNew.Client.connect("wss://...")               # Direct client connection
      # Client handles reconnection internally now
    
    Tips:
      - The Client GenServer now handles reconnection internally
      - Kill Gun process to test reconnection: Process.exit(client.gun_pid, :kill)
      - Monitor connection state: WebsockexNewTest.monitor_connection(client)
    """)
  end
end

# Print help on startup
WebsockexNewTest.help()