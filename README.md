# WebsockexNew

Simple, robust WebSocket client for Elixir using Gun transport layer.

WebsockexNew is a simplified WebSocket client library focused on clarity and reliability. It provides a clean 5-function interface for WebSocket operations with platform-specific adapters for customization.

## Features

- **Simple Interface**: 5 core functions - connect, send_message, close, subscribe, get_state
- **Gun Transport**: Battle-tested WebSocket transport layer
- **Adapter Pattern**: Platform-specific customization through adapters
- **Error Resilience**: Automatic reconnection with subscription preservation
- **Real Endpoint Testing**: Integration tests use actual WebSocket APIs

## Architecture

WebsockexNew consists of 8 core modules:

```
WebsockexNew.Client         # Core client interface (5 functions)
WebsockexNew.Config         # Configuration management  
WebsockexNew.MessageHandler # Message processing
WebsockexNew.Reconnection   # Connection recovery
WebsockexNew.ConnectionRegistry # Connection tracking
WebsockexNew.ErrorHandler  # Error processing
WebsockexNew.Frame          # Frame handling
WebsockexNew.Examples.DeribitAdapter # Example adapter
```

## Installation

Add `websockex_new` to your dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:websockex_new, "~> 0.1.0"}
  ]
end
```

## Quick Start

### Basic Usage

```elixir
# Connect to WebSocket endpoint
{:ok, client} = WebsockexNew.Client.connect("wss://api.example.com/ws")

# Send a message
:ok = WebsockexNew.Client.send_message(client, "Hello, WebSocket!")

# Subscribe to channels
:ok = WebsockexNew.Client.subscribe(client, ["channel1", "channel2"])

# Check connection state
:connected = WebsockexNew.Client.get_state(client)

# Close connection
:ok = WebsockexNew.Client.close(client)
```

### Configuration

```elixir
# Simple URL connection
{:ok, client} = WebsockexNew.Client.connect("wss://api.example.com/ws")

# With configuration options
config = WebsockexNew.Config.new!("wss://api.example.com/ws", 
  timeout: 10_000,
  retry_count: 5,
  headers: [{"Authorization", "Bearer token"}]
)
{:ok, client} = WebsockexNew.Client.connect(config)
```

## Platform Adapters

Use adapters for platform-specific functionality:

### Deribit Example

```elixir
# Connect to Deribit test environment
{:ok, adapter} = WebsockexNew.Examples.DeribitAdapter.connect()

# Authenticate with credentials
{:ok, adapter} = WebsockexNew.Examples.DeribitAdapter.authenticate(adapter)

# Subscribe to market data
{:ok, adapter} = WebsockexNew.Examples.DeribitAdapter.subscribe(adapter, [
  "ticker.BTC-USD",
  "trades.ETH-USD"
])

# Handle platform-specific messages
handler = WebsockexNew.Examples.DeribitAdapter.create_message_handler(
  on_message: fn frame -> process_market_data(frame) end,
  on_heartbeat: fn response -> send_heartbeat(response) end
)
```

### Creating Custom Adapters

```elixir
defmodule MyPlatform.Adapter do
  defstruct [:client, :authenticated, :subscriptions, :api_key]
  
  def connect(opts \\ []) do
    case WebsockexNew.Client.connect("wss://api.myplatform.com/ws") do
      {:ok, client} ->
        adapter = %__MODULE__{
          client: client,
          authenticated: false,
          subscriptions: MapSet.new(),
          api_key: Keyword.get(opts, :api_key)
        }
        {:ok, adapter}
        
      error -> error
    end
  end
  
  def authenticate(%__MODULE__{client: client, api_key: api_key} = adapter) do
    auth_message = Jason.encode!(%{type: "auth", api_key: api_key})
    
    case WebsockexNew.Client.send_message(client, auth_message) do
      :ok -> {:ok, %{adapter | authenticated: true}}
      error -> error
    end
  end
end
```

## Core API

### WebsockexNew.Client

The main client interface provides 5 essential functions:

```elixir
# Establish WebSocket connection
@spec connect(String.t() | Config.t(), keyword()) :: {:ok, t()} | {:error, term()}

# Send text messages
@spec send_message(t(), binary()) :: :ok | {:error, term()}

# Close connection gracefully  
@spec close(t()) :: :ok

# Subscribe to channels/topics
@spec subscribe(t(), list()) :: :ok | {:error, term()}

# Get current connection state
@spec get_state(t()) :: :connecting | :connected | :disconnected
```

### Configuration Options

```elixir
WebsockexNew.Config.new(url, [
  headers: [],              # HTTP headers for upgrade
  timeout: 5_000,           # Connection timeout (ms)
  retry_count: 3,           # Reconnection attempts
  retry_delay: 1_000,       # Delay between retries (ms)
  heartbeat_interval: 30_000 # Heartbeat frequency (ms)
])
```

## Error Handling

WebsockexNew categorizes errors for appropriate recovery:

### Recoverable Errors (Auto-reconnect)
- Network failures: `:econnrefused`, `:timeout`, `:nxdomain`
- Connection issues: `:ehostunreach`, `:enetunreach`
- Transport errors: `{:tls_alert, _}`, `{:gun_down, _, _, _, _}`

### Fatal Errors (No reconnect)
- Protocol errors: `:invalid_frame`, `:frame_too_large`
- Authentication: `:unauthorized`, `:invalid_credentials`

```elixir
case WebsockexNew.Client.connect("wss://api.example.com/ws") do
  {:ok, client} -> 
    # Connected successfully
    client
    
  {:error, {:recoverable, reason}} ->
    # Network error - can retry
    handle_recoverable_error(reason)
    
  {:error, reason} ->
    # Fatal error - don't retry
    handle_fatal_error(reason)
end
```

## Testing

WebsockexNew follows a "Real Endpoint First" testing philosophy:

```bash
# Run all tests
mix test

# Run integration tests against real endpoints
mix test --only integration

# Run with real API credentials
DERIBIT_CLIENT_ID=your_id DERIBIT_CLIENT_SECRET=your_secret mix test
```

For integration testing with Deribit:
```bash
export DERIBIT_CLIENT_ID="your_test_client_id"
export DERIBIT_CLIENT_SECRET="your_test_client_secret"
mix test
```

## Development Commands

```bash
# Install dependencies
mix deps.get

# Run tests with coverage
mix coverage

# Run linter (Credo)
mix lint

# Run type checker (Dialyzer)  
mix dialyzer

# Run all quality checks
mix check

# Format code
mix format

# Generate documentation
mix docs
```

## Documentation

Comprehensive documentation is available:

- **[Architecture Overview](docs/architecture.md)** - System design and components
- **[API Reference](docs/api.md)** - Complete function documentation
- **[Adapter Development](docs/adapter_guide.md)** - Creating platform adapters
- **[Integration Testing](docs/integration_testing.md)** - Testing with real endpoints

## Examples

The `WebsockexNew.Examples.DeribitAdapter` demonstrates:
- Connection establishment
- Authentication flows
- Subscription management
- Message handling
- Heartbeat responses
- Error processing

## Design Goals

1. **Simplicity**: 8 modules vs 56 in previous implementations
2. **Clarity**: Clean interfaces with obvious functionality
3. **Reliability**: Gun-based transport with proven stability
4. **Extensibility**: Adapter pattern for platform customization
5. **Real-world Testing**: Integration tests use actual endpoints

## License

MIT License - see LICENSE file for details.

## Contributing

1. Fork the repository
2. Create a feature branch
3. Write tests (preferably integration tests with real endpoints)
4. Run `mix check` to validate code quality
5. Submit a pull request

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for version history and updates.