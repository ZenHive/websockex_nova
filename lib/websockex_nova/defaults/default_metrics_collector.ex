defmodule WebsockexNova.Defaults.DefaultMetricsCollector do
  @moduledoc """
  Default implementation of the MetricsCollector behavior for WebsockexNova.

  Subscribes to all relevant telemetry events and aggregates metrics in ETS tables.
  Provides a public API for querying metrics (for testing/demo purposes).

  All metrics handler API now uses the canonical WebsockexNova.ClientConn struct,
  with metrics-specific state in the :metrics field.

  ## Metrics Tracked

    * Connection statistics (open/close counts, durations)
    * Message throughput (sent/received count, size, latency)
    * Error metrics (count by category)

  ## Usage

      # Start the collector (normally done in your supervision tree)
      WebsockexNova.Defaults.DefaultMetricsCollector.start_link([])

      # Query metrics (for testing/demo)
      WebsockexNova.Defaults.DefaultMetricsCollector.get_metric(:connections_opened)
  """

  @behaviour WebsockexNova.Behaviours.MetricsCollector

  use GenServer

  alias WebsockexNova.ClientConn
  alias WebsockexNova.Telemetry.TelemetryEvents

  @table :websockex_nova_metrics

  # Public API

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @doc """
  Get a metric by key (for testing/demo).
  """
  def get_metric(key) do
    case :ets.lookup(@table, key) do
      [{^key, value}] -> value
      _ -> 0
    end
  end

  def get_metric(key, default) do
    case(:ets.lookup(@table, key)) do
      [{^key, value}] -> value
      _ -> default
    end
  end

  # GenServer callbacks

  @impl true
  def init(_) do
    :ets.new(@table, [:named_table, :public, :set, {:read_concurrency, true}])
    attach_telemetry_handlers()
    {:ok, %{}}
  end

  # --- MetricsCollector behaviour (3-arity) for telemetry/behaviour compliance ---
  @impl true
  def handle_connection_event(event, measurements, metadata)
      when is_list(event) and is_map(measurements) and is_map(metadata) do
    do_handle_connection_event(event, measurements, metadata)
    :ok
  end

  @impl true
  def handle_message_event(event, measurements, metadata)
      when is_list(event) and is_map(measurements) and is_map(metadata) do
    do_handle_message_event(event, measurements, metadata)
    :ok
  end

  @impl true
  def handle_error_event(event, measurements, metadata)
      when is_list(event) and is_map(measurements) and is_map(metadata) do
    do_handle_error_event(event, measurements, metadata)
    :ok
  end

  # --- Canonical struct API (4-arity) for explicit handler usage ---
  @impl true
  def handle_connection_event(event, measurements, metadata, %ClientConn{metrics: metrics} = conn)
      when is_list(event) and is_map(measurements) and is_map(metadata) and is_map(metrics) do
    do_handle_connection_event(event, measurements, metadata)
    {:ok, conn}
  end

  @impl true
  def handle_message_event(event, measurements, metadata, %ClientConn{metrics: metrics} = conn)
      when is_list(event) and is_map(measurements) and is_map(metadata) and is_map(metrics) do
    do_handle_message_event(event, measurements, metadata)
    {:ok, conn}
  end

  @impl true
  def handle_error_event(event, measurements, metadata, %ClientConn{metrics: metrics} = conn)
      when is_list(event) and is_map(measurements) and is_map(metadata) and is_map(metrics) do
    do_handle_error_event(event, measurements, metadata)
    {:ok, conn}
  end

  # Internal event logic (unchanged)
  def do_handle_connection_event(event, measurements, _metadata) do
    case event do
      [:websockex_nova, :connection, :open] ->
        incr(:connections_opened)
        record_duration(:connection_open_duration, measurements)

      [:websockex_nova, :connection, :close] ->
        incr(:connections_closed)
        record_duration(:connection_close_duration, measurements)

      [:websockex_nova, :connection, :websocket_upgrade] ->
        incr(:websocket_upgrades)
        record_duration(:websocket_upgrade_duration, measurements)

      _ ->
        :ok
    end

    :ok
  end

  def do_handle_message_event(event, measurements, _metadata) do
    case event do
      [:websockex_nova, :message, :sent] ->
        incr(:messages_sent)
        add(:bytes_sent, Map.get(measurements, :size, 0))
        record_latency(:message_sent_latency, measurements)

      [:websockex_nova, :message, :received] ->
        incr(:messages_received)
        add(:bytes_received, Map.get(measurements, :size, 0))
        record_latency(:message_received_latency, measurements)

      _ ->
        :ok
    end

    :ok
  end

  def do_handle_error_event(_event, _measurements, metadata) when is_map(metadata) do
    reason = Map.get(metadata, :reason, :unknown)
    incr({:error, reason})
    incr(:errors_total)
    :ok
  end

  # Telemetry attach
  defp attach_telemetry_handlers do
    :telemetry.attach_many(
      "websockex_nova_default_metrics_collector",
      [
        TelemetryEvents.connection_open(),
        TelemetryEvents.connection_close(),
        TelemetryEvents.connection_websocket_upgrade(),
        TelemetryEvents.message_sent(),
        TelemetryEvents.message_received(),
        TelemetryEvents.error_occurred()
      ],
      &__MODULE__.handle_telemetry/4,
      nil
    )
  end

  def handle_telemetry(event, measurements, metadata, _config) do
    # Ensure measurements and metadata are maps
    measurements_map = ensure_map(measurements)
    metadata_map = ensure_map(metadata)

    cond do
      List.starts_with?(event, [:websockex_nova, :connection]) ->
        __MODULE__.do_handle_connection_event(event, measurements_map, metadata_map)

      List.starts_with?(event, [:websockex_nova, :message]) ->
        __MODULE__.do_handle_message_event(event, measurements_map, metadata_map)

      List.starts_with?(event, [:websockex_nova, :error]) ->
        __MODULE__.do_handle_error_event(event, measurements_map, metadata_map)

      true ->
        :ok
    end
  end

  # ETS metric helpers
  defp incr(key), do: :ets.update_counter(@table, key, {2, 1}, {key, 0})

  defp add(key, value) when is_integer(value),
    do: :ets.update_counter(@table, key, {2, value}, {key, 0})

  defp add(_key, _), do: :ok

  # Record duration with pattern matching optimization
  defp record_duration(key, %{duration: ms}) when is_integer(ms) do
    :ets.update_counter(@table, key, {2, ms}, {key, 0})
  end

  defp record_duration(key, measurements) when is_map(measurements) do
    case Map.get(measurements, :duration) do
      ms when is_integer(ms) -> :ets.update_counter(@table, key, {2, ms}, {key, 0})
      _ -> :ok
    end
  end

  # Record latency with pattern matching optimization
  defp record_latency(key, %{latency: ms}) when is_integer(ms) do
    :ets.update_counter(@table, key, {2, ms}, {key, 0})
  end

  defp record_latency(key, measurements) when is_map(measurements) do
    case Map.get(measurements, :latency) do
      ms when is_integer(ms) -> :ets.update_counter(@table, key, {2, ms}, {key, 0})
      _ -> :ok
    end
  end

  # Ensure data is a map
  defp ensure_map(data) when is_map(data), do: data
  defp ensure_map(data) when is_list(data), do: Map.new(data)
  defp ensure_map(_), do: %{}
end
