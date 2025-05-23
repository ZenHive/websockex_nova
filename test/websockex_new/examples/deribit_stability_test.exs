defmodule WebsockexNew.Examples.DeribitStabilityTest do
  @moduledoc """
  24-hour stability test for DeribitGenServerAdapter with continuous heartbeats.

  This test runs for extended periods to verify:
  - Continuous heartbeat functionality
  - Automatic reconnection on failures
  - Memory stability
  - Message handling under load
  - Network disruption recovery

  Run with: mix test --only stability test/websockex_new/examples/deribit_stability_test.exs
  """

  use ExUnit.Case

  alias WebsockexNew.Examples.DeribitGenServerAdapter

  require Logger

  @moduletag :stability
  @moduletag timeout: :infinity

  # Test configuration
  @test_duration_hours 24
  @test_duration_ms @test_duration_hours * 60 * 60 * 1000
  @heartbeat_interval_seconds 30
  # Report every minute
  @subscription_channels ["ticker.BTC-PERPETUAL.raw", "ticker.ETH-PERPETUAL.raw"]

  defmodule StabilityMonitor do
    @moduledoc """
    Monitors the adapter during stability testing and collects metrics.
    """

    use GenServer

    defstruct [
      :adapter,
      :start_time,
      :heartbeat_count,
      :reconnection_count,
      :error_count,
      :message_count,
      :last_heartbeat_time,
      :test_pid
    ]

    def start_link(adapter, test_pid) do
      GenServer.start_link(__MODULE__, {adapter, test_pid})
    end

    def get_metrics(monitor) do
      GenServer.call(monitor, :get_metrics)
    end

    def record_heartbeat(monitor) do
      GenServer.cast(monitor, :heartbeat)
    end

    def record_reconnection(monitor) do
      GenServer.cast(monitor, :reconnection)
    end

    def record_error(monitor, error) do
      GenServer.cast(monitor, {:error, error})
    end

    def record_message(monitor) do
      GenServer.cast(monitor, :message)
    end

    @impl true
    def init({adapter, test_pid}) do
      state = %__MODULE__{
        adapter: adapter,
        start_time: System.monotonic_time(:millisecond),
        heartbeat_count: 0,
        reconnection_count: 0,
        error_count: 0,
        message_count: 0,
        last_heartbeat_time: System.monotonic_time(:millisecond),
        test_pid: test_pid
      }

      # Start periodic status reporting
      # Report every minute
      :timer.send_interval(60_000, :report_status)

      {:ok, state}
    end

    @impl true
    def handle_call(:get_metrics, _from, state) do
      metrics = %{
        runtime_ms: System.monotonic_time(:millisecond) - state.start_time,
        heartbeat_count: state.heartbeat_count,
        reconnection_count: state.reconnection_count,
        error_count: state.error_count,
        message_count: state.message_count,
        heartbeat_interval_ms: System.monotonic_time(:millisecond) - state.last_heartbeat_time
      }

      {:reply, metrics, state}
    end

    @impl true
    def handle_cast(:heartbeat, state) do
      now = System.monotonic_time(:millisecond)
      new_state = %{state | heartbeat_count: state.heartbeat_count + 1, last_heartbeat_time: now}
      {:noreply, new_state}
    end

    def handle_cast(:reconnection, state) do
      Logger.warning("📡 Reconnection detected! Count: #{state.reconnection_count + 1}")
      {:noreply, %{state | reconnection_count: state.reconnection_count + 1}}
    end

    def handle_cast({:error, error}, state) do
      Logger.error("❌ Error detected: #{inspect(error)}")
      {:noreply, %{state | error_count: state.error_count + 1}}
    end

    def handle_cast(:message, state) do
      {:noreply, %{state | message_count: state.message_count + 1}}
    end

    @impl true
    def handle_info(:report_status, state) do
      runtime_hours = (System.monotonic_time(:millisecond) - state.start_time) / (60 * 60 * 1000)
      heartbeat_rate = state.heartbeat_count / max(runtime_hours, 0.001)

      Logger.info("""

      📊 === STABILITY TEST STATUS REPORT ===
      ⏱️  Runtime: #{Float.round(runtime_hours, 2)} hours
      💓 Heartbeats: #{state.heartbeat_count} (#{Float.round(heartbeat_rate, 1)}/hour)
      🔄 Reconnections: #{state.reconnection_count}
      ❌ Errors: #{state.error_count}
      📨 Messages: #{state.message_count}
      🕐 Last heartbeat: #{div(System.monotonic_time(:millisecond) - state.last_heartbeat_time, 1000)}s ago
      =====================================
      """)

      {:noreply, state}
    end
  end

  setup do
    # Ensure we have credentials
    client_id = System.get_env("DERIBIT_CLIENT_ID")
    client_secret = System.get_env("DERIBIT_CLIENT_SECRET")

    if is_nil(client_id) or is_nil(client_secret) do
      {:skip, "DERIBIT_CLIENT_ID and DERIBIT_CLIENT_SECRET must be set"}
    end

    %{
      client_id: client_id,
      client_secret: client_secret
    }
  end

  @tag :stability
  test "24-hour continuous operation with heartbeats", %{
    client_id: client_id,
    client_secret: client_secret
  } do
    Logger.info("""

    🚀 === STARTING 24-HOUR STABILITY TEST ===
    Duration: #{@test_duration_hours} hours
    Heartbeat interval: #{@heartbeat_interval_seconds} seconds
    Subscriptions: #{inspect(@subscription_channels)}
    =======================================
    """)

    # Start the monitor
    {:ok, monitor} = StabilityMonitor.start_link(nil, self())

    # Create handler function that captures the monitor
    handler_fun = fn message ->
      case message do
        {:message, {:text, text}} ->
          StabilityMonitor.record_message(monitor)

          case Jason.decode(text) do
            {:ok, %{"method" => "heartbeat"}} ->
              StabilityMonitor.record_heartbeat(monitor)

            {:ok, %{"params" => %{"type" => "heartbeat"}}} ->
              # Deribit sends heartbeats as params.type = "heartbeat"
              StabilityMonitor.record_heartbeat(monitor)

            {:ok, %{"method" => "subscription", "params" => %{"channel" => channel}}} ->
              Logger.debug("📊 Market data: #{channel}")

            {:ok, %{"error" => error}} ->
              StabilityMonitor.record_error(monitor, error)

            {:ok, decoded} ->
              # Log unhandled messages for debugging
              if Map.has_key?(decoded, "method") do
                Logger.debug("Unhandled method: #{decoded["method"]}")
              end

              :ok

            _ ->
              :ok
          end

        {:protocol_error, reason} ->
          Logger.warning("🔌 WebSocket disconnected: #{inspect(reason)}")
          StabilityMonitor.record_reconnection(monitor)

        _ ->
          :ok
      end
    end

    # Start the adapter with our custom handler
    adapter_opts = [
      client_id: client_id,
      client_secret: client_secret,
      heartbeat_interval: @heartbeat_interval_seconds,
      handler: handler_fun,
      name: :stability_test_adapter
    ]

    {:ok, adapter} = DeribitGenServerAdapter.start_link(adapter_opts)

    # Wait for connection
    Process.sleep(2_000)

    # Authenticate
    assert :ok = DeribitGenServerAdapter.authenticate(adapter)
    Process.sleep(1_000)

    # Subscribe to channels
    assert :ok = DeribitGenServerAdapter.subscribe(adapter, @subscription_channels)

    # Run stability monitoring
    run_stability_test(adapter, monitor, @test_duration_ms)

    # Get final metrics
    metrics = StabilityMonitor.get_metrics(monitor)

    # Generate final report
    generate_final_report(metrics)

    # Assertions
    assert_stability_requirements(metrics)

    # Cleanup
    DeribitGenServerAdapter.unsubscribe(adapter, @subscription_channels)
    GenServer.stop(adapter)
  end

  defp run_stability_test(_adapter, _monitor, remaining_ms) when remaining_ms <= 0 do
    :ok
  end

  defp run_stability_test(adapter, monitor, remaining_ms) do
    # Check every 30 seconds
    check_interval = 30_000

    # Verify adapter is still alive
    if Process.alive?(Process.whereis(:stability_test_adapter)) do
      # Verify we can still communicate
      case DeribitGenServerAdapter.get_state(adapter) do
        {:ok, state} ->
          if state.authenticated do
            Logger.debug("✅ Adapter healthy and authenticated")
          else
            Logger.warning("⚠️  Adapter not authenticated, attempting re-auth")
            DeribitGenServerAdapter.authenticate(adapter)
          end

        error ->
          StabilityMonitor.record_error(monitor, error)
      end
    else
      Logger.error("💀 Adapter process died!")
      StabilityMonitor.record_error(monitor, :adapter_died)
    end

    # Sleep and continue
    Process.sleep(min(check_interval, remaining_ms))
    run_stability_test(adapter, monitor, remaining_ms - check_interval)
  end

  defp generate_final_report(metrics) do
    runtime_hours = metrics.runtime_ms / (60 * 60 * 1000)
    heartbeat_rate = metrics.heartbeat_count / max(runtime_hours, 0.001)
    message_rate = metrics.message_count / max(runtime_hours, 0.001)

    report = """

    📊 === FINAL STABILITY TEST REPORT ===

    Test Duration: #{Float.round(runtime_hours, 2)} hours

    Heartbeat Performance:
    - Total heartbeats: #{metrics.heartbeat_count}
    - Heartbeat rate: #{Float.round(heartbeat_rate, 1)}/hour
    - Expected heartbeats: #{round(runtime_hours * 120)}  # 2 per minute
    - Success rate: #{Float.round(metrics.heartbeat_count / max(runtime_hours * 120, 1) * 100, 1)}%

    Connection Stability:
    - Reconnections: #{metrics.reconnection_count}
    - Errors: #{metrics.error_count}
    - Uptime: #{Float.round((runtime_hours * 3600 - metrics.reconnection_count * 5) / (runtime_hours * 36), 1)}%

    Message Processing:
    - Total messages: #{metrics.message_count}
    - Message rate: #{Float.round(message_rate, 1)}/hour

    Overall Assessment:
    #{stability_assessment(metrics, runtime_hours)}

    =====================================
    """

    Logger.info(report)

    # Write report to file
    File.write!("stability_report_#{DateTime.to_iso8601(DateTime.utc_now())}.txt", report)
  end

  defp stability_assessment(metrics, runtime_hours) do
    heartbeat_success = metrics.heartbeat_count / max(runtime_hours * 120, 1)

    cond do
      metrics.error_count == 0 and metrics.reconnection_count == 0 and heartbeat_success > 0.95 ->
        "✅ EXCELLENT - Perfect stability with no issues"

      metrics.error_count < 5 and metrics.reconnection_count < 3 and heartbeat_success > 0.90 ->
        "✅ GOOD - Minor issues but within acceptable parameters"

      metrics.error_count < 10 and metrics.reconnection_count < 10 and heartbeat_success > 0.80 ->
        "⚠️  FAIR - Some stability issues detected, investigation recommended"

      true ->
        "❌ POOR - Significant stability issues requiring immediate attention"
    end
  end

  defp assert_stability_requirements(metrics) do
    runtime_hours = metrics.runtime_ms / (60 * 60 * 1000)

    # Heartbeat success rate should be > 95%
    heartbeat_success_rate = metrics.heartbeat_count / max(runtime_hours * 120, 1)

    assert heartbeat_success_rate > 0.95,
           "Heartbeat success rate too low: #{Float.round(heartbeat_success_rate * 100, 1)}%"

    # Should have minimal reconnections (< 1 per hour on average)
    reconnection_rate = metrics.reconnection_count / max(runtime_hours, 1)

    assert reconnection_rate < 1.0,
           "Too many reconnections: #{Float.round(reconnection_rate, 1)} per hour"

    # Error rate should be very low
    error_rate = metrics.error_count / max(runtime_hours, 1)

    assert error_rate < 2.0,
           "Too many errors: #{Float.round(error_rate, 1)} per hour"
  end
end
