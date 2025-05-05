defmodule WebsockexNova.Behaviours.ErrorHandler do
  @moduledoc """
  Behaviour for error handlers.

  ## Responsibilities
  - The error handler is the **single source of truth** for reconnection policy (max attempts, backoff, etc.).
  - Tracks reconnection attempts and delays in its own state.
  - All reconnection decisions are delegated here from the connection manager and connection handler.
  - The transport adapter is responsible only for the mechanics of (re)connecting.

  ## Callbacks
  - `handle_error/3` — Handles errors and returns actions (`:ok`, `:stop`, `:retry`, `:reconnect`).
  - `should_reconnect?/3` — Returns `{true, delay}` or `{false, _}` based on error, attempt, and state.
  - `increment_reconnect_attempts/1` — (Optional) Increments the attempt count in the handler state.
  - `reset_reconnect_attempts/1` — (Optional) Resets the attempt count in the handler state.
  - `log_error/3` — Logs errors with context.
  - `classify_error/2` — (Optional) Classifies errors for reporting/metrics.

  All state is a map. All arguments and return values are explicit and documented.
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
