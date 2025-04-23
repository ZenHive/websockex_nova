defmodule WebsockexNova.Behaviors.MetricsCollector do
  @moduledoc """
  Behaviour for metrics collectors.
  All state and context are maps. All arguments and return values are explicit and documented.
  """

  @typedoc "Metric type"
  @type metric_type :: :counter | :gauge | :histogram

  @typedoc "Event type"
  @type event :: [atom()]

  @typedoc "Measurements map"
  @type measurements :: map()

  @typedoc "Metadata map"
  @type metadata :: map()

  @doc """
  Handles connection-related telemetry events.
  Returns:
    - `:ok`
  """
  @callback handle_connection_event(event, measurements, metadata) :: :ok

  @doc """
  Handles message-related telemetry events.
  Returns:
    - `:ok`
  """
  @callback handle_message_event(event, measurements, metadata) :: :ok

  @doc """
  Handles error-related telemetry events.
  Returns:
    - `:ok`
  """
  @callback handle_error_event(event, measurements, metadata) :: :ok
end
