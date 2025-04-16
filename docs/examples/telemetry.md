# WebSockexNova Telemetry Guide

This guide explains how to leverage WebSockexNova's telemetry capabilities for monitoring, alerting, and performance analysis.

## Telemetry Events Overview

WebSockexNova uses `:telemetry` to emit events at critical points in the connection lifecycle, providing visibility into WebSocket performance and behavior.

### Core Event Categories

| Category | Description |
|----------|-------------|
| Connection | Connection lifecycle events (connect, disconnect, reconnect) |
| Message | Message processing events (send, receive, encode, decode) |
| Subscription | Subscription management events (subscribe, unsubscribe) |
| Error | Error detection and handling events |
| Authentication | Authentication and authorization events |

### Full Event List

#### Connection Events

```
[:websockex_nova, :connection, :started]
[:websockex_nova, :connection, :completed]
[:websockex_nova, :connection, :disconnected]
[:websockex_nova, :connection, :reconnect, :attempt]
[:websockex_nova, :connection, :reconnect, :success]
[:websockex_nova, :connection, :reconnect, :failed]
```

#### Message Events

```
[:websockex_nova, :message, :received]
[:websockex_nova, :message, :sent]
[:websockex_nova, :message, :decode, :started]
[:websockex_nova, :message, :decode, :completed]
[:websockex_nova, :message, :encode, :started]
[:websockex_nova, :message, :encode, :completed]
[:websockex_nova, :message, :process, :started]
[:websockex_nova, :message, :process, :completed]
```

#### Subscription Events

```
[:websockex_nova, :subscription, :subscribe, :started]
[:websockex_nova, :subscription, :subscribe, :completed]
[:websockex_nova, :subscription, :unsubscribe, :started]
[:websockex_nova, :subscription, :unsubscribe, :completed]
```

#### Error Events

```
[:websockex_nova, :error, :occurred]
[:websockex_nova, :error, :handled]
```

#### Authentication Events

```
[:websockex_nova, :auth, :started]
[:websockex_nova, :auth, :completed]
[:websockex_nova, :auth, :failed]
[:websockex_nova, :auth, :refresh, :started]
[:websockex_nova, :auth, :refresh, :completed]
```

## Event Measurements and Metadata

### Connection Events

```elixir
# Connection started
:telemetry.execute([:websockex_nova, :connection, :started],
  %{system_time: System.system_time()},
  %{client_id: client_id, uri: uri})

# Connection completed
:telemetry.execute([:websockex_nova, :connection, :completed],
  %{duration: duration},
  %{client_id: client_id, uri: uri})

# Connection disconnected
:telemetry.execute([:websockex_nova, :connection, :disconnected],
  %{system_time: System.system_time(), duration: connection_duration},
  %{client_id: client_id, uri: uri, reason: reason})
```

### Message Events

```elixir
# Message received
:telemetry.execute([:websockex_nova, :message, :received],
  %{size: byte_size(message), system_time: System.system_time()},
  %{client_id: client_id, type: message_type})

# Message processing completed
:telemetry.execute([:websockex_nova, :message, :process, :completed],
  %{duration: duration},
  %{client_id: client_id, type: message_type, result: result})
```

## Configuring Telemetry

### Basic Setup

To start collecting telemetry events, attach handlers to the events you're interested in:

```elixir
defmodule MyApp.Telemetry do
  @moduledoc """
  Configures telemetry for WebSockexNova.
  """

  def setup do
    events = [
      [:websockex_nova, :connection, :completed],
      [:websockex_nova, :message, :received],
      [:websockex_nova, :error, :occurred]
    ]

    :telemetry.attach_many(
      "websockex-nova-logger",
      events,
      &__MODULE__.handle_event/4,
      nil
    )
  end

  def handle_event([:websockex_nova, :connection, :completed], measurements, metadata, _config) do
    Logger.info("Connection established in #{measurements.duration / 1_000_000}ms",
      client_id: metadata.client_id,
      uri: metadata.uri
    )
  end

  def handle_event([:websockex_nova, :message, :received], measurements, metadata, _config) do
    Logger.debug("Received #{metadata.type} message of size #{measurements.size} bytes",
      client_id: metadata.client_id,
      type: metadata.type
    )
  end

  def handle_event([:websockex_nova, :error, :occurred], _measurements, metadata, _config) do
    Logger.error("WebSocket error: #{inspect(metadata.error)}",
      client_id: metadata.client_id,
      error_type: metadata.error_type
    )
  end
end
```

Call `MyApp.Telemetry.setup()` in your application's `start/2` function to attach these handlers.

### Profile-Based Telemetry

Different profiles have different telemetry settings:

#### Financial Profile

```elixir
config :websockex_nova,
  telemetry: [
    level: :detailed,          # High granularity
    connection_events: true,   # Track all connection events
    message_events: true,      # Track all message events
    error_events: true,        # Track all error events
    heartbeat_events: true,    # Track heartbeats
    metadata_filter: false     # Include all metadata
  ]
```

#### Standard Profile

```elixir
config :websockex_nova,
  telemetry: [
    level: :standard,          # Medium granularity
    connection_events: true,   # Track connection events
    message_events: false,     # Skip detailed message events
    error_events: true,        # Track error events
    heartbeat_events: false,   # Skip heartbeat events
    metadata_filter: true      # Filter sensitive metadata
  ]
```

#### Lightweight Profile

```elixir
config :websockex_nova,
  telemetry: [
    level: :minimal,           # Low granularity
    connection_events: true,   # Track only major connection events
    message_events: false,     # Skip message events
    error_events: true,        # Track only major errors
    heartbeat_events: false,   # Skip heartbeat events
    metadata_filter: true      # Filter sensitive metadata
  ]
```

### Custom Telemetry Handlers

You can implement custom handlers for specific needs:

```elixir
defmodule MyApp.CustomTelemetry do
  def message_duration_handler([:websockex_nova, :message, :process, :completed], %{duration: duration}, metadata, _config) do
    # Send message processing duration to StatsD
    :statsix.gauge("websocket.message.process.duration",
      duration / 1_000_000,
      tags: ["client:#{metadata.client_id}", "type:#{metadata.type}"]
    )

    # Alert on slow message processing
    if duration > 100_000_000 do  # 100ms
      notify_operations("Slow message processing: #{duration / 1_000_000}ms for #{metadata.type}")
    end
  end
end
```

## Integration with Monitoring Systems

### Prometheus Integration

Using the `TelemetryMetricsPrometheus` library:

```elixir
defmodule MyApp.Telemetry do
  use Supervisor
  import Telemetry.Metrics

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  def init(_arg) do
    children = [
      {TelemetryMetricsPrometheus, metrics: metrics()}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  def metrics do
    [
      # Connection metrics
      counter("websockex_nova.connection.started.count", tags: [:client_id, :uri]),
      distribution("websockex_nova.connection.completed.duration",
        tags: [:client_id, :uri],
        unit: {:native, :millisecond},
        reporter_options: [
          buckets: [10, 100, 500, 1000, 5000]
        ]),

      # Message metrics
      counter("websockex_nova.message.received.count", tags: [:client_id, :type]),
      counter("websockex_nova.message.sent.count", tags: [:client_id, :type]),
      summary("websockex_nova.message.received.size", tags: [:client_id, :type]),
      summary("websockex_nova.message.sent.size", tags: [:client_id, :type]),
      distribution("websockex_nova.message.process.completed.duration",
        tags: [:client_id, :type],
        unit: {:native, :millisecond}),

      # Error metrics
      counter("websockex_nova.error.occurred.count", tags: [:client_id, :error_type]),

      # Subscription metrics
      counter("websockex_nova.subscription.subscribe.completed.count",
        tags: [:client_id, :channel])
    ]
  end
end
```

### Grafana Dashboard

Example Grafana dashboard queries for Prometheus:

**Connection Success Rate**:
```
sum(rate(websockex_nova_connection_completed_count[5m])) /
sum(rate(websockex_nova_connection_started_count[5m]))
```

**Average Connection Time**:
```
avg(websockex_nova_connection_completed_duration_milliseconds_sum /
websockex_nova_connection_completed_duration_milliseconds_count)
```

**Message Throughput**:
```
sum(rate(websockex_nova_message_received_count[1m])) by (client_id, type)
```

**Error Rate**:
```
sum(rate(websockex_nova_error_occurred_count[5m])) by (error_type)
```

## Key Performance Indicators

### Connection Health

- **Connection Success Rate**: `>99.9%` for financial applications, `>99%` for standard
- **Average Connection Time**: `<500ms` for financial, `<1s` for standard
- **Reconnection Success Rate**: `>99%` for all profiles
- **Time to Reconnect**: `<2s` for financial, `<5s` for standard

### Message Performance

- **Message Processing Time**: `<10ms` for financial, `<50ms` for standard
- **Message Throughput**: Depends on application requirements
- **Message Error Rate**: `<0.01%` for financial, `<0.1%` for standard

### Error Handling

- **Error Recovery Rate**: `>99%` for non-critical errors
- **Error-to-Alert Time**: `<5s` for critical errors in financial applications

## Best Practices

### 1. Focus on Critical Events

For production systems, focus on essential events to reduce overhead:
- Connection status changes
- Authentication failures
- Error occurrences
- Performance outliers

### 2. Use Aggregation for High-Volume Events

For high-volume message processing, use sampling or aggregation:
```elixir
# Counter for message volume instead of logging each message
:telemetry.execute(
  [:websockex_nova, :message, :batch_processed],
  %{count: messages_processed, total_size: total_size},
  %{client_id: client_id}
)
```

### 3. Set Up Appropriate Alerting

Create alerts for critical events:
- Connection failures beyond retry limits
- Authentication failures
- Sustained high error rates
- Unusual latency patterns

### 4. Correlate WebSocket Metrics with System Metrics

Combine WebSockexNova telemetry with system metrics:
- Network latency and packet loss
- CPU and memory utilization
- BEAM VM metrics (process count, reductions)
- Application-level metrics

## Conclusion

WebSockexNova's telemetry capabilities provide comprehensive visibility into WebSocket connections, from basic connectivity to detailed message processing. By configuring the appropriate level of telemetry for your application profile, you can effectively monitor performance, detect issues early, and ensure reliable WebSocket communication.

For specific platform integrations, refer to the platform-specific telemetry guides in the examples directory.
