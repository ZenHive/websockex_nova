defmodule WebsockexNova.Behaviors.ErrorHandler do
  @moduledoc """
  Behaviour for error handlers.

  The ErrorHandler is the **single source of truth** for error handling and reconnection
  policies in WebsockexNova. It centralizes all error-related decisions, including whether
  to retry operations, reconnect after failures, or stop the connection entirely.

  ## Responsibilities

  - The error handler is the **single source of truth** for reconnection policy (max attempts, backoff, etc.)
  - Tracks reconnection attempts and delays in its own state
  - All reconnection decisions are delegated here from the connection manager and connection handler
  - The transport adapter is responsible only for the mechanics of (re)connecting
  - Handles error classification for metrics and monitoring
  - Provides consistent error logging across the system

  ## Callbacks

  - `handle_error/3` — Handles errors and returns actions (`:ok`, `:stop`, `:retry`, `:reconnect`)
  - `should_reconnect?/3` — Returns `{true, delay}` or `{false, _}` based on error, attempt, and state
  - `increment_reconnect_attempts/1` — (Optional) Increments the attempt count in the handler state
  - `reset_reconnect_attempts/1` — (Optional) Resets the attempt count in the handler state
  - `log_error/3` — Logs errors with context
  - `classify_error/2` — (Optional) Classifies errors for reporting/metrics

  All state is a map. All arguments and return values are explicit and documented.

  ## Implementation Example

      defmodule MyApp.CustomErrorHandler do
        @behaviour WebsockexNova.Behaviors.ErrorHandler
        require Logger

        @impl true
        def handle_error(error, context, state) do
          # Classify the error for appropriate handling
          error_type = classify_error(error, context)
          
          case error_type do
            :network_error ->
              # Network errors should trigger reconnection
              {:reconnect, state}
            
            :authentication_error ->
              # Auth errors should stop the connection
              {:stop, {:authentication_failed, error}, state}
            
            :rate_limit ->
              # Rate limits should retry with exponential backoff
              delay = calculate_backoff(state.retry_count || 0)
              updated_state = Map.update(state, :retry_count, 1, &(&1 + 1))
              {:retry, delay, updated_state}
            
            :timeout ->
              # Timeouts might retry with shorter delay
              {:retry, 1000, state}
            
            :protocol_error ->
              # Protocol errors usually mean incompatibility
              {:stop, {:protocol_error, error}, state}
            
            _ ->
              # Unknown errors default to reconnection
              {:reconnect, state}
          end
        end

        @impl true
        def should_reconnect?(error, attempt, state) do
          # Define reconnection policy
          max_attempts = state[:max_reconnect_attempts] || 10
          base_delay = state[:base_reconnect_delay] || 1_000
          max_delay = state[:max_reconnect_delay] || 60_000
          
          if attempt >= max_attempts do
            # Too many attempts, stop reconnecting
            {false, nil}
          else
            # Calculate exponential backoff with jitter
            delay = calculate_exponential_backoff(attempt, base_delay, max_delay)
            {true, delay}
          end
        end

        @impl true
        def increment_reconnect_attempts(state) do
          Map.update(state, :reconnect_attempts, 1, &(&1 + 1))
        end

        @impl true
        def reset_reconnect_attempts(state) do
          state
          |> Map.put(:reconnect_attempts, 0)
          |> Map.put(:retry_count, 0)
        end

        @impl true
        def log_error(error, context, state) do
          error_type = classify_error(error, context)
          attempts = Map.get(state, :reconnect_attempts, 0)
          
          Logger.error(\\\"\\\"\\\"
          WebSocket error occurred:
            Type: \\\#{error_type}
            Error: \\\#{inspect(error)}
            Context: \\\#{inspect(context)}
            Reconnection attempts: \\\#{attempts}
          \\\"\\\"\\\")
        end

        @impl true
        def classify_error(error, context) do
          cond do
            # Network-related errors
            match?({:error, :nxdomain}, error) -> :network_error
            match?({:error, :econnrefused}, error) -> :network_error
            match?({:error, :ehostunreach}, error) -> :network_error
            match?({:error, :timeout}, error) -> :timeout
            
            # SSL/TLS errors
            match?({:ssl_error, _}, error) -> :ssl_error
            match?({:tls_alert, _}, error) -> :ssl_error
            
            # Authentication errors
            match?({:error, {:auth_failed, _}}, error) -> :authentication_error
            match?(%{"error" => "unauthorized"}, error) -> :authentication_error
            
            # Rate limiting
            match?(%{"error" => "rate_limit_exceeded"}, error) -> :rate_limit
            match?({:error, :too_many_requests}, error) -> :rate_limit
            
            # Protocol errors
            match?({:error, {:invalid_message, _}}, error) -> :protocol_error
            match?({:error, :invalid_frame}, error) -> :protocol_error
            
            # Connection state errors
            is_map(context) and Map.get(context, :during) == "handshake" -> :handshake_error
            is_map(context) and Map.get(context, :during) == "upgrade" -> :upgrade_error
            
            # Default classification
            true -> :unknown_error
          end
        end

        # Private helpers
        
        defp calculate_backoff(retry_count) do
          # Simple exponential backoff: 1s, 2s, 4s, 8s, etc.
          base_delay = 1_000
          max_delay = 30_000
          
          delay = base_delay * :math.pow(2, retry_count)
          min(round(delay), max_delay)
        end

        defp calculate_exponential_backoff(attempt, base_delay, max_delay) do
          # Exponential backoff with jitter
          delay = base_delay * :math.pow(2, attempt)
          delay_with_jitter = delay * (0.5 + :rand.uniform())
          
          min(round(delay_with_jitter), max_delay)
        end
      end

  ## Context Map Structure

  The context map typically contains:
  - `:during` - Phase when error occurred ("connect", "handshake", "upgrade", "message", etc.)
  - `:operation` - Specific operation that failed
  - `:gun_pid` - Gun process PID if available
  - `:stream_ref` - WebSocket stream reference
  - `:conn_info` - Connection information map
  - `:metadata` - Additional error metadata

  ## Error Classification

  Common error types to consider:
  - `:network_error` - Connection failures, DNS issues
  - `:timeout` - Operation timeouts
  - `:authentication_error` - Auth failures
  - `:rate_limit` - Rate limiting errors
  - `:protocol_error` - WebSocket protocol violations
  - `:ssl_error` - TLS/SSL errors
  - `:handshake_error` - WebSocket handshake failures
  - `:unknown_error` - Unclassified errors

  ## Reconnection Strategies

  1. **Exponential Backoff**: Delay doubles with each attempt
  2. **Linear Backoff**: Fixed delay between attempts
  3. **Fibonacci Backoff**: Delays follow Fibonacci sequence
  4. **Jittered Backoff**: Add randomness to prevent thundering herd
  5. **Circuit Breaker**: Stop reconnecting after threshold

  ## Tips

  1. Keep error classification comprehensive but simple
  2. Use exponential backoff with jitter for reconnection
  3. Set reasonable maximum reconnection attempts
  4. Log errors with sufficient context for debugging
  5. Consider different policies for different error types
  6. Reset attempt counters on successful reconnection
  7. Implement circuit breakers for persistent failures

  **Note**: The `:reconnect` return value from `handle_error/3` is deprecated.
  Use `should_reconnect?/3` for all reconnection policy decisions.

  See `WebsockexNova.Defaults.DefaultErrorHandler` for a reference implementation.
  """

  @typedoc "Handler state"
  @type state :: map()

  @typedoc "Error type or data"
  @type error :: term()

  @typedoc "Context information about the error"
  @type context :: map()

  @typedoc "Delay in milliseconds for retry/reconnect operations"
  @type delay :: non_neg_integer() | nil

  @doc """
  Handle an error and determine the appropriate action.
  Returns:
    - `{:ok, state}`
    - `{:retry, delay, state}`
    - `{:stop, reason, state}`
    - `{:reconnect, state}` (DEPRECATED: use `should_reconnect?/3` for policy)
  """
  @callback handle_error(error, context, state) ::
              {:ok, state}
              | {:retry, delay, state}
              | {:stop, term(), state}
              | {:reconnect, state}

  @doc """
  Determine if reconnection should be attempted.
  This is the single source of truth for reconnection policy.
  Returns:
    - `{true, delay}`
    - `{false, _}`
  """
  @callback should_reconnect?(error, non_neg_integer(), state) :: {boolean(), delay}

  @doc """
  Log an error with appropriate context.
  Returns:
    - `:ok`
  """
  @callback log_error(term(), context, state) :: :ok

  @doc """
  Optional callback for classifying errors.
  Returns:
    - The error category (any term, typically an atom like :transient or :critical)
  """
  @callback classify_error(error, context) :: term()

  @doc """
  Optional callback to increment the reconnection attempt count in the handler state.
  Returns the updated state.
  """
  @callback increment_reconnect_attempts(state) :: state

  @doc """
  Optional callback to reset the reconnection attempt count in the handler state.
  Returns the updated state.
  """
  @callback reset_reconnect_attempts(state) :: state

  @optional_callbacks [
    classify_error: 2,
    increment_reconnect_attempts: 1,
    reset_reconnect_attempts: 1
  ]
end
