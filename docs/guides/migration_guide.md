# Migration Guide: From Raw Behaviors to Macros

This guide helps you migrate existing WebsockexNova implementations from raw behavior implementations to the more convenient macro-based approach.

## Table of Contents
1. [Why Migrate to Macros](#why-migrate-to-macros)
2. [Migration Overview](#migration-overview)
3. [Client Migration](#client-migration)
4. [Adapter Migration](#adapter-migration)
5. [Behavior Migration](#behavior-migration)
6. [Testing Migration](#testing-migration)
7. [Incremental Migration](#incremental-migration)
8. [Common Patterns](#common-patterns)
9. [Troubleshooting Migration](#troubleshooting-migration)

## Why Migrate to Macros

Benefits of using macros over raw behaviors:

1. **Less Boilerplate**: Macros provide default implementations
2. **Cleaner Code**: Focus on business logic, not plumbing
3. **Better Defaults**: Sensible defaults are included
4. **Easier Testing**: Built-in test helpers
5. **Future-proof**: New features automatically available

## Migration Overview

### Before: Raw Implementation

```elixir
defmodule MyApp.OldClient do
  alias WebsockexNova.Client
  
  def connect(opts \\ %{}) do
    adapter = MyApp.OldAdapter
    merged_opts = Map.merge(default_options(), opts)
    Client.connect(adapter, merged_opts)
  end
  
  def authenticate(conn, credentials) do
    Client.authenticate(conn, credentials)
  end
  
  def send_message(conn, message) do
    Client.send_json(conn, message)
  end
  
  def subscribe(conn, channel) do
    Client.subscribe(conn, channel)
  end
  
  defp default_options do
    %{
      host: "api.example.com",
      port: 443,
      path: "/ws"
    }
  end
end
```

### After: Macro-based Implementation

```elixir
defmodule MyApp.NewClient do
  use WebsockexNova.ClientMacro, 
    adapter: MyApp.NewAdapter,
    default_options: %{
      host: "api.example.com",
      port: 443,
      path: "/ws"
    }
  
  # All standard methods are automatically included
  # Only add domain-specific methods
  def send_message(conn, message) do
    send_json(conn, message)  # Inherited from macro
  end
end
```

## Client Migration

### Step 1: Identify Current Implementation

```elixir
# Old client structure
defmodule MyApp.TradingClient do
  alias WebsockexNova.Client
  alias MyApp.TradingAdapter
  
  def connect(opts) do
    full_opts = build_options(opts)
    Client.connect(TradingAdapter, full_opts)
  end
  
  def place_order(conn, order) do
    message = build_order_message(order)
    Client.send_json(conn, message)
  end
  
  def subscribe_market_data(conn, symbols) do
    Enum.each(symbols, fn symbol ->
      Client.subscribe(conn, "market.#{symbol}")
    end)
  end
  
  defp build_options(opts) do
    Map.merge(%{
      url: "wss://trading.example.com",
      heartbeat_interval: 30_000
    }, opts)
  end
  
  defp build_order_message(order) do
    %{
      action: "place_order",
      order: order,
      timestamp: DateTime.utc_now()
    }
  end
end
```

### Step 2: Convert to Macro

```elixir
defmodule MyApp.TradingClient do
  use WebsockexNova.ClientMacro, 
    adapter: MyApp.TradingAdapter
  
  # Override default options
  def default_opts do
    %{
      url: "wss://trading.example.com",
      heartbeat_interval: 30_000
    }
  end
  
  # Keep domain-specific methods
  def place_order(conn, order) do
    message = build_order_message(order)
    send_json(conn, message)  # Now available from macro
  end
  
  def subscribe_market_data(conn, symbols) do
    Enum.each(symbols, fn symbol ->
      subscribe(conn, "market.#{symbol}")  # From macro
    end)
  end
  
  # Private helpers remain the same
  defp build_order_message(order) do
    %{
      action: "place_order",
      order: order,
      timestamp: DateTime.utc_now()
    }
  end
end
```

### Step 3: Update Usage

```elixir
# Before
{:ok, conn} = MyApp.TradingClient.connect(%{})

# After - exact same API!
{:ok, conn} = MyApp.TradingClient.connect(%{})
```

## Adapter Migration

### Step 1: Identify Current Adapter

```elixir
# Old adapter implementation
defmodule MyApp.OldAdapter do
  @behaviour WebsockexNova.Adapter
  
  def child_spec(config) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [config]},
      type: :worker,
      restart: :permanent
    }
  end
  
  def handlers do
    %{
      connection: MyApp.ConnectionHandler,
      message: MyApp.MessageHandler,
      error: MyApp.ErrorHandler,
      auth: MyApp.AuthHandler
    }
  end
  
  def init(config) do
    {:ok, config}
  end
  
  def url(config) do
    config.url || "wss://default.example.com"
  end
  
  def headers(config) do
    base_headers = [
      {"User-Agent", "MyApp/1.0"}
    ]
    
    if config[:auth_token] do
      [{"Authorization", "Bearer #{config.auth_token}"} | base_headers]
    else
      base_headers
    end
  end
  
  def options(config) do
    %{
      heartbeat_interval: config[:heartbeat_interval] || 30_000,
      reconnect_interval: config[:reconnect_interval] || 5_000
    }
  end
end
```

### Step 2: Convert to Macro

```elixir
defmodule MyApp.NewAdapter do
  use WebsockexNova.Adapter
  
  # Most methods have sensible defaults
  # Only override what you need
  
  @impl true
  def handlers do
    %{
      connection: MyApp.ConnectionHandler,
      message: MyApp.MessageHandler,
      error: MyApp.ErrorHandler,
      auth: MyApp.AuthHandler
    }
  end
  
  @impl true
  def url(config) do
    config.url || "wss://default.example.com"
  end
  
  @impl true
  def headers(config) do
    base_headers = super(config)  # Get default headers
    
    if config[:auth_token] do
      [{"Authorization", "Bearer #{config.auth_token}"} | base_headers]
    else
      base_headers
    end
  end
  
  # child_spec, init, and options now have defaults!
end
```

### Step 3: Migrate Advanced Features

```elixir
# If you had complex initialization
defmodule MyApp.AdvancedAdapter do
  use WebsockexNova.Adapter
  
  # Override only specific lifecycle hooks
  @impl true
  def init(config) do
    # Perform custom initialization
    setup_monitoring()
    configure_ssl(config)
    
    # Call parent implementation
    super(config)
  end
  
  @impl true
  def terminate(reason, state) do
    # Custom cleanup
    cleanup_monitoring()
    
    # Call parent implementation
    super(reason, state)
  end
  
  defp setup_monitoring do
    # Custom monitoring logic
  end
  
  defp cleanup_monitoring do
    # Custom cleanup logic
  end
end
```

## Behavior Migration

### Step 1: Identify Custom Behaviors

```elixir
# Old behavior implementation
defmodule MyApp.OldMessageHandler do
  @behaviour WebsockexNova.Behaviors.MessageHandler
  
  def handle_text_frame(text, state) do
    case Jason.decode(text) do
      {:ok, message} ->
        process_message(message, state)
      {:error, error} ->
        {:error, {:json_decode_error, error}}
    end
  end
  
  def handle_binary_frame(binary, state) do
    # Custom binary handling
    {:ok, state}
  end
  
  defp process_message(%{"type" => type} = message, state) do
    case type do
      "ping" -> handle_ping(message, state)
      "data" -> handle_data(message, state)
      "error" -> handle_error_message(message, state)
      _ -> {:ok, state}
    end
  end
  
  # ... more implementation
end
```

### Step 2: Use Composition

```elixir
# New behavior using defaults
defmodule MyApp.NewMessageHandler do
  use WebsockexNova.Defaults.MessageHandler
  
  # Only override what you need to customize
  @impl true
  def handle_text_frame(text, state) do
    case Jason.decode(text) do
      {:ok, message} ->
        process_message(message, state)
      {:error, _error} ->
        # Use default error handling
        super(text, state)
    end
  end
  
  # Binary frame handling inherits default
  
  defp process_message(%{"type" => type} = message, state) do
    case type do
      "ping" -> handle_ping(message, state)
      "data" -> handle_data(message, state)
      "error" -> handle_error_message(message, state)
      _ -> {:ok, state}
    end
  end
  
  # ... rest remains the same
end
```

### Step 3: Use Behavior Macros

```elixir
# Create reusable behavior macros
defmodule MyApp.MessageHandlerMacro do
  defmacro __using__(opts) do
    quote do
      use WebsockexNova.Defaults.MessageHandler
      
      @json_decoder unquote(opts[:json_decoder] || Jason)
      
      @impl true
      def handle_text_frame(text, state) do
        case @json_decoder.decode(text) do
          {:ok, message} ->
            route_message(message, state)
          {:error, _} ->
            {:error, :invalid_json}
        end
      end
      
      # Must be implemented by using module
      @callback route_message(message :: map(), state :: map()) ::
        {:ok, map()} | {:error, term()}
      
      defoverridable handle_text_frame: 2
    end
  end
end

# Use the macro
defmodule MyApp.CustomHandler do
  use MyApp.MessageHandlerMacro, json_decoder: Jason
  
  @impl true
  def route_message(%{"type" => type} = msg, state) do
    # Custom routing logic
  end
end
```

## Testing Migration

### Step 1: Update Test Structure

```elixir
# Old test structure
defmodule MyApp.OldClientTest do
  use ExUnit.Case
  alias MyApp.OldClient
  
  setup do
    # Manual setup
    {:ok, conn} = OldClient.connect(%{url: "ws://localhost:4000"})
    
    on_exit(fn ->
      # Manual cleanup
      GenServer.stop(conn.pid)
    end)
    
    {:ok, conn: conn}
  end
  
  test "sends message", %{conn: conn} do
    assert {:ok, _} = OldClient.send_message(conn, %{test: true})
  end
end
```

### Step 2: Use Macro Test Helpers

```elixir
# New test structure
defmodule MyApp.NewClientTest do
  use ExUnit.Case
  use WebsockexNova.TestHelper  # Provides test utilities
  
  setup do
    # Use test helpers
    {:ok, conn} = start_test_client(MyApp.NewClient)
    {:ok, conn: conn}
  end
  
  test "sends message", %{conn: conn} do
    assert {:ok, _} = MyApp.NewClient.send_message(conn, %{test: true})
    
    # Test helpers provide assertions
    assert_message_sent(%{test: true})
  end
end
```

### Step 3: Migrate Mocks

```elixir
# Old mock setup
defmodule MyApp.MockSetup do
  def setup_mocks do
    # Manual mock configuration
    expect(MockWebSocket, :connect, fn _, _ ->
      {:ok, %{pid: self()}}
    end)
    
    expect(MockWebSocket, :send, fn _, _ ->
      :ok
    end)
  end
end

# New mock setup using macros
defmodule MyApp.NewMockSetup do
  use WebsockexNova.MockHelper
  
  setup_mock_adapter MyApp.TestAdapter do
    on_connect do
      {:ok, %{connected: true}}
    end
    
    on_send do
      :ok
    end
  end
end
```

## Incremental Migration

### Phase 1: Add Macro Wrapper

```elixir
# Keep old implementation working
defmodule MyApp.TransitionalClient do
  use WebsockexNova.ClientMacro, adapter: MyApp.OldAdapter
  
  # Delegate to old implementation during transition
  defdelegate old_connect(opts), to: MyApp.OldClient, as: :connect
  
  # New macro-based implementation
  def connect(opts \\ %{}) do
    # Log usage for monitoring
    Logger.info("Using new connect implementation")
    super(opts)
  end
  
  # Feature flag for gradual rollout
  def smart_connect(opts \\ %{}) do
    if feature_enabled?(:use_macro_client) do
      connect(opts)
    else
      old_connect(opts)
    end
  end
end
```

### Phase 2: Parallel Implementation

```elixir
# Run old and new in parallel for comparison
defmodule MyApp.ParallelClient do
  use WebsockexNova.ClientMacro, adapter: MyApp.NewAdapter
  
  def connect(opts \\ %{}) do
    # Connect using both implementations
    old_result = MyApp.OldClient.connect(opts)
    new_result = super(opts)
    
    # Compare results
    compare_results(old_result, new_result)
    
    # Return new implementation result
    new_result
  end
  
  defp compare_results({:ok, old_conn}, {:ok, new_conn}) do
    # Log any differences for analysis
    if old_conn.state != new_conn.state do
      Logger.warn("State mismatch in connection")
    end
  end
end
```

### Phase 3: Complete Migration

```elixir
# Final implementation
defmodule MyApp.Client do
  use WebsockexNova.ClientMacro, adapter: MyApp.Adapter
  
  # All old custom methods migrated
  def place_order(conn, order) do
    send_json(conn, build_order_message(order))
  end
  
  def subscribe_to_markets(conn, markets) do
    Enum.each(markets, &subscribe(conn, "market.#{&1}"))
  end
  
  # Old implementation completely removed
end
```

## Common Patterns

### Pattern: Configuration Migration

```elixir
# Old configuration
defmodule MyApp.OldConfig do
  def get_config do
    %{
      adapter: MyApp.OldAdapter,
      url: System.get_env("WS_URL"),
      options: build_options()
    }
  end
  
  defp build_options do
    %{
      heartbeat: 30_000,
      reconnect: true
    }
  end
end

# New configuration
defmodule MyApp.NewConfig do
  use WebsockexNova.ConfigHelper
  
  # Use macro helpers
  config :adapter, MyApp.NewAdapter
  config :url, from_env: "WS_URL"
  
  config :options do
    %{
      heartbeat: 30_000,
      reconnect: true
    }
  end
end
```

### Pattern: Behavior Consolidation

```elixir
# Multiple old behaviors
defmodule MyApp.OldAuth do
  @behaviour WebsockexNova.Behaviors.AuthHandler
  # Implementation
end

defmodule MyApp.OldError do
  @behaviour WebsockexNova.Behaviors.ErrorHandler
  # Implementation
end

# Consolidated new behavior
defmodule MyApp.CombinedHandler do
  use WebsockexNova.Defaults.AuthHandler
  use WebsockexNova.Defaults.ErrorHandler
  
  # Override specific methods
  @impl WebsockexNova.Behaviors.AuthHandler
  def handle_auth(state, credentials) do
    # Custom auth logic
    super(state, credentials)
  end
end
```

### Pattern: Testing Migration

```elixir
# Old test pattern
defmodule OldTest do
  use ExUnit.Case
  
  test "manual websocket test" do
    # Lots of setup code
    {:ok, server} = MockServer.start()
    {:ok, conn} = MyApp.OldClient.connect()
    # Test code
    MockServer.stop(server)
  end
end

# New test pattern
defmodule NewTest do
  use WebsockexNova.TestCase  # Includes all helpers
  
  test "websocket test with helpers" do
    with_mock_server do
      {:ok, conn} = MyApp.NewClient.connect()
      # Test code with built-in assertions
      assert_connected(conn)
      assert_message_received(%{type: "welcome"})
    end
  end
end
```

## Troubleshooting Migration

### Issue: Behavior Conflicts

```elixir
# Problem: Multiple behaviors defining same callback
defmodule ConflictingBehaviors do
  use BehaviorA  # Defines handle_message/2
  use BehaviorB  # Also defines handle_message/2
  
  # Which implementation is used?
end

# Solution: Explicit implementation
defmodule ResolvedBehaviors do
  use BehaviorA
  use BehaviorB
  
  # Explicitly choose which to use
  @impl BehaviorA
  def handle_message(msg, state) do
    # This implementation wins
  end
  
  # Or delegate to both
  def handle_message(msg, state) do
    with {:ok, state} <- BehaviorA.handle_message(msg, state),
         {:ok, state} <- BehaviorB.handle_message(msg, state) do
      {:ok, state}
    end
  end
end
```

### Issue: Missing Functionality

```elixir
# Problem: Macro doesn't include a method you need
defmodule MissingMethod do
  use WebsockexNova.ClientMacro, adapter: MyAdapter
  
  # Need custom method not in macro
  def custom_operation(conn, params) do
    # How to implement?
  end
end

# Solution: Use the underlying client
defmodule CompleteClient do
  use WebsockexNova.ClientMacro, adapter: MyAdapter
  alias WebsockexNova.Client
  
  def custom_operation(conn, params) do
    # Use Client directly for non-standard operations
    Client.call(conn, {:custom_op, params})
  end
  
  # Or extend the macro functionality
  def send_custom_frame(conn, frame) do
    Client.send_frame(conn, frame)
  end
end
```

### Issue: State Management Changes

```elixir
# Problem: State structure changed
defmodule StateConverter do
  # Convert old state format to new
  def migrate_state(old_state) do
    %{
      # Map old fields to new structure
      connection_id: old_state.conn_id,
      status: map_status(old_state.status),
      metadata: %{
        created_at: old_state.created,
        updated_at: DateTime.utc_now()
      }
    }
  end
  
  defp map_status(:connected), do: :active
  defp map_status(:disconnected), do: :inactive
  defp map_status(status), do: status
end

# Use in migration
defmodule MigratingHandler do
  use WebsockexNova.Defaults.MessageHandler
  
  @impl true
  def handle_text_frame(text, state) do
    # Check if state needs migration
    new_state = if old_format?(state) do
      StateConverter.migrate_state(state)
    else
      state
    end
    
    # Continue with new state format
    super(text, new_state)
  end
  
  defp old_format?(state) do
    Map.has_key?(state, :conn_id)  # Old field name
  end
end
```

## Best Practices

1. **Test During Migration**: Maintain test coverage throughout
2. **Incremental Changes**: Migrate one component at a time
3. **Maintain Compatibility**: Keep APIs stable during transition
4. **Monitor Performance**: Compare metrics before/after
5. **Document Changes**: Keep clear migration notes
6. **Use Feature Flags**: Control rollout of new implementation
7. **Backup Strategy**: Have rollback plan ready
8. **Parallel Running**: Run old/new side by side initially

## Checklist

- [ ] Inventory current implementation
- [ ] Identify components to migrate
- [ ] Create migration plan
- [ ] Set up parallel implementations
- [ ] Migrate clients to macros
- [ ] Migrate adapters to macros
- [ ] Update behavior implementations
- [ ] Migrate test suite
- [ ] Update documentation
- [ ] Performance testing
- [ ] Gradual rollout
- [ ] Monitor for issues
- [ ] Remove old implementation
- [ ] Final cleanup

## Next Steps

After migration:
1. Review [Advanced Macros Guide](advanced_macros.md)
2. Explore [Behavior Composition](behavior_composition.md)
3. Optimize with [Performance Tuning](performance_tuning.md)