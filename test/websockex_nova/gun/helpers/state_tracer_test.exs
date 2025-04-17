defmodule WebSockexNova.Gun.Helpers.StateTracerTest do
  use ExUnit.Case, async: true

  alias WebSockexNova.Gun.ConnectionState
  alias WebSockexNova.Gun.Helpers.StateTracer

  describe "initialization" do
    test "init_trace/2 initializes trace context with default values" do
      state = ConnectionState.new("example.com", 443, %{transport: :tls})
      traced_state = StateTracer.init_trace(state)

      assert Map.has_key?(traced_state, :trace_context)
      assert traced_state.trace_context.connection_count == 0
      assert traced_state.trace_context.total_uptime_ms == 0
      assert is_list(traced_state.trace_context.events)
      assert length(traced_state.trace_context.events) == 0
      assert traced_state.trace_context.trace_id != nil
    end

    test "init_trace/2 respects custom trace_id" do
      state = ConnectionState.new("example.com", 443, %{transport: :tls})
      custom_id = "custom-trace-123"
      traced_state = StateTracer.init_trace(state, custom_id)

      assert traced_state.trace_context.trace_id == custom_id
    end
  end

  describe "event tracing" do
    setup do
      state =
        ConnectionState.new("example.com", 443, %{transport: :tls})
        |> StateTracer.init_trace()

      %{state: state}
    end

    test "trace_transition/5 records events correctly", %{state: state} do
      # Record a connection event
      state =
        StateTracer.trace_transition(state, :connect, :initialized, :connected, %{gun_pid: self()})

      # Verify event was recorded
      events = StateTracer.get_trace_history(state)
      assert length(events) == 1
      event = List.first(events)
      assert event.event_type == :connect
      assert event.from_status == :initialized
      assert event.to_status == :connected
      assert event.metadata.gun_pid == self()
    end

    test "trace_transition/5 updates connection statistics", %{state: state} do
      # Connection established
      state = StateTracer.trace_transition(state, :connect, :initialized, :connected, %{})
      stats = StateTracer.get_statistics(state)
      assert stats.connection_count == 1
      assert stats.last_connected_at != nil

      # Disconnection
      state =
        StateTracer.trace_transition(state, :disconnect, :connected, :disconnected, %{
          reason: :normal
        })

      stats = StateTracer.get_statistics(state)
      assert stats.last_disconnected_at != nil
      assert stats.total_uptime_ms > 0

      # Reconnection attempt
      state = StateTracer.trace_transition(state, :reconnect, :disconnected, :reconnecting, %{})
      stats = StateTracer.get_statistics(state)
      assert stats.reconnection_count == 1
    end

    test "multiple transitions are recorded in correct order", %{state: state} do
      transitions = [
        {:init, :initialized, :connecting},
        {:connect, :connecting, :connected},
        {:upgrade, :connected, :websocket_connected},
        {:disconnect, :websocket_connected, :disconnected},
        {:reconnect, :disconnected, :reconnecting}
      ]

      # Record all transitions
      state =
        Enum.reduce(transitions, state, fn {event_type, from, to}, acc_state ->
          StateTracer.trace_transition(acc_state, event_type, from, to, %{})
        end)

      # Get history and verify order (oldest first)
      events = StateTracer.get_trace_history(state)
      assert length(events) == length(transitions)

      # Verify each event in order
      Enum.zip(events, transitions)
      |> Enum.each(fn {event, {expected_type, expected_from, expected_to}} ->
        assert event.event_type == expected_type
        assert event.from_status == expected_from
        assert event.to_status == expected_to
      end)
    end
  end

  describe "statistics and exports" do
    setup do
      state =
        ConnectionState.new("example.com", 443, %{transport: :tls})
        |> StateTracer.init_trace()
        |> StateTracer.trace_transition(:init, :initialized, :connecting)
        |> StateTracer.trace_transition(:connect, :connecting, :connected)
        |> StateTracer.trace_transition(:upgrade, :connected, :websocket_connected)
        |> StateTracer.trace_transition(:disconnect, :websocket_connected, :disconnected)

      %{state: state}
    end

    test "get_statistics/1 returns correct connection stats", %{state: state} do
      stats = StateTracer.get_statistics(state)

      assert stats.connection_count == 1
      assert stats.total_uptime_ms > 0
      assert stats.reconnection_count == 0
      assert stats.trace_id != nil
      assert stats.last_connected_at != nil
      assert stats.last_disconnected_at != nil
    end

    test "get_trace_history/1 returns events in chronological order", %{state: state} do
      history = StateTracer.get_trace_history(state)

      assert length(history) == 4

      # Check events are in correct order (oldest to newest)
      event_types = Enum.map(history, & &1.event_type)
      assert event_types == [:init, :connect, :upgrade, :disconnect]
    end

    test "export_trace/2 creates a valid JSON file", %{state: state} do
      # Create a temporary file for testing
      path = System.tmp_dir!() <> "/websockex_nova_trace_test_#{:rand.uniform(999_999)}.json"

      result = StateTracer.export_trace(state, path)
      assert result == :ok

      # Read the file and verify content
      {:ok, content} = File.read(path)
      {:ok, parsed} = Jason.decode(content, keys: :atoms)

      assert parsed.host == "example.com"
      assert parsed.port == 443
      assert length(parsed.events) == 4
      assert parsed.statistics.connection_count == 1

      # Clean up test file
      File.rm!(path)
    end
  end
end
