defmodule WebsockexNova.Behaviors.MetricsCollector do
  @moduledoc """
  Behavior for collecting and aggregating metrics from WebsockexNova telemetry events.

  Implement this behavior to handle connection, message, and error telemetry events.
  The default implementation is `WebsockexNova.Defaults.DefaultMetricsCollector`.

  ## Callbacks

    * `handle_connection_event/3` — Handles connection-related telemetry events
    * `handle_message_event/3` — Handles message-related telemetry events
    * `handle_error_event/3` — Handles error-related telemetry events

  ## Metric Types

    * `:counter` — Monotonically increasing value
    * `:gauge` — Value that can go up or down
    * `:histogram` — Distribution of values (e.g., durations, sizes)

  ## Example

      def handle_connection_event(event, measurements, metadata) do
        # Track connection open/close, durations, etc.
        :ok
      end
  """

  @type metric_type :: :counter | :gauge | :histogram
  @type event :: [atom()]
  @type measurements :: map()
  @type metadata :: map()

  @callback handle_connection_event(event, measurements, metadata) :: :ok
  @callback handle_message_event(event, measurements, metadata) :: :ok
  @callback handle_error_event(event, measurements, metadata) :: :ok
end
