# WebsockexNova Documentation

Welcome to the WebsockexNova documentation. WebsockexNova is a robust WebSocket client library for Elixir with a pluggable adapter architecture.

## Guides

1. [Platform Adapter Implementation Guide](platform_adapter_guide.md) - Learn how to implement adapters for specific WebSocket services
2. [Behavior Customization Guide](behavior_customization_guide.md) - Learn how to customize WebSocket behavior handlers

## Architecture

WebsockexNova employs a "thin adapter" architecture that separates concerns through:

1. **Behavioral Interfaces**: Well-defined behaviors for various aspects of WebSocket handling
2. **Default Implementations**: Ready-to-use default implementations of these behaviors
3. **Platform Adapters**: Thin adapters that bridge to specific platforms/services
4. **Connection Management**: Process-based connection handling with ownership semantics

This modular design allows for maximum flexibility while minimizing boilerplate code.

## Key Components

- **Connection**: The core GenServer process managing the WebSocket lifecycle
- **Client**: A convenient API for interacting with connections
- **Behaviors**: Interfaces for connection, message, authentication, error handling, etc.
- **Defaults**: Ready-to-use implementations of all behaviors
- **Platform Adapters**: Thin adapters for specific WebSocket services

## Getting Started

### Basic Usage

```elixir
# Start a connection to the Echo service
{:ok, conn} = WebsockexNova.Connection.start_link(
  adapter: WebsockexNova.Platform.Echo.Adapter
)

# Send a message and get the response
{:text, response} = WebsockexNova.Client.send_text(conn, "Hello")
```

### Using with Custom Handlers

```elixir
# Start a connection with custom handlers
{:ok, conn} = WebsockexNova.Connection.start_link(
  adapter: WebsockexNova.Platform.Echo.Adapter,
  message_handler: MyApp.MessageHandler,
  connection_handler: MyApp.ConnectionHandler
)
```

## Available Behaviors

WebsockexNova provides the following behavior modules:

- `ConnectionHandler`: Handle connection lifecycle events
- `MessageHandler`: Process incoming WebSocket messages
- `SubscriptionHandler`: Manage channel subscriptions
- `AuthHandler`: Handle authentication
- `ErrorHandler`: Process error scenarios
- `RateLimitHandler`: Implement rate limiting
- `LoggingHandler`: Provide logging functionality
- `MetricsCollector`: Collect metrics about WebSocket operations

Each behavior has a corresponding default implementation in the `WebsockexNova.Defaults` namespace.
