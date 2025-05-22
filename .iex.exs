alias WebsockexNova.Client
alias WebsockexNova.Examples.ClientDeribit
alias WebsockexNova.Examples.ClientDeribitMacro

# .iex.exs -- WebsockexNova debugging helpers

import IEx.Helpers
require Logger

# All helpers are now in WebsockexNova.IExHelpers

defmodule WebsockexNova.IExHelpers do
  @moduledoc """
  IEx helpers for inspecting WebsockexNova connection state.

  Usage in IEx:
    import WebsockexNova.IExHelpers
    conn, state = get_conn_state(conn)
    print_conn(conn)
    print_adapter(conn)
    print_handlers(conn)
    print_full_config(conn)
  """

  # Helper to get the canonical conn and adapter state from a running connection
  # Usage: {conn, state} = get_conn_state(conn)
  def get_conn_state(conn) do
    state = :sys.get_state(conn.transport_pid)
    {conn, state}
  end

  # Helper to pretty-print the top-level fields of conn
  # Usage: print_conn(conn)
  def print_conn(conn) do
    IO.puts("\n=== WebsockexNova.ClientConn (top-level) ===")
    conn
    |> Map.from_struct()
    |> Enum.reject(fn {k, _v} -> k in [:adapter_state, :connection_handler_settings, :auth_handler_settings, :subscription_handler_settings, :error_handler_settings, :message_handler_settings, :extras] end)
    |> Enum.each(fn {k, v} -> IO.puts("#{k}: #{inspect(v, pretty: true)}") end)
    IO.puts("\n--- Handler/Feature State ---")
    IO.puts("rate_limit: #{inspect(conn.rate_limit, pretty: true)}")
    IO.puts("logging: #{inspect(conn.logging, pretty: true)}")
    IO.puts("metrics: #{inspect(conn.metrics, pretty: true)}")
    IO.puts("subscriptions: #{inspect(conn.subscriptions, pretty: true)}")
    IO.puts("reconnection: #{inspect(conn.reconnection, pretty: true)}")
    IO.puts("auth_status: #{inspect(conn.auth_status)}")
    IO.puts("auth_expires_at: #{inspect(conn.auth_expires_at)}")
    IO.puts("auth_refresh_threshold: #{inspect(conn.auth_refresh_threshold)}")
    IO.puts("last_error: #{inspect(conn.last_error)}")
    IO.puts("\n--- Handler Settings ---")
    IO.puts("connection_handler_settings: #{inspect(conn.connection_handler_settings, pretty: true)}")
    IO.puts("auth_handler_settings: #{inspect(conn.auth_handler_settings, pretty: true)}")
    IO.puts("subscription_handler_settings: #{inspect(conn.subscription_handler_settings, pretty: true)}")
    IO.puts("error_handler_settings: #{inspect(conn.error_handler_settings, pretty: true)}")
    IO.puts("message_handler_settings: #{inspect(conn.message_handler_settings, pretty: true)}")
    IO.puts("\n--- Extras ---")
    IO.puts("extras: #{inspect(conn.extras, pretty: true)}")
    # Print full config if present in extras or handler settings
    full_config = conn.extras[:full_config] || conn.connection_handler_settings[:full_config]
    if full_config do
      IO.puts("\n--- Full Adapter Config (from :full_config) ---")
      IO.inspect(full_config, pretty: true)
    end
    :ok
  end

  # Helper to print the adapter module and its state
  # Usage: print_adapter(conn)
  def print_adapter(conn) do
    IO.puts("\n=== Adapter Info ===")
    IO.puts("adapter: #{inspect(conn.adapter)}")
    IO.puts("adapter_state: #{inspect(conn.adapter_state, pretty: true)}")
    :ok
  end

  # Helper to print all handler-specific state in detail
  # Usage: print_handlers(conn)
  def print_handlers(conn) do
    IO.puts("\n=== Handler State ===")
    IO.puts("connection_handler_settings: #{inspect(conn.connection_handler_settings, pretty: true)}")
    IO.puts("auth_handler_settings: #{inspect(conn.auth_handler_settings, pretty: true)}")
    IO.puts("subscription_handler_settings: #{inspect(conn.subscription_handler_settings, pretty: true)}")
    IO.puts("error_handler_settings: #{inspect(conn.error_handler_settings, pretty: true)}")
    IO.puts("message_handler_settings: #{inspect(conn.message_handler_settings, pretty: true)}")
    :ok
  end

  # Helper to print just the full config if present
  # Usage: print_full_config(conn)
  def print_full_config(conn) do
    full_config = conn.extras[:full_config] || conn.connection_handler_settings[:full_config]
    if full_config do
      IO.puts("\n=== Full Adapter Config (from :full_config) ===")
      IO.inspect(full_config, pretty: true)
    else
      IO.puts("No :full_config found in conn.extras or conn.connection_handler_settings.")
    end
    :ok
  end
end

# Make helpers available directly in IEx
import WebsockexNova.IExHelpers

# Usage:
#   {conn, state} = get_conn_state(conn)
#   print_conn(conn)
#   print_adapter(conn)
#   print_handlers(conn)
#   print_full_config(conn)

# WebsockexNew Testing Interface
defmodule WebsockexNewTest do
  @moduledoc """
  Testing interface for WebsockexNew reconnection behavior.
  
  Usage:
    # Connect to test.deribit.com
    client = WebsockexNewTest.connect()
    
    # Connect with custom config
    client = WebsockexNewTest.connect(retry_count: 5, retry_delay: 2000)
    
    # Monitor reconnection attempts
    WebsockexNewTest.monitor_reconnection(client)
    
    # Test reconnection manually
    WebsockexNewTest.test_reconnection()
    
    # Close connection
    WebsockexNewTest.close(client)
  """
  
  alias WebsockexNew.{Client, Config, Reconnection}
  
  @deribit_test_url "wss://test.deribit.com/ws/api/v2"
  
  def connect(opts \\ []) do
    opts = Keyword.merge([retry_count: 10, retry_delay: 1000], opts)
    
    IO.puts("🔌 Connecting to #{@deribit_test_url}")
    IO.puts("   Options: #{inspect(opts)}")
    
    case Client.connect(@deribit_test_url, opts) do
      {:ok, client} ->
        IO.puts("✅ Connected! PID: #{inspect(client.gun_pid)}")
        IO.puts("   State: #{inspect(client.state)}")
        IO.puts("   URL: #{client.url}")
        
        # Subscribe to a test channel
        Client.subscribe(client, ["deribit_price_index.btc_usd"])
        IO.puts("📡 Subscribed to deribit_price_index.btc_usd")
        
        client
        
      {:error, reason} ->
        IO.puts("❌ Connection failed: #{inspect(reason)}")
        nil
    end
  end
  
  def monitor_reconnection(client) when is_map(client) do
    IO.puts("👀 Monitoring connection status...")
    IO.puts("   Now disconnect your WiFi to test reconnection!")
    IO.puts("   Use Ctrl+C to stop monitoring")
    
    spawn(fn -> monitor_loop(client) end)
  end
  
  defp monitor_loop(client) do
    state = Client.get_state(client)
    
    case state do
      :connected ->
        IO.puts("🟢 Status: CONNECTED")
      :connecting ->
        IO.puts("🟡 Status: CONNECTING...")
      :disconnected ->
        IO.puts("🔴 Status: DISCONNECTED")
      _ ->
        IO.puts("⚪ Status: #{inspect(state)}")
    end
    
    # Check if process is still alive
    if Process.alive?(client.gun_pid) do
      :timer.sleep(2000)
      monitor_loop(client)
    else
      IO.puts("💀 Gun process died: #{inspect(client.gun_pid)}")
    end
  end
  
  def test_reconnection do
    IO.puts("🧪 Testing reconnection logic...")
    
    {:ok, config} = Config.new(@deribit_test_url, retry_count: 3, retry_delay: 1000)
    
    IO.puts("   Config: #{inspect(config)}")
    IO.puts("   Attempting reconnection with subscriptions...")
    
    subscriptions = ["deribit_price_index.btc_usd"]
    
    case Reconnection.reconnect(config, 0, subscriptions) do
      {:ok, client} ->
        IO.puts("✅ Reconnection successful!")
        IO.puts("   New client: #{inspect(client.gun_pid)}")
        client
        
      {:error, :max_retries} ->
        IO.puts("❌ Reconnection failed: max retries exceeded")
        nil
        
      {:error, reason} ->
        IO.puts("❌ Reconnection failed: #{inspect(reason)}")
        nil
    end
  end
  
  def simulate_disconnect_test do
    IO.puts("🔌 Testing reconnection by simulating connection failure...")
    
    # Connect first
    client = connect()
    
    if client do
      IO.puts("📍 Original connection: #{inspect(client.gun_pid)}")
      
      # Kill the Gun process to simulate network failure
      Process.exit(client.gun_pid, :kill)
      :timer.sleep(100)
      
      IO.puts("💀 Killed Gun process, now testing reconnection...")
      
      # Test reconnection
      {:ok, config} = Config.new(@deribit_test_url, retry_count: 3, retry_delay: 500)
      subscriptions = ["deribit_price_index.btc_usd"]
      
      case Reconnection.reconnect(config, 0, subscriptions) do
        {:ok, new_client} ->
          IO.puts("✅ Reconnection successful after simulated failure!")
          IO.puts("   New connection: #{inspect(new_client.gun_pid)}")
          IO.puts("   Subscriptions restored: #{inspect(subscriptions)}")
          new_client
          
        {:error, reason} ->
          IO.puts("❌ Reconnection failed: #{inspect(reason)}")
          nil
      end
    else
      IO.puts("❌ Initial connection failed")
      nil
    end
  end
  
  def close(client) when is_map(client) do
    IO.puts("🔌 Closing connection...")
    Client.close(client)
    IO.puts("✅ Connection closed")
    :ok
  end
  
  def close(_), do: :ok
  
  def status(client) when is_map(client) do
    state = Client.get_state(client)
    alive = Process.alive?(client.gun_pid)
    
    IO.puts("📊 Connection Status:")
    IO.puts("   State: #{inspect(state)}")
    IO.puts("   PID: #{inspect(client.gun_pid)} (alive: #{alive})")
    IO.puts("   URL: #{client.url}")
    
    {state, alive}
  end
  
  def help do
    IO.puts("""
    
    🚀 WebsockexNew Testing Interface
    
    Basic Usage:
      client = WebsockexNewTest.connect()                    # Connect with defaults
      client = WebsockexNewTest.connect(retry_count: 5)      # Connect with custom options
      WebsockexNewTest.status(client)                        # Check connection status
      WebsockexNewTest.close(client)                         # Close connection
    
    Reconnection Testing:
      WebsockexNewTest.monitor_reconnection(client)          # Monitor connection (disable WiFi to test)
      WebsockexNewTest.test_reconnection()                   # Test reconnection logic manually
      WebsockexNewTest.simulate_disconnect_test()            # Kill connection and test reconnection
    
    Direct API:
      WebsockexNew.Client.connect("wss://...")               # Direct client connection
      WebsockexNew.Reconnection.reconnect(config, 0, [])    # Direct reconnection test
    
    Tips:
    1. Connect first: client = WebsockexNewTest.connect()
    2. Start monitoring: WebsockexNewTest.monitor_reconnection(client)
    3. Disable WiFi to trigger reconnection attempts
    4. Re-enable WiFi to see successful reconnection
    
    """)
  end
end

# Make testing interface available
import WebsockexNewTest

IO.puts("🚀 WebsockexNew Testing Interface loaded!")
IO.puts("   Type: WebsockexNewTest.help() for usage instructions")
