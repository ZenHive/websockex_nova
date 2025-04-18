defmodule WebsockexNova.Gun.Helpers.StateTracer do
  @moduledoc """
  Provides detailed tracing capabilities for connection state transitions.

  This module implements event tracing for WebSocket connection state changes,
  allowing for easier debugging and monitoring of the connection lifecycle.

  Features:
  - Records all state transitions with timestamps
  - Tracks connection statistics (uptime, reconnection frequency)
  - Provides a searchable history of connection events
  - Can output trace events to a file or monitoring system
  - Supports optional correlation IDs for distributed tracing
  """

  alias WebsockexNova.Gun.ConnectionState

  require Logger

  @doc """
  Initializes a new trace context in the connection state.

  ## Parameters

  * `state` - The current connection state
  * `trace_id` - Optional trace ID for distributed tracing (generates one if nil)

  ## Returns

  Updated connection state with trace context
  """
  @spec init_trace(ConnectionState.t(), String.t() | nil) :: map()
  def init_trace(state, trace_id \\ nil) do
    trace_id = trace_id || generate_trace_id()

    trace_context = %{
      trace_id: trace_id,
      started_at: current_timestamp(),
      events: [],
      connection_count: 0,
      total_uptime_ms: 0,
      last_connected_at: nil,
      last_disconnected_at: nil,
      reconnection_timestamps: []
    }

    Map.put(state, :trace_context, trace_context)
  end

  @doc """
  Traces a state transition event.

  ## Parameters

  * `state` - The current connection state
  * `event_type` - The type of event (:connect, :disconnect, :upgrade, etc.)
  * `from_status` - Previous connection status
  * `to_status` - New connection status
  * `metadata` - Additional contextual information about the event

  ## Returns

  Updated connection state with the event recorded
  """
  @spec trace_transition(ConnectionState.t(), atom(), atom(), atom(), map()) :: map()
  def trace_transition(state, event_type, from_status, to_status, metadata \\ %{}) do
    # If no trace context exists, create one
    state = ensure_trace_context(state)

    # Create the trace event
    event = %{
      event_type: event_type,
      from_status: from_status,
      to_status: to_status,
      timestamp: current_timestamp(),
      metadata: metadata
    }

    # Update state statistics based on event type
    state = update_statistics(state, event)

    # Record the event in the trace context
    trace_context = Map.update!(state.trace_context, :events, fn events -> [event | events] end)
    %{state | trace_context: trace_context}
  end

  @doc """
  Gets the full trace history from the connection state.

  ## Parameters

  * `state` - The connection state

  ## Returns

  List of trace events in chronological order (oldest first)
  """
  @spec get_trace_history(ConnectionState.t()) :: [map()]
  def get_trace_history(state) do
    case Map.get(state, :trace_context) do
      nil -> []
      %{events: events} -> Enum.reverse(events)
    end
  end

  @doc """
  Gets connection statistics from the trace context.

  ## Parameters

  * `state` - The connection state

  ## Returns

  Map of connection statistics
  """
  @spec get_statistics(ConnectionState.t()) :: map()
  def get_statistics(state) do
    case Map.get(state, :trace_context) do
      nil ->
        %{connection_count: 0, total_uptime_ms: 0, reconnection_count: 0}

      trace_context ->
        # Calculate current uptime if connected
        updated_uptime = calculate_current_uptime(trace_context)

        # Return statistics
        %{
          trace_id: trace_context.trace_id,
          connection_count: trace_context.connection_count,
          total_uptime_ms: updated_uptime,
          last_connected_at: trace_context.last_connected_at,
          last_disconnected_at: trace_context.last_disconnected_at,
          reconnection_count: length(trace_context.reconnection_timestamps)
        }
    end
  end

  @doc """
  Exports the trace history to a file.

  ## Parameters

  * `state` - The connection state
  * `path` - File path for the export

  ## Returns

  `:ok` on success, `{:error, reason}` on failure
  """
  @spec export_trace(ConnectionState.t(), Path.t()) :: :ok | {:error, term()}
  def export_trace(state, path) do
    history = get_trace_history(state)
    stats = get_statistics(state)

    export_data = %{
      host: state.host,
      port: state.port,
      statistics: stats,
      events: history
    }

    case Jason.encode(export_data, pretty: true) do
      {:ok, json} ->
        File.write(path, json)

      {:error, reason} ->
        Logger.error("Failed to export trace: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Private helper functions

  defp ensure_trace_context(state) do
    if Map.has_key?(state, :trace_context) do
      state
    else
      init_trace(state)
    end
  end

  defp generate_trace_id do
    16
    |> :crypto.strong_rand_bytes()
    |> Base.encode16(case: :lower)
  end

  defp current_timestamp do
    System.system_time(:millisecond)
  end

  defp update_statistics(state, event) do
    update_in(state.trace_context, fn trace ->
      case {event.event_type, event.to_status} do
        {_, :connected} ->
          increment_connection_count(trace, event.timestamp)

        {_, :disconnected} ->
          update_disconnection(trace, event.timestamp)

        {_, :reconnecting} ->
          add_reconnection_timestamp(trace, event.timestamp)

        _ ->
          trace
      end
    end)
  end

  defp increment_connection_count(trace, timestamp) do
    trace
    |> Map.update!(:connection_count, &(&1 + 1))
    |> Map.put(:last_connected_at, timestamp)
  end

  defp update_disconnection(trace, timestamp) do
    trace =
      if trace.last_connected_at do
        uptime = max(1, timestamp - trace.last_connected_at)
        Map.update!(trace, :total_uptime_ms, &(&1 + uptime))
      else
        trace
      end

    Map.put(trace, :last_disconnected_at, timestamp)
  end

  defp add_reconnection_timestamp(trace, timestamp) do
    Map.update!(trace, :reconnection_timestamps, &[timestamp | &1])
  end

  defp calculate_current_uptime(trace_context) do
    # If currently connected, add the ongoing connection time to the total
    if trace_context.last_connected_at &&
         (!trace_context.last_disconnected_at ||
            trace_context.last_connected_at > trace_context.last_disconnected_at) do
      ongoing_uptime = current_timestamp() - trace_context.last_connected_at
      trace_context.total_uptime_ms + ongoing_uptime
    else
      trace_context.total_uptime_ms
    end
  end
end
