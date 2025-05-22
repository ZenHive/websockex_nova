# WebsockexNew

A robust, highly extensible WebSocket client library for Elixir with elegant abstractions for building specialized WebSocket clients.

This library is based on the excellent [Websockex](https://github.com/Azolo/websockex) library by [Azolo](https://github.com/Azolo) and has been heavily extended with additional capabilities including behavior-based extensibility, adapter patterns, Gun transport integration, automatic reconnection, subscription management, rate limiting, and more.

## Features

- **Behavior-Based Architecture**: Easily extendable through behavior interfaces
- **Adapter Pattern**: Customize specific aspects of WebSocket communication
- **Default Implementations**: Sensible defaults provided for all behaviors
- **Gun Integration**: Uses the battle-tested Gun library as the transport layer
- **Client Macro**: Simplify creation of service-specific WebSocket clients
- **Adapter Macro**: Build service-specific adapters with minimal boilerplate
- **Rate Limiting**: Built-in rate limiting capabilities
- **Observability**: Rich telemetry and logging support

## Installation

Add `websockex_new` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:websockex_new, "~> 0.1.0"}
  ]
end
```

## Usage

### Basic Usage

```elixir
# Connect to a WebSocket server
{:ok, conn} = WebsockexNew.Client.connect(WebsockexNew.Defaults.DefaultAdapter, %{
  host: "echo.websocket.org",
  port: 443,
  path: "/",
  transport: :tls
})

# Send a message
{:ok, response} = WebsockexNew.Client.send_text(conn, "Hello, WebSocket!")

# Close the connection
WebsockexNew.Client.close(conn)
```

### Using ClientMacro

Create service-specific clients with minimal boilerplate using `WebsockexNew.ClientMacro`:

```elixir
defmodule MyApp.DeribitClient do
  use WebsockexNew.ClientMacro, adapter: MyApp.DeribitAdapter

  # Add domain-specific methods:
  def subscribe_to_trades(conn, instrument, opts \\ nil) do
    channel = "trades.#{instrument}.raw"
    subscribe(conn, channel, opts)
  end

  def subscribe_to_ticker(conn, instrument, opts \\ nil) do
    channel = "ticker.#{instrument}.raw"
    subscribe(conn, channel, opts)
  end
end

# Usage
{:ok, conn} = MyApp.DeribitClient.connect()
{:ok, _} = MyApp.DeribitClient.subscribe_to_trades(conn, "BTC-PERPETUAL")
```

### Using AdapterMacro

Create service-specific adapters with minimal boilerplate using `WebsockexNew.Adapter`:

```elixir
defmodule MyApp.DeribitAdapter do
  use WebsockexNew.Adapter

  # Override only what you need:
  @impl WebsockexNew.Behaviors.ConnectionHandler
  def connection_info(opts) do
    defaults = %{
      host: "www.deribit.com",
      port: 443,
      path: "/ws/api/v2",
      transport: :tls
    }

    {:ok, Map.merge(defaults, opts)}
  end

  @impl WebsockexNew.Behaviors.MessageHandler
  def handle_message(message, state) do
    # Custom message handling...
    {:ok, decoded_message, updated_state}
  end
end
```

## Documentation

Comprehensive documentation is available in the `docs/` directory:

- **Architecture Overview**: `docs/architecture.md`
- **Client Macro Guide**: `docs/client_macro.md`
- **Implementation Plan**: `docs/plan.md`

## License

This project is licensed under the MIT License - see the LICENSE file for details.
