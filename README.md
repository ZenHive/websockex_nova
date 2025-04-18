# WebsockexNova

WebsockexNova is a robust WebSocket client for Elixir, built on top of the [Gun](https://github.com/ninenines/gun) HTTP client. It provides a behavior-based architecture for easy customization and platform-specific integrations, while handling the complexities of WebSocket connections for you.

## Features

- **Behavior-Based Architecture**: Extensible through well-defined behavior interfaces
- **Robust Connection Management**: Sophisticated connection lifecycle with automatic reconnection
- **Gun Integration**: Built on the battle-tested Gun HTTP/WebSocket client
- **Reliable Process Monitoring**: Uses Erlang process monitors for robust connection tracking
- **Flexible Error Handling**: Customizable error recovery strategies
- **Ownership Transfer Support**: Reliably transfer connection ownership between processes
- **Platform-Specific Integrations**: Ready-to-use adapters for common platforms

## Installation

Add `websockex_nova` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:websockex_nova, "~> 0.1.0"}
  ]
end
```

## Basic Usage

```elixir
# Create a simple WebSocket client
defmodule MyApp.SimpleClient do
  use WebsockexNova.Client

  # Implement required callbacks
  def handle_connect(_conn, state) do
    IO.puts "Connected to WebSocket server!"
    {:ok, state}
  end

  def handle_frame({:text, message}, _conn, state) do
    IO.puts "Received message: #{message}"
    {:ok, state}
  end

  def handle_disconnect(reason, state) do
    IO.puts "Disconnected: #{inspect(reason)}"
    {:reconnect, state}
  end
end

# Connect to a WebSocket server
{:ok, client} = MyApp.SimpleClient.start_link("wss://echo.websocket.org")

# Send a message
MyApp.SimpleClient.send_frame(client, {:text, "Hello WebSocket!"})
```

## Development

This project uses several code quality tools to maintain high standards:

### Static Analysis

- **Dialyzer**: Detects type inconsistencies and potential bugs

  ```
  mix dialyzer
  ```

- **Credo**: Enforces code style and best practices

  ```
  mix credo
  ```

- **Sobelow**: Identifies security vulnerabilities
  ```
  mix sobelow
  ```

### Documentation

- **ExDoc**: Generates documentation from code comments
  ```
  mix docs
  ```

PLT files for Dialyzer are stored in `priv/plts` and are gitignored. When setting up the project for the first time, you'll need to generate them:

```
mkdir -p priv/plts
mix dialyzer
```

## Architecture

WebsockexNova uses a behavior-based architecture for flexibility:

- **ConnectionHandler**: Defines connection lifecycle callbacks
- **MessageHandler**: Handles message processing and routing
- **ErrorHandler**: Manages error recovery strategies

Under the hood, WebsockexNova uses Gun as its transport layer with enhanced reliability:

- **Process Monitoring**: Uses Erlang process monitors instead of links for greater resilience
- **Explicit Monitor References**: Passes monitor references to Gun's await functions to prevent deadlocks
- **Ownership Transfer**: Provides a robust mechanism for transferring connection ownership between processes

## Documentation

For more information, see:

- [Architecture Overview](docs/architecture.md)
- [Gun Integration Guide](docs/guides/gun_integration.md)
- [API Reference](https://hexdocs.pm/websockex_nova)

## Deployment Profiles

WebsockexNova supports different deployment profiles:

- **Financial Profile**: For high-frequency trading and financial applications
- **Standard Profile**: For general-purpose WebSocket applications
- **Lightweight Profile**: For simple WebSocket integrations
- **Chat/Messaging Profile**: Optimized for interactive messaging platforms

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
