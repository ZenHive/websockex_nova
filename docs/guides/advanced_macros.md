# Advanced Macro Usage Guide

This guide covers advanced patterns and techniques for using the WebsockexNova macro system effectively.

## Table of Contents
1. [Macro Composition Patterns](#macro-composition-patterns)
2. [Conditional Compilation](#conditional-compilation)
3. [Dynamic Behavior Selection](#dynamic-behavior-selection)
4. [Testing Macro-Based Code](#testing-macro-based-code)
5. [Performance Optimization](#performance-optimization)
6. [Common Pitfalls](#common-pitfalls)

## Macro Composition Patterns

### Layered Client Architecture

Create multiple levels of abstraction using composed macros:

```elixir
defmodule MyApp.BaseTraderClient do
  defmacro __using__(opts) do
    quote do
      use WebsockexNova.ClientMacro, unquote(opts)
      
      # Common trading functionality
      def execute_trade(conn, order_params) do
        with {:ok, validated_params} <- validate_order(order_params),
             {:ok, risk_approved} <- check_risk_limits(validated_params),
             {:ok, result} <- send_order(conn, risk_approved) do
          {:ok, result}
        end
      end
      
      defp validate_order(params) do
        # Implementation specific to trader
        {:ok, params}
      end
      
      # Must be implemented by using module
      @callback check_risk_limits(map()) :: {:ok, map()} | {:error, term()}
      @callback send_order(ClientConn.t(), map()) :: {:ok, term()} | {:error, term()}
    end
  end
end

defmodule MyApp.EquityTrader do
  use MyApp.BaseTraderClient, adapter: MyApp.EquityAdapter
  
  @impl true
  def check_risk_limits(params) do
    # Equity-specific risk checks
    if params.shares * params.price <= 100_000 do
      {:ok, params}
    else
      {:error, :position_too_large}
    end
  end
  
  @impl true
  def send_order(conn, params) do
    send_json(conn, %{
      action: "execute_equity_order",
      order: params
    })
  end
end
```

### Multi-Adapter Support

Create clients that can switch between adapters dynamically:

```elixir
defmodule MyApp.MultiExchangeClient do
  use WebsockexNova.ClientMacro, adapter: :dynamic
  
  # Override the adapter resolution
  defp resolve_adapter(opts) do
    case opts[:exchange] do
      :binance -> MyApp.BinanceAdapter
      :coinbase -> MyApp.CoinbaseAdapter
      :kraken -> MyApp.KrakenAdapter
      _ -> raise ArgumentError, "Unknown exchange: #{inspect(opts[:exchange])}"
    end
  end
  
  def connect(opts \\ %{}) do
    adapter = resolve_adapter(opts)
    WebsockexNova.Client.connect(adapter, Map.delete(opts, :exchange))
  end
  
  # Universal order placement that works across exchanges
  def place_order(conn, params) do
    normalized_params = normalize_order_params(conn.adapter, params)
    send_json(conn, normalized_params)
  end
  
  defp normalize_order_params(MyApp.BinanceAdapter, params) do
    %{
      symbol: params.pair,
      side: String.upcase(to_string(params.side)),
      type: "LIMIT",
      quantity: params.amount,
      price: params.price
    }
  end
  
  defp normalize_order_params(MyApp.CoinbaseAdapter, params) do
    %{
      product_id: params.pair,
      side: params.side,
      order_type: "limit",
      size: params.amount,
      price: params.price
    }
  end
end
```

## Conditional Compilation

### Environment-Specific Features

Use compile-time configuration to include/exclude features:

```elixir
defmodule MyApp.ConfigurableClient do
  use WebsockexNova.ClientMacro, adapter: MyApp.ProductionAdapter
  
  # Only include debug features in dev/test environments
  if Mix.env() in [:dev, :test] do
    def debug_state(conn) do
      {:ok, state} = get_internal_state(conn)
      IO.inspect(state, label: "Connection State")
    end
    
    def simulate_disconnect(conn) do
      send(conn.transport_pid, :force_disconnect)
    end
  end
  
  # Include performance monitoring only in production
  if Mix.env() == :prod do
    def __after_compile__(env, _bytecode) do
      # Set up performance monitoring
      :telemetry.attach_many(
        "#{env.module}-perf",
        [
          [:websockex_nova, :message, :sent],
          [:websockex_nova, :message, :received]
        ],
        &__MODULE__.handle_telemetry_event/4,
        %{}
      )
    end
    
    def handle_telemetry_event(event, measurements, metadata, _config) do
      # Send to monitoring service
      Metrics.record(event, measurements, metadata)
    end
  end
end
```

### Feature Flags

Implement feature flags through macro options:

```elixir
defmodule MyApp.FeatureFlagClient do
  defmacro __using__(opts) do
    features = Keyword.get(opts, :features, [])
    
    quote do
      use WebsockexNova.ClientMacro, adapter: unquote(opts[:adapter])
      
      # Conditionally include rate limiting
      if :rate_limiting in unquote(features) do
        @rate_limiter RateLimiter.new(100, :second)
        
        def send_json(conn, payload, opts \\ nil) do
          case RateLimiter.check_rate(@rate_limiter) do
            :ok -> super(conn, payload, opts)
            {:error, :rate_limited} -> {:error, :rate_limited}
          end
        end
      end
      
      # Conditionally include caching
      if :caching in unquote(features) do
        @cache_ttl :timer.seconds(60)
        
        def get_cached_data(conn, key) do
          case Cache.get(key) do
            nil ->
              result = fetch_data(conn, key)
              Cache.put(key, result, @cache_ttl)
              result
            cached ->
              cached
          end
        end
      end
    end
  end
end

# Usage
defmodule MyApp.FullFeatureClient do
  use MyApp.FeatureFlagClient,
    adapter: MyApp.Adapter,
    features: [:rate_limiting, :caching]
end
```

## Dynamic Behavior Selection

### Runtime Behavior Switching

Implement strategies that can change behavior at runtime:

```elixir
defmodule MyApp.StrategyClient do
  use WebsockexNova.ClientMacro, adapter: MyApp.StrategyAdapter
  
  defstruct [:conn, :strategy]
  
  # Strategy behavior
  defmodule Strategy do
    @callback handle_price_update(state :: term(), price :: float()) :: 
      {:ok, actions :: list()} | {:noop, state :: term()}
  end
  
  # Different trading strategies
  defmodule MomentumStrategy do
    @behaviour Strategy
    
    def handle_price_update(state, price) do
      if price > state.moving_average * 1.02 do
        {:ok, [{:buy, state.position_size}]}
      else
        {:noop, state}
      end
    end
  end
  
  defmodule MeanReversionStrategy do
    @behaviour Strategy
    
    def handle_price_update(state, price) do
      if price < state.moving_average * 0.98 do
        {:ok, [{:buy, state.position_size}]}
      else
        {:noop, state}
      end
    end
  end
  
  # Client implementation with dynamic strategy
  def set_strategy(client, strategy_module) do
    %{client | strategy: strategy_module}
  end
  
  def handle_market_data(%__MODULE__{} = client, %{"price" => price}) do
    case client.strategy.handle_price_update(client.conn.state, price) do
      {:ok, actions} ->
        Enum.each(actions, &execute_action(client.conn, &1))
      {:noop, _new_state} ->
        :ok
    end
  end
  
  defp execute_action(conn, {:buy, amount}) do
    send_json(conn, %{action: "buy", amount: amount})
  end
end
```

## Testing Macro-Based Code

### Mocking Macro-Generated Functions

Test macro-generated code effectively:

```elixir
defmodule MyApp.TestableClient do
  defmacro __using__(opts) do
    quote do
      use WebsockexNova.ClientMacro, unquote(opts)
      
      # Make internal functions testable
      @doc false
      def __test_helper__(conn, action, params) do
        case action do
          :validate_order -> validate_order(params)
          :check_risk -> check_risk_limits(conn, params)
          _ -> {:error, :unknown_action}
        end
      end
      
      # Private functions that need testing
      defp validate_order(params) do
        # Complex validation logic
        {:ok, params}
      end
      
      defp check_risk_limits(conn, params) do
        # Risk management logic
        {:ok, params}
      end
    end
  end
end

# In tests
defmodule MyApp.TestableClientTest do
  use ExUnit.Case
  
  defmodule TestClient do
    use MyApp.TestableClient, adapter: MockAdapter
  end
  
  test "validates orders correctly" do
    conn = %ClientConn{adapter: MockAdapter}
    params = %{price: 100, quantity: 10}
    
    assert {:ok, ^params} = TestClient.__test_helper__(conn, :validate_order, params)
  end
end
```

### Compile-Time Testing

Test macro expansion itself:

```elixir
defmodule MacroExpansionTest do
  use ExUnit.Case
  
  test "client macro generates expected functions" do
    defmodule CompileTimeTest do
      use WebsockexNova.ClientMacro, adapter: TestAdapter
    end
    
    # Verify generated functions exist
    assert function_exported?(CompileTimeTest, :connect, 1)
    assert function_exported?(CompileTimeTest, :send_json, 3)
    assert function_exported?(CompileTimeTest, :subscribe, 3)
  end
  
  test "macro with custom options generates overrides" do
    defmodule CustomOptionsTest do
      use WebsockexNova.ClientMacro,
        adapter: TestAdapter,
        default_options: %{custom: true}
        
      def default_opts, do: %{custom: true, extra: 123}
    end
    
    assert CustomOptionsTest.default_opts() == %{custom: true, extra: 123}
  end
end
```

## Performance Optimization

### Compile-Time Optimization

Optimize macro expansion for better performance:

```elixir
defmodule MyApp.OptimizedClient do
  defmacro __using__(opts) do
    # Pre-compute values at compile time
    adapter = Keyword.fetch!(opts, :adapter)
    handler_mappings = build_handler_mappings(adapter)
    
    quote do
      use WebsockexNova.ClientMacro, adapter: unquote(adapter)
      
      # Use compile-time computed mappings
      @handler_mappings unquote(Macro.escape(handler_mappings))
      
      # Inline small functions for performance
      @compile {:inline, [
        handle_response: 2,
        validate_params: 1,
        build_request: 2
      ]}
      
      defp handle_response(response, handler_key) do
        handler = @handler_mappings[handler_key]
        handler.handle(response)
      end
    end
  end
  
  defp build_handler_mappings(adapter) do
    # Build mappings at compile time
    %{
      order_response: adapter.order_handler(),
      market_data: adapter.market_data_handler()
    }
  end
end
```

### Memory-Efficient Patterns

Use ETS for shared state in macro-based clients:

```elixir
defmodule MyApp.EfficientClient do
  use WebsockexNova.ClientMacro, adapter: MyApp.EfficientAdapter
  
  @table_name :client_shared_state
  
  def init_shared_state do
    :ets.new(@table_name, [:named_table, :public, :set])
  end
  
  def store_subscription(conn, channel, subscription_id) do
    key = {conn.id, channel}
    :ets.insert(@table_name, {key, subscription_id})
  end
  
  def get_subscription(conn, channel) do
    key = {conn.id, channel}
    case :ets.lookup(@table_name, key) do
      [{^key, subscription_id}] -> {:ok, subscription_id}
      [] -> {:error, :not_found}
    end
  end
  
  # Use match specs for efficient queries
  def get_all_subscriptions(conn) do
    match_spec = [{{conn.id, :"$1"}, :"$2"}, [], [{{:"$1", :"$2"}}]}]
    :ets.select(@table_name, match_spec)
  end
end
```

## Common Pitfalls

### Macro Hygiene Issues

Avoid variable capture and namespace pollution:

```elixir
# BAD: Variables can leak
defmacro bad_macro do
  quote do
    conn = get_connection()  # This 'conn' might conflict!
    send_data(conn, data)
  end
end

# GOOD: Use unique variable names
defmacro good_macro do
  quote do
    var!(ws_conn, __MODULE__) = get_connection()
    send_data(var!(ws_conn, __MODULE__), var!(data, __MODULE__))
  end
end

# BETTER: Use hygienic variables
defmacro better_macro do
  quote do
    conn = unquote(quote do: get_connection())
    send_data(conn, unquote(quote do: data))
  end
end
```

### Compile-Time Dependencies

Handle module dependencies correctly:

```elixir
defmodule MyApp.DependentClient do
  # Ensure dependent modules are compiled first
  require MyApp.SharedBehaviors
  require MyApp.CommonValidations
  
  use WebsockexNova.ClientMacro, adapter: MyApp.Adapter
  
  # Import shared functionality
  import MyApp.CommonValidations, only: [validate_order: 1]
  
  def place_order(conn, params) do
    with {:ok, validated} <- validate_order(params) do
      send_json(conn, %{action: "place_order", order: validated})
    end
  end
end
```

### Debugging Macro Expansions

Debug complex macro expansions:

```elixir
defmodule MyApp.DebuggableClient do
  # Use this to see macro expansion
  require WebsockexNova.ClientMacro
  
  # Uncomment to debug macro expansion
  # IO.puts(Macro.to_string(
  #   quote do
  #     use WebsockexNova.ClientMacro, adapter: MyApp.Adapter
  #   end
  #   |> Macro.expand(__ENV__)
  # ))
  
  use WebsockexNova.ClientMacro, adapter: MyApp.Adapter
  
  # Add debug helper
  defmacro debug_expansion(ast) do
    expanded = Macro.expand(ast, __CALLER__)
    IO.puts("Original: #{Macro.to_string(ast)}")
    IO.puts("Expanded: #{Macro.to_string(expanded)}")
    expanded
  end
end
```

## Best Practices

1. **Keep Macros Simple**: Complex logic should be in regular functions
2. **Document Generated Functions**: Use `@doc` attributes in macros
3. **Provide Escape Hatches**: Allow overriding generated functions
4. **Test at Multiple Levels**: Test both macro expansion and runtime behavior
5. **Use Compile-Time Checks**: Validate options during compilation
6. **Avoid Runtime Overhead**: Move computation to compile time when possible
7. **Maintain Backwards Compatibility**: Version your macro APIs

## Next Steps

- Explore [Behavior Composition Patterns](behavior_composition.md)
- Learn about [Testing Custom Behaviors](testing_behaviors.md)
- Review [Architectural Patterns](architectural_patterns.md)