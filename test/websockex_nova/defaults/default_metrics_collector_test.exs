defmodule WebsockexNova.Defaults.DefaultMetricsCollectorTest do
  use ExUnit.Case, async: false

  alias WebsockexNova.Defaults.DefaultMetricsCollector
  alias WebsockexNova.Telemetry.TelemetryEvents

  setup do
    # Ensure the collector is started and ETS is clean
    {:ok, _pid} = DefaultMetricsCollector.start_link([])
    :ets.delete_all_objects(:websockex_nova_metrics)
    :ok
  end

  test "increments connection open and close metrics" do
    :telemetry.execute(TelemetryEvents.connection_open(), %{duration: 42}, %{
      connection_id: 1,
      host: "localhost",
      port: 1234
    })

    :telemetry.execute(TelemetryEvents.connection_close(), %{duration: 55}, %{
      connection_id: 1,
      host: "localhost",
      port: 1234,
      reason: :normal
    })

    assert DefaultMetricsCollector.get_metric(:connections_opened) == 1
    assert DefaultMetricsCollector.get_metric(:connections_closed) == 1
    assert DefaultMetricsCollector.get_metric(:connection_open_duration) == 42
    assert DefaultMetricsCollector.get_metric(:connection_close_duration) == 55
  end

  test "increments websocket upgrade metric" do
    :telemetry.execute(TelemetryEvents.connection_websocket_upgrade(), %{duration: 10}, %{
      connection_id: 1,
      stream_ref: make_ref(),
      headers: []
    })

    assert DefaultMetricsCollector.get_metric(:websocket_upgrades) == 1
    assert DefaultMetricsCollector.get_metric(:websocket_upgrade_duration) == 10
  end

  test "tracks message sent and received metrics" do
    :telemetry.execute(TelemetryEvents.message_sent(), %{size: 100, latency: 5}, %{
      connection_id: 1,
      stream_ref: make_ref(),
      frame_type: :text
    })

    :telemetry.execute(TelemetryEvents.message_received(), %{size: 200, latency: 7}, %{
      connection_id: 1,
      stream_ref: make_ref(),
      frame_type: :text
    })

    assert DefaultMetricsCollector.get_metric(:messages_sent) == 1
    assert DefaultMetricsCollector.get_metric(:messages_received) == 1
    assert DefaultMetricsCollector.get_metric(:bytes_sent) == 100
    assert DefaultMetricsCollector.get_metric(:bytes_received) == 200
    assert DefaultMetricsCollector.get_metric(:message_sent_latency) == 5
    assert DefaultMetricsCollector.get_metric(:message_received_latency) == 7
  end

  test "tracks error metrics by reason" do
    :telemetry.execute(TelemetryEvents.error_occurred(), %{}, %{
      connection_id: 1,
      reason: :timeout,
      stream_ref: nil,
      context: %{}
    })

    :telemetry.execute(TelemetryEvents.error_occurred(), %{}, %{
      connection_id: 1,
      reason: :other,
      stream_ref: nil,
      context: %{}
    })

    assert DefaultMetricsCollector.get_metric({:error, :timeout}) == 1
    assert DefaultMetricsCollector.get_metric({:error, :other}) == 1
    assert DefaultMetricsCollector.get_metric(:errors_total) == 2
  end

  test "get_metric/2 returns default if metric is missing" do
    assert DefaultMetricsCollector.get_metric(:nonexistent, 123) == 123
  end
end
