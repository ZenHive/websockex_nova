defmodule WebsockexNova.Defaults.DefaultErrorHandler do
  @moduledoc """
  Default implementation of the ErrorHandler behavior.

  This module provides sensible default implementations for all ErrorHandler
  callbacks, including:

  * Error classification by type
  * Reconnection logic with exponential backoff
  * Standardized error logging
  * State tracking of errors

  ## Usage

  You can use this module directly or as a starting point for your own implementation:

      defmodule MyApp.CustomErrorHandler do
        use WebsockexNova.Defaults.DefaultErrorHandler

        # Override specific callbacks as needed
        def should_reconnect?(error, attempt, state) do
          # Custom reconnection logic
          {attempt < 10, attempt * 1000}
        end
      end

  ## Configuration

  The default handler supports configuration via the `:reconnection` key in the state (preferred),
  or legacy keys for backward compatibility:

  * `:reconnection` - map or keyword list with keys:
      * `:max_attempts` or `:max_reconnect_attempts` (default: 5)
      * `:base_delay` or `:initial_delay` (default: 1000)
      * `:max_delay` (default: 30000)
      * `:strategy` (currently only exponential supported)
  * Legacy keys (for backward compatibility):
      * `:max_reconnect_attempts`, `:base_delay`, `:max_delay`
  """

  @behaviour WebsockexNova.Behaviors.ErrorHandler

  require Logger

  @default_max_reconnect_attempts 5
  # 1 second
  @default_base_delay 1_000
  # 30 seconds
  @default_max_delay 30_000

  @impl true
  def handle_error(error, context, state) do
    # Track the error in the state
    state =
      state
      |> Map.put(:last_error, error)
      |> Map.put(:error_context, context)

    # Handle based on error classification
    case classify_error(error, context) do
      :critical ->
        {:stop, :critical_error, state}

      :normal ->
        # Non-critical errors don't need special handling
        {:ok, state}

      :transient ->
        # For transient errors, calculate retry delay
        attempt = Map.get(context, :attempt, 1)
        {max_attempts, base_delay, max_delay} = extract_reconnection_opts(state)

        if attempt <= max_attempts do
          delay = calculate_backoff_delay(attempt, base_delay, max_delay)
          {:retry, delay, state}
        else
          {:stop, :max_retry_attempts_reached, state}
        end
    end
  end

  @impl true
  def should_reconnect?(error, attempt, state) do
    {max_attempts, base_delay, max_delay} = extract_reconnection_opts(state)

    if attempt <= max_attempts && reconnectable_error?(error) do
      delay = calculate_backoff_delay(attempt, base_delay, max_delay)
      {true, delay}
    else
      {false, 0}
    end
  end

  @impl true
  def log_error(error, context, _state) do
    error_type = extract_error_type(error)
    context_str = format_context(context)

    case classify_error(error, context) do
      :critical ->
        Logger.warning("CRITICAL WebSocket error: #{error_type} - #{inspect(error)}. #{context_str}")

      :normal ->
        Logger.info("WebSocket error: #{error_type} - #{inspect(error)}. #{context_str}")

      :transient ->
        Logger.info("Transient WebSocket error: #{error_type} - #{inspect(error)}. #{context_str}")
    end

    :ok
  end

  @impl true
  def classify_error({:connection_error, _}, _context), do: :transient
  def classify_error({:message_error, _}, _context), do: :normal
  def classify_error({:auth_error, _}, _context), do: :critical
  def classify_error({:critical_error, _}, _context), do: :critical
  def classify_error(_, _), do: :transient

  # Helper functions

  defp reconnectable_error?({:auth_error, _}), do: false
  defp reconnectable_error?({:critical_error, _}), do: false
  defp reconnectable_error?(_), do: true

  defp extract_error_type({type, _}), do: type
  defp extract_error_type(_), do: :unknown_error

  defp format_context(context) when is_map(context) do
    Enum.map_join(context, ", ", fn {k, v} -> "#{k}: #{inspect(v)}" end)
  end

  defp format_context(_), do: ""

  defp calculate_backoff_delay(attempt, base_delay, max_delay) do
    # Exponential backoff with bounded jitter
    raw_delay = min(max_delay, base_delay * :math.pow(2, attempt - 1))
    # Add jitter by taking a random value between 0.8*delay and delay
    jitter_min = raw_delay * 0.8
    trunc(jitter_min + :rand.uniform() * (raw_delay - jitter_min))
  end

  # Extract reconnection options from state (prefer :reconnection map, fallback to legacy keys)
  defp extract_reconnection_opts(state) do
    rc =
      case Map.get(state, :reconnection) do
        nil -> %{}
        rc when is_list(rc) -> Map.new(rc)
        rc when is_map(rc) -> rc
        _ -> %{}
      end

    max_attempts =
      Map.get(rc, :max_attempts) ||
        Map.get(rc, :max_reconnect_attempts) ||
        Map.get(state, :max_reconnect_attempts) ||
        @default_max_reconnect_attempts

    base_delay =
      Map.get(rc, :base_delay) ||
        Map.get(rc, :initial_delay) ||
        Map.get(state, :base_delay) ||
        @default_base_delay

    max_delay =
      Map.get(rc, :max_delay) ||
        Map.get(state, :max_delay) ||
        @default_max_delay

    {max_attempts, base_delay, max_delay}
  end
end
