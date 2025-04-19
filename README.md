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

## Telemetry & Metrics

WebsockexNova emits rich [Telemetry](https://hexdocs.pm/telemetry/telemetry.html) events for all connection, message, and error activities. This enables real-time observability, metrics collection, and integration with tools like Prometheus, StatsD, or custom dashboards.

### Telemetry Events

| Event Name                                           | Measurements                 | Metadata                                        |
| ---------------------------------------------------- | ---------------------------- | ----------------------------------------------- |
| `[:websockex_nova, :connection, :open]`              | `%{duration}` (ms, optional) | `%{connection_id, host, port}`                  |
| `[:websockex_nova, :connection, :close]`             | `%{duration}` (ms, optional) | `%{connection_id, host, port, reason}`          |
| `[:websockex_nova, :connection, :websocket_upgrade]` | `%{duration}` (ms, optional) | `%{connection_id, stream_ref, headers}`         |
| `[:websockex_nova, :message, :sent]`                 | `%{size, latency}`           | `%{connection_id, stream_ref, frame_type}`      |
| `[:websockex_nova, :message, :received]`             | `%{size, latency}`           | `%{connection_id, stream_ref, frame_type}`      |
| `[:websockex_nova, :error, :occurred]`               | `%{}`                        | `%{connection_id, stream_ref, reason, context}` |

#### Example: Subscribing to Telemetry Events

```elixir
:telemetry.attach(
  "my-websockexnova-listener",
  [:websockex_nova, :message, :sent],
  fn event, measurements, metadata, _config ->
    IO.inspect({event, measurements, metadata}, label: "WebsockexNova Telemetry")
  end,
  nil
)
```

### Metrics Collection

WebsockexNova provides a `MetricsCollector` behavior for aggregating metrics from telemetry events. The default implementation (`WebsockexNova.Defaults.DefaultMetricsCollector`) tracks:

- Connection statistics (open/close counts, durations)
- Message throughput (sent/received count, size, latency)
- Error metrics (count by category)

#### Using the Default Metrics Collector

The default collector is started automatically, but you can also start it manually:

```elixir
WebsockexNova.Defaults.DefaultMetricsCollector.start_link([])

# Query a metric (for demo/testing)
WebsockexNova.Defaults.DefaultMetricsCollector.get_metric(:messages_sent)
```

#### Implementing a Custom Metrics Collector

To implement your own collector, use the `WebsockexNova.Behaviors.MetricsCollector` behavior:

```elixir
defmodule MyApp.CustomCollector do
  @behaviour WebsockexNova.Behaviors.MetricsCollector

  def handle_connection_event(event, measurements, metadata) do
    # Custom logic
    :ok
  end

  def handle_message_event(event, measurements, metadata) do
    # Custom logic
    :ok
  end

  def handle_error_event(event, measurements, metadata) do
    # Custom logic
    :ok
  end
end
```

You can then attach your collector to telemetry events as needed.

For more details, see the [API Reference](https://hexdocs.pm/websockex_nova) and the `WebsockexNova.Telemetry.TelemetryEvents` and `WebsockexNova.Behaviors.MetricsCollector` modules.

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
