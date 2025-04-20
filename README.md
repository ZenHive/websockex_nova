# WebsockexNova

WebsockexNova is a robust, extensible WebSocket client for Elixir, built on top of the [Gun](https://github.com/ninenines/gun) HTTP client. It provides a behavior-based architecture for easy customization and platform-specific integrations, while handling the complexities of WebSocket connections for you.

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

## Quickstart (Recommended)

The primary, recommended interface for most users is the ergonomic `WebsockexNova.Client` API, which works with any adapter.

```elixir
# Start a connection using the minimal Echo adapter
{:ok, pid} = WebsockexNova.Connection.start_link(adapter: WebsockexNova.Platform.Echo.Adapter)

# Send a text message and receive an echo
WebsockexNova.Client.send_text(pid, "Hello")
# => {:text, "Hello"}

# Send a JSON message and receive an echo
WebsockexNova.Client.send_json(pid, %{foo: "bar"})
# => {:text, "{\"foo\":\"bar\"}"}
```

- The Echo adapter is a minimal, reference implementation. Featureful adapters (like Deribit) support authentication, subscriptions, and more.
- See the [Adapter Integration Guide](docs/guides/adapter_integration.md) for advanced usage and adapter development.

## Advanced: Custom Process-Based Client Example

For advanced use cases, you can build your own process that manages a WebsockexNova connection and interacts with it using the client API. This is useful if you want to encapsulate connection management, message routing, or integrate with other OTP behaviors.

```elixir
defmodule MyApp.AdvancedClient do
  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    # Start a connection to the Echo adapter
    {:ok, conn_pid} = WebsockexNova.Connection.start_link(adapter: WebsockexNova.Platform.Echo.Adapter)
    {:ok, %{conn: conn_pid}}
  end

  @doc """
  Send a text message and get the reply (synchronously).
  """
  def echo_text(text) do
    GenServer.call(__MODULE__, {:echo_text, text})
  end

  @impl true
  def handle_call({:echo_text, text}, _from, %{conn: conn} = state) do
    reply = WebsockexNova.Client.send_text(conn, text)
    {:reply, reply, state}
  end
end

# Usage:
MyApp.AdvancedClient.start_link([])
MyApp.AdvancedClient.echo_text("Hello from advanced client!")
# => {:text, "Hello from advanced client!"}
```

- This pattern gives you full control over process supervision, state, and message routing.
- For most use cases, the direct `WebsockexNova.Client` API is simpler and preferred.

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
- [Adapter Integration Guide](docs/guides/adapter_integration.md)
- [API Reference](https://hexdocs.pm/websockex_nova)

## Deployment Profiles

WebsockexNova supports different deployment profiles:

- **Financial Profile**: For high-frequency trading and financial applications
- **Standard Profile**: For general-purpose WebSocket applications
- **Lightweight Profile**: For simple WebSocket integrations
- **Chat/Messaging Profile**: Optimized for interactive messaging platforms

## Supervision Tree

WebsockexNova uses a robust OTP supervision tree to ensure reliability and fault-tolerance:

```
WebsockexNova.Application (Supervisor)
├── WebsockexNova.Gun.ClientSupervisor (DynamicSupervisor)
│   └── WebsockexNova.Gun.ConnectionWrapper (one per connection)
└── WebsockexNova.Transport.RateLimiting (GenServer)
```

- **ClientSupervisor**: Dynamically supervises all Gun/WebSocket connection processes. Each connection is a `ConnectionWrapper` GenServer.
- **RateLimiting**: Centralized GenServer for rate limiting and request queueing.
- All critical processes are supervised and implement graceful shutdown.
- The supervision strategy is `:one_for_one` for independent fault isolation.

See the code and guides for more details on customizing the supervision tree for your deployment.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
