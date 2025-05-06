defmodule WebsockexNova.Defaults.DefaultErrorHandler do
  @moduledoc """
  Default implementation of the ErrorHandler behavior.

  This module provides sensible default implementations for all ErrorHandler
  callbacks, including:

  * Error classification by type
  * Reconnection logic with exponential backoff
  * Standardized error logging
  * State tracking of errors and reconnection attempts (single source of truth)

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

  ## Reconnection Attempt Tracking

  This handler tracks the reconnection attempt count in the adapter_state under the `:reconnect_attempts` key.
  Use `increment_reconnect_attempts/1` and `reset_reconnect_attempts/1` to update this count.
  """

  @behaviour WebsockexNova.Behaviours.ErrorHandler

  require Logger

  @default_max_reconnect_attempts 5
  # 1 second
  @default_base_delay 1_000
  # 30 seconds
  @default_max_delay 30_000

  # State initialization helper
  def error_init(opts) when is_map(opts) or is_list(opts) do
    opts_map = if is_list(opts), do: Map.new(opts), else: opts
    known_keys = MapSet.new(Map.keys(%WebsockexNova.ClientConn{}))
    {known, custom} = Enum.split_with(opts_map, fn {k, _v} -> MapSet.member?(known_keys, k) end)
    known_map = Map.new(known)
    custom_map = Map.new(custom)
    conn = struct(WebsockexNova.ClientConn, known_map)

    conn = %{
      conn
      | error_handler_settings: Map.merge(conn.error_handler_settings || %{}, custom_map)
    }

    # Initialize adapter_state with reconnect_attempts = 1
    adapter_state = Map.get(conn, :adapter_state, %{})
    adapter_state = Map.put_new(adapter_state, :reconnect_attempts, 1)
    conn = %{conn | adapter_state: adapter_state}
    {:ok, conn}
  end

  @impl true
  def handle_error(error, context, %WebsockexNova.ClientConn{} = conn) when is_map(context) do
    # Track the error in the adapter_state
    adapter_state = conn.adapter_state || %{}

    updated_adapter_state =
      adapter_state
      |> Map.put(:last_error, error)
      |> Map.put(:error_context, context)

    updated_conn = %{conn | adapter_state: updated_adapter_state}

    # Use the attempt count from adapter_state, defaulting to 1
    attempt = get_reconnect_attempts(updated_conn)

    # Handle based on error classification
    case classify_error(error, context) do
      :critical ->
        {:stop, :critical_error, updated_conn}

      :normal ->
        # Non-critical errors don't need special handling
        {:ok, updated_conn}

      :transient ->
        {max_attempts, base_delay, max_delay} = extract_reconnection_opts(updated_conn)

        if attempt <= max_attempts do
          delay = calculate_backoff_delay(attempt, base_delay, max_delay)
          {:retry, delay, updated_conn}
        else
          {:stop, :max_retry_attempts_reached, updated_conn}
        end
    end
  end

  @impl true
  def should_reconnect?(error, _attempt, %WebsockexNova.ClientConn{} = conn) do
    # Always use the attempt count from adapter_state
    attempt = get_reconnect_attempts(conn)
    {max_attempts, base_delay, max_delay} = extract_reconnection_opts(conn)

    if attempt <= max_attempts && reconnectable_error?(error) do
      delay = calculate_backoff_delay(attempt, base_delay, max_delay)
      {true, delay}
    else
      {false, 0}
    end
  end

  @impl true
  def log_error(error, context, %WebsockexNova.ClientConn{} = _conn) when is_map(context) do
    error_type = extract_error_type(error)
    context_str = format_context(context)

    case classify_error(error, context) do
      :critical ->
        Logger.warning(
          "CRITICAL WebSocket error: #{error_type} - #{inspect(error)}. #{context_str}"
        )

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

  @doc """
  Get the reconnection attempt count from the adapter_state.
  """
  def get_reconnect_attempts(%WebsockexNova.ClientConn{adapter_state: adapter_state}) do
    # Default to 1 if not present
    Map.get(adapter_state || %{}, :reconnect_attempts, 1)
  end

  @doc """
  Increment the reconnection attempt count in the adapter_state.
  """
  @impl true
  def increment_reconnect_attempts(%WebsockexNova.ClientConn{adapter_state: adapter_state} = conn) do
    current_attempts = Map.get(adapter_state || %{}, :reconnect_attempts, 0)
    updated_adapter_state = Map.put(adapter_state || %{}, :reconnect_attempts, current_attempts + 1)
    %{conn | adapter_state: updated_adapter_state}
  end

  @doc """
  Reset the reconnection attempt count in the adapter_state.
  """
  @impl true
  def reset_reconnect_attempts(%WebsockexNova.ClientConn{adapter_state: adapter_state} = conn) do
    updated_adapter_state = Map.put(adapter_state || %{}, :reconnect_attempts, 1)
    %{conn | adapter_state: updated_adapter_state}
  end

  # Helper functions

  defp reconnectable_error?({:auth_error, _}), do: false
  defp reconnectable_error?({:critical_error, _}), do: false
  defp reconnectable_error?(_), do: true

  defp extract_error_type({type, _}), do: type
  defp extract_error_type(_), do: :unknown_error

  defp format_context(context) when is_map(context) do
    Enum.map_join(context, ", ", fn {k, v} -> "#{k}: #{inspect(v)}" end)
  end

  defp calculate_backoff_delay(attempt, base_delay, max_delay) do
    # Exponential backoff with bounded jitter
    raw_delay = min(max_delay, base_delay * :math.pow(2, attempt - 1))
    # Add jitter by taking a random value between 0.8*delay and delay
    jitter_min = raw_delay * 0.8
    trunc(jitter_min + :rand.uniform() * (raw_delay - jitter_min))
  end

  # Extract reconnection options from state (prefer :reconnection map, fallback to legacy keys)
  defp extract_reconnection_opts(%WebsockexNova.ClientConn{} = conn) do
    rc = extract_reconnection_config(conn)

    max_attempts = extract_max_attempts(rc, conn)
    base_delay = extract_base_delay(rc, conn)
    max_delay = extract_max_delay(rc, conn)

    {max_attempts, base_delay, max_delay}
  end

  defp extract_reconnection_config(%WebsockexNova.ClientConn{} = conn) do
    case Map.get(conn, :reconnection) do
      nil -> %{}
      rc when is_list(rc) -> Map.new(rc)
      rc when is_map(rc) -> rc
      _ -> %{}
    end
  end

  defp extract_max_attempts(rc, conn) do
    Map.get(rc, :max_attempts) ||
      Map.get(rc, :max_reconnect_attempts) ||
      Map.get(conn, :max_reconnect_attempts) ||
      @default_max_reconnect_attempts
  end

  defp extract_base_delay(rc, conn) do
    Map.get(rc, :base_delay) ||
      Map.get(rc, :initial_delay) ||
      Map.get(conn, :base_delay) ||
      @default_base_delay
  end

  defp extract_max_delay(rc, _conn) do
    Map.get(rc, :max_delay) ||
      @default_max_delay
  end
end
