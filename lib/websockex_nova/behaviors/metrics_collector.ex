defmodule WebsockexNova.Behaviors.MetricsCollector do
  @moduledoc """
  Behaviour for metrics collectors.
  All state and context are maps. All arguments and return values are explicit and documented.
  Supports both stateless (3-arity, for telemetry) and stateful (4-arity, for handler API) callbacks.
  """

  @typedoc "Metric type"
  @type metric_type :: :counter | :gauge | :histogram

  @typedoc "Event type"
  @type event :: [atom()]

  @typedoc "Measurements map"
  @type measurements :: map()

  @typedoc "Metadata map"
  @type metadata :: map()

  @typedoc "Canonical connection state struct"
  @type conn_state :: WebsockexNova.ClientConn.t()

  @doc """
  Handles connection-related telemetry events (stateless, for telemetry).
  Returns:
    - `:ok`
  """
  @callback handle_connection_event(event, measurements, metadata) :: :ok

  @doc """
  Handles connection-related events with canonical state struct (for handler API).
  Returns:
    - `{:ok, conn_state}`
  """
  @callback handle_connection_event(event, measurements, metadata, conn_state) :: {:ok, conn_state}

  @doc """
  Handles message-related telemetry events (stateless, for telemetry).
  Returns:
    - `:ok`
  """
  @callback handle_message_event(event, measurements, metadata) :: :ok

  @doc """
  Handles message-related events with canonical state struct (for handler API).
  Returns:
    - `{:ok, conn_state}`
  """
  @callback handle_message_event(event, measurements, metadata, conn_state) :: {:ok, conn_state}

  @doc """
  Handles error-related telemetry events (stateless, for telemetry).
  Returns:
    - `:ok`
  """
  @callback handle_error_event(event, measurements, metadata) :: :ok

  @doc """
  Handles error-related events with canonical state struct (for handler API).
  Returns:
    - `{:ok, conn_state}`
  """
  @callback handle_error_event(event, measurements, metadata, conn_state) :: {:ok, conn_state}
end
