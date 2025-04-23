defmodule WebsockexNova.Behaviors.ErrorHandler do
  @moduledoc """
  Behaviour for error handlers.
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
    - `{:reconnect, state}`
    - `{:retry, delay, state}`
    - `{:stop, reason, state}`
  """
  @callback handle_error(error, context, state) ::
              {:ok, state}
              | {:reconnect, state}
              | {:retry, delay, state}
              | {:stop, term(), state}

  @doc """
  Determine if reconnection should be attempted.
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

  @optional_callbacks [classify_error: 2]
end
