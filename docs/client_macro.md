# ClientMacro

The `WebsockexNova.ClientMacro` provides a way to quickly build specialized WebSocket clients with minimal boilerplate code. Similar to the `WebsockexNova.Adapter` macro, it standardizes common functionality while enabling customizations specific to your WebSocket API.

## Benefits

- **Reduced Boilerplate**: Automatically includes the standard client methods (connect, authenticate, subscribe, etc.)
- **Adapter Integration**: Directly ties your client to your adapter
- **Standardization**: Ensures consistent API across different client implementations
- **Focus**: Let developers focus on domain-specific methods rather than plumbing code

## Usage

### Basic Example

```elixir
defmodule MyApp.MyClient do
  use WebsockexNova.ClientMacro, adapter: MyApp.MyAdapter

  # Add domain-specific methods:
  def subscribe_to_portfolio(conn, account_id, opts \\ nil) do
    channel = "portfolio.#{account_id}.updates"
    subscribe(conn, channel, opts)
  end
end
```

### With Custom Default Options

```elixir
defmodule MyApp.MyClient do
  use WebsockexNova.ClientMacro, adapter: MyApp.MyAdapter

  # Override default options
  defp default_opts do
    %{
      host: "api.example.com",
      port: 443,
      log_level: :debug
    }
  end

  # Your custom methods...
end
```

### Complete Example

```elixir
defmodule MyApp.MyClient do
  use WebsockexNova.ClientMacro, adapter: MyApp.MyAdapter

  @doc """
  Subscribe to market data updates for a specific symbol.
  """
  def subscribe_to_market_data(conn, symbol, opts \\ nil) do
    channel = "market.#{symbol}.tickers"
    subscribe(conn, channel, opts)
  end

  @doc """
  Place a limit order.
  """
  def place_limit_order(conn, params, opts \\ nil) do
    %{symbol: symbol, side: side, price: price, quantity: quantity} = params

    payload = %{
      type: "order",
      subtype: "limit",
      symbol: symbol,
      side: side,
      price: price,
      quantity: quantity
    }

    send_json(conn, payload, opts)
  end

  @doc """
  Cancel an order.
  """
  def cancel_order(conn, order_id, opts \\ nil) do
    payload = %{
      type: "cancel_order",
      order_id: order_id
    }

    send_json(conn, payload, opts)
  end
end
```

## Included Methods

The ClientMacro automatically provides the following methods:

- `connect(opts \\ %{})`
- `authenticate(conn, credentials \\ %{}, opts \\ nil)`
- `subscribe(conn, channel, opts \\ nil)`
- `unsubscribe(conn, channel, opts \\ nil)`
- `send_json(conn, payload, opts \\ nil)`
- `send_text(conn, text, opts \\ nil)`
- `ping(conn, opts \\ nil)`
- `status(conn, opts \\ nil)`
- `close(conn)`

## Implementation Details

Under the hood, the ClientMacro delegates to the underlying `WebsockexNova.Client` module, which in turn delegates to the specified adapter. The macro ensures your client implementation:

1. Uses the appropriate adapter for connection and communication
2. Includes all standard WebSocket operations
3. Applies sensible defaults from your adapter
4. Allows overriding defaults via client-specific logic
