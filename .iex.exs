# WebsockexNew Interactive Testing
# ================================
# 
# This file sets up an interactive environment for testing WebsockexNew library components.
# It provides convenience functions for testing WebSocket connections, subscriptions,
# reconnection logic, heartbeat functionality, and various error scenarios.
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
      
      # Connect with debug mode
      client = WebsockexNewTest.connect_debug()
      
      # Test heartbeat functionality
      WebsockexNewTest.test_heartbeat()
      
      # Subscribe to channels
      WebsockexNewTest.subscribe(client, ["deribit_price_index.btc_usd"])
      
      # Send custom messages
      WebsockexNewTest.send_json(client, %{method: "public/test"})
  """
  
  alias WebsockexNew.{Client, Config}
  alias WebsockexNew.Examples.DeribitAdapter
  
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
  
  def connect_debug(opts \\ []) do
    IO.puts("🔌 Connecting to Deribit with DEBUG mode enabled...")
    IO.puts("📝 All messages will be printed to console")
    
    # Create a debug handler that prints all messages
    debug_handler = WebsockexNew.MessageHandler.create_handler(
      on_message: fn 
        {:message, {:text, json}} ->
          IO.puts("\n📨 [TEXT MESSAGE] #{DateTime.utc_now() |> DateTime.to_string()}")
          case Jason.decode(json) do
            {:ok, decoded} ->
              IO.inspect(decoded, label: "   JSON", pretty: true)
            {:error, _} ->
              IO.puts("   Raw text: #{json}")
          end
          :ok
        {:message, {:binary, data}} ->
          IO.puts("\n📦 [BINARY MESSAGE] #{DateTime.utc_now() |> DateTime.to_string()}")
          IO.inspect(data, label: "   Binary data", pretty: true)
          :ok
        {:message, other} ->
          IO.puts("\n📨 [MESSAGE] #{DateTime.utc_now() |> DateTime.to_string()}")
          IO.inspect(other, label: "   Content", pretty: true)
          :ok
        other ->
          IO.puts("\n🔔 [OTHER] #{DateTime.utc_now() |> DateTime.to_string()}")
          IO.inspect(other, label: "   Data", pretty: true)
          :ok
      end,
      on_upgrade: fn info ->
        IO.puts("\n🔗 [UPGRADE] WebSocket connection upgraded")
        IO.inspect(info, label: "   Info", pretty: true)
        :ok
      end,
      on_error: fn error ->
        IO.puts("\n❌ [ERROR] #{DateTime.utc_now() |> DateTime.to_string()}")
        IO.inspect(error, label: "   Error", pretty: true)
        :ok
      end,
      on_down: fn reason ->
        IO.puts("\n📉 [DOWN] Connection down")
        IO.inspect(reason, label: "   Reason", pretty: true)
        :ok
      end
    )
    
    connect(Keyword.merge(opts, [handler: debug_handler]))
  end
  
  def test_automatic_heartbeat(interval \\ 10) do
    IO.puts("""
    💓 Testing AUTOMATIC Deribit Heartbeat Functionality
    ===================================================
    Using DeribitAdapter with built-in automatic heartbeat responses
    Heartbeat interval: #{interval} seconds
    """)
    
    # Create debug handler to highlight heartbeat messages
    heartbeat_handler = create_heartbeat_debug_handler()
    
    # Connect using DeribitAdapter with automatic heartbeat configuration
    IO.puts("🔌 Connecting with DeribitAdapter (automatic heartbeat enabled)...")
    
    case DeribitAdapter.connect([
      url: @deribit_test_url,
      handler: heartbeat_handler,
      heartbeat_interval: interval
    ]) do
      {:ok, adapter} ->
        IO.puts("✅ Connected with automatic heartbeat support!")
        IO.puts("   Client will automatically respond to test_request messages")
        
        # Enable server-side heartbeat  
        IO.puts("\n📤 Enabling server-side heartbeat...")
        {:ok, heartbeat_request} = DeribitAdapter.set_heartbeat(%{interval: interval})
        Client.send_message(adapter.client, Jason.encode!(heartbeat_request))
        
        IO.puts("\n⏳ Watching automatic heartbeat responses...")
        IO.puts("   🔍 Look for:")
        IO.puts("   📨 [HEARTBEAT IN] test_request messages from server")
        IO.puts("   📤 [HEARTBEAT OUT] automatic public/test responses")
        IO.puts("   💚 [HEARTBEAT OK] successful heartbeat handling")
        IO.puts("\n   Press Enter to stop...")
        
        # Start monitoring heartbeat health
        spawn(fn -> monitor_heartbeat_health(adapter.client) end)
        
        # Wait for user input
        IO.gets("")
        
        # Disable heartbeat
        IO.puts("\n📤 Disabling heartbeat...")
        {:ok, disable_request} = DeribitAdapter.disable_heartbeat()
        Client.send_message(adapter.client, Jason.encode!(disable_request))
        
        :timer.sleep(1000)
        
        # Close
        IO.puts("\n🔌 Closing connection...")
        Client.close(adapter.client)
        IO.puts("✅ Automatic heartbeat test completed!")
        
      {:error, reason} ->
        IO.puts("❌ Connection failed: #{inspect(reason)}")
    end
    
    :ok
  end
  
  def test_heartbeat(interval \\ 10) do
    IO.puts("""
    💓 Testing Manual Heartbeat Functionality (Legacy)
    =================================================
    Setting up heartbeat with #{interval} second interval
    """)
    
    # Connect with debug mode to see all messages
    client = connect_debug()
    
    if client do
      # Enable heartbeat on Deribit side
      IO.puts("\n📤 Enabling server-side heartbeat...")
      {:ok, heartbeat_request} = DeribitAdapter.set_heartbeat(%{interval: interval})
      Client.send_message(client, Jason.encode!(heartbeat_request))
      
      IO.puts("\n⏳ Waiting for heartbeat messages...")
      IO.puts("   You should see:")
      IO.puts("   1. Regular heartbeat messages with type: 'heartbeat'")
      IO.puts("   2. test_request messages that trigger automatic responses")
      IO.puts("   3. The client automatically sending public/test responses")
      IO.puts("\n   Press Enter to disable heartbeat and close connection...")
      
      # Wait for user input
      IO.gets("")
      
      # Disable heartbeat
      IO.puts("\n📤 Disabling heartbeat...")
      {:ok, disable_request} = DeribitAdapter.disable_heartbeat()
      Client.send_message(client, Jason.encode!(disable_request))
      
      :timer.sleep(1000)
      
      # Close
      IO.puts("\n🔌 Closing connection...")
      Client.close(client)
      IO.puts("✅ Heartbeat test completed!")
    else
      IO.puts("❌ Test aborted - connection failed")
    end
    
    :ok
  end
  
  def test_heartbeat_with_config do
    IO.puts("""
    💓 Testing Client-side Heartbeat Configuration
    ==============================================
    """)
    
    # Connect with heartbeat configuration
    IO.puts("🔌 Connecting with heartbeat config...")
    
    {:ok, config} = Config.new(@deribit_test_url)
    {:ok, client} = Client.connect(config,
      handler: create_debug_handler(),
      heartbeat_config: %{
        type: :deribit,
        interval: 10_000,
        test_request_handler: fn ->
          IO.puts("🔄 [HEARTBEAT] Sending automatic test response")
          {:ok, request} = DeribitAdapter.test_request()
          Jason.encode!(request)
        end
      }
    )
    
    IO.puts("✅ Connected with heartbeat configuration!")
    
    # Enable server-side heartbeat
    IO.puts("\n📤 Enabling server-side heartbeat...")
    {:ok, heartbeat_request} = DeribitAdapter.set_heartbeat(%{interval: 10})
    Client.send_message(client, Jason.encode!(heartbeat_request))
    
    IO.puts("\n⏳ Observing heartbeat behavior for 30 seconds...")
    :timer.sleep(30_000)
    
    # Disable and close
    {:ok, disable_request} = DeribitAdapter.disable_heartbeat()
    Client.send_message(client, Jason.encode!(disable_request))
    Client.close(client)
    
    IO.puts("✅ Heartbeat config test completed!")
  end
  
  def test_gun_debug do
    IO.puts("""
    🔫 Testing Complete Gun Debug Flow
    =================================
    This shows the complete Gun connection lifecycle with full debugging:
    - Gun connection establishment
    - WebSocket upgrade process  
    - Message flow and processing
    - Heartbeat integration
    - Connection monitoring
    """)
    
    IO.puts("🔌 Starting Gun debug connection...")
    IO.puts("📝 Watch for detailed Gun protocol messages")
    
    # Create minimal handler to not interfere with Gun debug logs
    minimal_handler = fn _ -> :ok end
    
    case DeribitAdapter.connect([
      url: @deribit_test_url,
      handler: minimal_handler,
      heartbeat_interval: 15  # 15 second heartbeat for faster demo
    ]) do
      {:ok, adapter} ->
        IO.puts("\n✅ Connection established - monitoring Gun events...")
        
        # Send a test message to see WebSocket frame logging
        IO.puts("\n📤 Sending test message to see Gun WebSocket frame logging...")
        {:ok, test_request} = DeribitAdapter.test_request()
        Client.send_message(adapter.client, Jason.encode!(test_request))
        
        # Enable heartbeat to see test_request/response cycle
        IO.puts("\n📤 Enabling heartbeat to see Gun frame exchange...")
        {:ok, heartbeat_request} = DeribitAdapter.set_heartbeat(%{interval: 15})
        Client.send_message(adapter.client, Jason.encode!(heartbeat_request))
        
        # Subscribe to see more message activity
        IO.puts("\n📡 Subscribing to channel to see more Gun activity...")
        {:ok, sub_request} = DeribitAdapter.subscribe_request(%{channels: ["deribit_price_index.btc_usd"]})
        Client.send_message(adapter.client, Jason.encode!(sub_request))
        
        IO.puts("\n⏳ Observing Gun debug output for 45 seconds...")
        IO.puts("   🔍 Look for:")
        IO.puts("   🔫 [GUN OPEN] - Initial connection")
        IO.puts("   🔗 [GUN UPGRADE] - WebSocket upgrade")
        IO.puts("   📨 [GUN WS TEXT] - Text frame messages")
        IO.puts("   💓 [HEARTBEAT DETECTED] - Heartbeat processing")
        IO.puts("   📤 [HEARTBEAT RESPONSE] - Automatic responses")
        IO.puts("\n   Press Enter to stop early or wait 45 seconds...")
        
        # Create a task to wait for user input or timeout
        task = Task.async(fn ->
          IO.gets("")
          :user_stopped
        end)
        
        # Wait either for user input or 45 seconds
        case Task.yield(task, 45_000) do
          {:ok, :user_stopped} ->
            IO.puts("\n👤 Stopped by user")
          nil ->
            Task.shutdown(task)
            IO.puts("\n⏰ 45 second observation period completed")
        end
        
        # Disable heartbeat
        IO.puts("\n📤 Disabling heartbeat...")
        {:ok, disable_request} = DeribitAdapter.disable_heartbeat()
        Client.send_message(adapter.client, Jason.encode!(disable_request))
        
        :timer.sleep(1000)
        
        # Close connection to see Gun cleanup
        IO.puts("\n🔌 Closing connection to see Gun cleanup logs...")
        Client.close(adapter.client)
        
        :timer.sleep(500)
        
        IO.puts("✅ Gun debug test completed!")
        IO.puts("📊 Summary of what you observed:")
        IO.puts("   - Complete Gun connection establishment")
        IO.puts("   - WebSocket protocol upgrade")
        IO.puts("   - Real-time message frame processing")
        IO.puts("   - Automatic heartbeat request/response cycle")
        IO.puts("   - Clean connection termination")
        
      {:error, reason} ->
        IO.puts("❌ Gun debug test failed: #{inspect(reason)}")
    end
    
    :ok
  end
  
  def test_gun_reconnection do
    IO.puts("""
    🔄 Testing Gun Reconnection Debug Flow
    =====================================
    This will show Gun reconnection with full debugging
    """)
    
    case DeribitAdapter.connect([
      url: @deribit_test_url,
      heartbeat_interval: 10
    ]) do
      {:ok, adapter} ->
        IO.puts("✅ Initial connection established")
        IO.puts("📍 Gun PID: #{inspect(adapter.client.gun_pid)}")
        IO.puts("📍 Client GenServer PID: #{inspect(adapter.client.server_pid)}")
        
        IO.puts("\n💥 Killing Gun process to trigger reconnection...")
        IO.puts("   Watch for:")
        IO.puts("   💀 [PROCESS DOWN] - Gun process termination")
        IO.puts("   🔄 [GUN RECONNECT] - Reconnection attempt")
        IO.puts("   🔫 [GUN OPEN] - New connection establishment")
        IO.puts("   🔗 [GUN UPGRADE] - New WebSocket upgrade")
        
        # Kill the Gun process
        Process.exit(adapter.client.gun_pid, :kill)
        
        IO.puts("\n⏳ Waiting 15 seconds to observe reconnection...")
        :timer.sleep(15_000)
        
        # Check if we have a new Gun PID
        new_state = Client.get_state(adapter.client)
        IO.puts("\n📊 Reconnection Result:")
        IO.puts("   🔄 Connection State: #{new_state}")
        
        if new_state == :connected do
          IO.puts("   ✅ Reconnection successful!")
        else
          IO.puts("   ⏳ Reconnection in progress or failed")
        end
        
        # Clean close
        :timer.sleep(2000)
        Client.close(adapter.client)
        IO.puts("✅ Gun reconnection test completed!")
        
      {:error, reason} ->
        IO.puts("❌ Reconnection test failed: #{inspect(reason)}")
    end
    
    :ok
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
    
    # Use DeribitAdapter for proper subscription format
    {:ok, request} = DeribitAdapter.subscribe_request(%{channels: channels})
    json = Jason.encode!(request)
    
    case Client.send_message(client, json) do
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
    
    client = connect_debug()
    if client do
      IO.puts("📍 Client GenServer PID: #{inspect(client.server_pid)}")
      IO.puts("📍 Gun PID: #{inspect(client.gun_pid)}")
      IO.puts("\nTry: Process.exit(client.gun_pid, :kill)")
      IO.puts("Then check: Client.get_state(client)")
      IO.puts("\nMonitoring connection state...")
      monitor_connection(client)
      client
    end
  end
  
  def close(client) when is_map(client) do
    IO.puts("🔌 Closing connection...")
    Client.close(client)
    IO.puts("✅ Connection closed")
    :ok
  end
  
  defp create_debug_handler do
    WebsockexNew.MessageHandler.create_handler(
      on_message: fn 
        {:message, {:text, json}} ->
          IO.puts("\n📨 [TEXT MESSAGE] #{DateTime.utc_now() |> DateTime.to_string()}")
          case Jason.decode(json) do
            {:ok, decoded} ->
              IO.inspect(decoded, label: "   JSON", pretty: true)
            {:error, _} ->
              IO.puts("   Raw text: #{json}")
          end
          :ok
        {:message, {:binary, data}} ->
          IO.puts("\n📦 [BINARY MESSAGE] #{DateTime.utc_now() |> DateTime.to_string()}")
          IO.inspect(data, label: "   Binary data", pretty: true)
          :ok
        {:message, other} ->
          IO.puts("\n📨 [MESSAGE] #{DateTime.utc_now() |> DateTime.to_string()}")
          IO.inspect(other, label: "   Content", pretty: true)
          :ok
        other ->
          IO.puts("\n🔔 [OTHER] #{DateTime.utc_now() |> DateTime.to_string()}")
          IO.inspect(other, label: "   Data", pretty: true)
          :ok
      end,
      on_error: fn error ->
        IO.puts("\n❌ [ERROR] #{DateTime.utc_now() |> DateTime.to_string()}")
        IO.inspect(error, label: "   Error", pretty: true)
        :ok
      end
    )
  end
  
  defp create_heartbeat_debug_handler do
    WebsockexNew.MessageHandler.create_handler(
      on_message: fn 
        {:message, {:text, json}} ->
          timestamp = DateTime.utc_now() |> DateTime.to_string()
          
          case Jason.decode(json) do
            {:ok, %{"method" => "heartbeat", "params" => %{"type" => "test_request"}} = decoded} ->
              IO.puts("\n💓 [HEARTBEAT IN] #{timestamp}")
              IO.puts("   🚨 test_request received - Client will auto-respond!")
              IO.inspect(decoded, label: "   Heartbeat data", pretty: true)
              
            {:ok, %{"method" => "public/test"} = decoded} ->
              IO.puts("\n📤 [HEARTBEAT OUT] #{timestamp}")
              IO.puts("   ✅ Automatic heartbeat response sent")
              IO.inspect(decoded, label: "   Response data", pretty: true)
              
            {:ok, %{"method" => "heartbeat"} = decoded} ->
              IO.puts("\n💚 [HEARTBEAT OK] #{timestamp}")
              IO.puts("   💗 Heartbeat acknowledged")
              IO.inspect(decoded, label: "   Heartbeat data", pretty: true)
              
            {:ok, decoded} ->
              IO.puts("\n📨 [MESSAGE] #{timestamp}")
              IO.inspect(decoded, label: "   JSON", pretty: true)
              
            {:error, _} ->
              IO.puts("\n📨 [TEXT] #{timestamp}")
              IO.puts("   Raw text: #{json}")
          end
          :ok
          
        {:message, other} ->
          IO.puts("\n📨 [MESSAGE] #{DateTime.utc_now() |> DateTime.to_string()}")
          IO.inspect(other, label: "   Content", pretty: true)
          :ok
          
        other ->
          IO.puts("\n🔔 [OTHER] #{DateTime.utc_now() |> DateTime.to_string()}")
          IO.inspect(other, label: "   Data", pretty: true)
          :ok
      end,
      on_error: fn error ->
        IO.puts("\n❌ [ERROR] #{DateTime.utc_now() |> DateTime.to_string()}")
        IO.inspect(error, label: "   Error", pretty: true)
        :ok
      end
    )
  end
  
  defp monitor_heartbeat_health(client) do
    :timer.sleep(5000)
    
    try do
      health = Client.get_heartbeat_health(client)
      if health do
        IO.puts("\n💚 [HEARTBEAT HEALTH] #{DateTime.utc_now() |> DateTime.to_string()}")
        IO.inspect(health, label: "   Health metrics", pretty: true)
      end
    rescue
      _ -> :ok  # Client might not support heartbeat health yet
    end
    
    monitor_heartbeat_health(client)
  end
  
  def help do
    IO.puts("""
    WebsockexNew Interactive Testing with Heartbeat Support
    =======================================================
    
    Quick Start:
      client = WebsockexNewTest.connect()
      WebsockexNewTest.quick_test()
    
    Debug Mode (see all messages):
      client = WebsockexNewTest.connect_debug()
      WebsockexNewTest.test_heartbeat()
    
    Heartbeat Testing:
      WebsockexNewTest.test_automatic_heartbeat()            # Test automatic heartbeat (RECOMMENDED)
      WebsockexNewTest.test_automatic_heartbeat(5)           # Test with 5 second interval
      WebsockexNewTest.test_heartbeat()                      # Test manual heartbeat (legacy)
      WebsockexNewTest.test_heartbeat_with_config()          # Test client-side config
    
    Gun Protocol Debugging:
      WebsockexNewTest.test_gun_debug()                      # Complete Gun connection debug flow
      WebsockexNewTest.test_gun_reconnection()               # Gun reconnection debug flow
    
    Connection Management:
      WebsockexNewTest.connect()                             # Connect with defaults
      WebsockexNewTest.connect_debug()                       # Connect with debug output
      WebsockexNewTest.connect(timeout: 10_000)              # Connect with options
      WebsockexNewTest.close(client)                         # Close connection
    
    Message Operations:
      WebsockexNewTest.send_json(client, %{method: "test"})  # Send JSON message
      WebsockexNewTest.subscribe(client, ["channel"])        # Subscribe to channels
    
    Testing & Monitoring:
      WebsockexNewTest.test_error_scenarios()                # Test error handling
      WebsockexNewTest.monitor_connection(client)            # Monitor connection state
      WebsockexNewTest.test_internal_reconnection()          # Test auto-reconnection
    
    Direct API:
      WebsockexNew.Client.connect("wss://...")               # Direct client connection
      DeribitAdapter.set_heartbeat(%{interval: 10})          # Get heartbeat request
      DeribitAdapter.test_request()                          # Get test request
    
    Tips:
      - Use test_automatic_heartbeat() to see automatic heartbeat responses
      - Use test_gun_debug() to see complete Gun protocol flow
      - DeribitAdapter.connect() enables automatic heartbeat handling
      - test_request messages trigger instant automatic responses
      - Heartbeat health is monitored and displayed in real-time
      - Kill Gun process to test reconnection: Process.exit(client.gun_pid, :kill)
      - Look for 💓 [HEARTBEAT IN] and 📤 [HEARTBEAT OUT] messages
      - Look for 🔫 [GUN OPEN] and 🔗 [GUN UPGRADE] for connection flow
      - Look for 📨 [GUN WS TEXT] for WebSocket frame activity
    """)
  end
end

# Print help on startup
WebsockexNewTest.help()