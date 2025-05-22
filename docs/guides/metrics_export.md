# Exporting Metrics for External Systems

WebsockexNew emits [Telemetry](https://hexdocs.pm/telemetry/telemetry.html) events for all connection, message, and error activities. You can export these metrics to external systems such as Prometheus, StatsD, or any Telemetry-compatible backend using the [Telemetry.Metrics](https://hexdocs.pm/telemetry_metrics/) ecosystem.

---

## Prometheus Integration (Recommended)

### 1. Add Dependencies

Add the following to your `mix.exs`:

```elixir
defp deps do
  [
    {:telemetry_metrics, "~> 0.6"},
    {:telemetry_metrics_prometheus, "~> 1.0"}
  ]
end
```

### 2. Configure and Start the Prometheus Exporter

In your `application.ex`:

```elixir
def start(_type, _args) do
  children = [
    # ... your other children ...
    {TelemetryMetricsPrometheus, metrics: metrics()}
  ]
  Supervisor.start_link(children, strategy: :one_for_one)
end

defp metrics do
  [
    counter("websockex_new_connection_open_total", event_name: [:websockex_new, :connection, :open]),
    counter("websockex_new_connection_close_total", event_name: [:websockex_new, :connection, :close]),
    counter("websockex_new_message_sent_total", event_name: [:websockex_new, :message, :sent]),
    counter("websockex_new_message_received_total", event_name: [:websockex_new, :message, :received]),
    counter("websockex_new_error_total", event_name: [:websockex_new, :error, :occurred]),
    summary("websockex_new_message_sent_size_bytes", event_name: [:websockex_new, :message, :sent], measurement: :size)
  ]
end
```

### 3. Expose the Prometheus Metrics Endpoint

By default, `TelemetryMetricsPrometheus` exposes `/metrics` on port 9568. You can configure the port and path as needed.

- Visit `http://localhost:9568/metrics` to see all exported metrics.

---

## StatsD Integration

### 1. Add Dependency

```elixir
defp deps do
  [
    {:telemetry_metrics_statsd, "~> 0.6"}
  ]
end
```

### 2. Configure and Start the StatsD Reporter

In your `application.ex`:

```elixir
def start(_type, _args) do
  children = [
    # ... your other children ...
    {TelemetryMetricsStatsd, metrics: metrics(), host: "localhost", port: 8125}
  ]
  Supervisor.start_link(children, strategy: :one_for_one)
end
```

- The `metrics/0` function is the same as in the Prometheus example above.

---

## Custom Backends

You can use any Telemetry-compatible backend. See the [Telemetry.Metrics docs](https://hexdocs.pm/telemetry_metrics/) for more options and advanced usage.

---

## Example: Subscribing to Telemetry Events Directly

If you want to process metrics in your own code, you can subscribe to events directly:

```elixir
:telemetry.attach(
  "my-websockexnova-listener",
  [:websockex_new, :message, :sent],
  fn event, measurements, metadata, _config ->
    IO.inspect({event, measurements, metadata}, label: "WebsockexNew Telemetry")
  end,
  nil
)
```

---

## References

- [Telemetry.Metrics](https://hexdocs.pm/telemetry_metrics/)
- [TelemetryMetricsPrometheus](https://hexdocs.pm/telemetry_metrics_prometheus/)
- [TelemetryMetricsStatsd](https://hexdocs.pm/telemetry_metrics_statsd/)
- [Prometheus](https://prometheus.io/)
- [StatsD](https://github.com/statsd/statsd)
