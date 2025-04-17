defmodule WebsockexNova.Behaviors.ErrorHandler do
  @moduledoc """
  Defines the behavior for handling WebSocket errors.

  The ErrorHandler behavior defines how a WebSocket client should respond to
  various types of errors, determine reconnection strategies, and handle
  error logging. Implementing modules can customize error handling based on
  error type, context, and state.

  ## Callbacks

  * `handle_error/3` - Process an error and determine the appropriate action
  * `should_reconnect?/3` - Determine if reconnection should be attempted
  * `log_error/3` - Log an error with appropriate context
  """

  @typedoc """
  Error type or data - can be any term representing an error
  """
  @type error :: term()

  @typedoc """
  Context information about the error - typically a map with relevant data
  """
  @type context :: map()

  @typedoc """
  Handler state - can be any term
  """
  @type state :: term()

  @typedoc """
  Delay in milliseconds for retry/reconnect operations
  """
  @type delay :: non_neg_integer() | nil

  @typedoc """
  Return values for error handling callbacks

  * `{:ok, new_state}` - Continue with the updated state
  * `{:reconnect, new_state}` - Attempt to reconnect immediately
  * `{:retry, delay, new_state}` - Retry the operation after delay
  * `{:stop, reason, new_state}` - Stop the process with the given reason
  """
  @type handler_return ::
          {:ok, state()}
          | {:reconnect, state()}
          | {:retry, delay(), state()}
          | {:stop, term(), state()}

  @typedoc """
  Return values for reconnection decision

  * `{true, delay}` - Should reconnect after the specified delay (or immediately if nil)
  * `{false, _}` - Should not reconnect
  """
  @type reconnect_decision :: {boolean(), delay()}

  @doc """
  Handle an error and determine the appropriate action.

  Called when an error occurs during WebSocket operations.

  ## Parameters

  * `error` - The error that occurred
  * `context` - Additional context about the error
  * `state` - Current handler state

  ## Returns

  * `{:ok, new_state}` - Continue with the updated state
  * `{:reconnect, new_state}` - Attempt to reconnect immediately
  * `{:retry, delay, new_state}` - Retry the operation after delay milliseconds
  * `{:stop, reason, new_state}` - Stop the process with the given reason
  """
  @callback handle_error(error(), context(), state()) :: handler_return()

  @doc """
  Determine if reconnection should be attempted.

  Called to decide whether to reconnect after a disconnection or error.

  ## Parameters

  * `error` - The error that caused the disconnection
  * `attempt` - The current reconnection attempt number (starts at 1)
  * `state` - Current handler state

  ## Returns

  * `{true, delay}` - Should reconnect after delay milliseconds (or immediately if nil)
  * `{false, _}` - Should not reconnect
  """
  @callback should_reconnect?(error(), non_neg_integer(), state()) :: reconnect_decision()

  @doc """
  Log an error with appropriate context.

  Called to log an error with relevant context information.

  ## Parameters

  * `error_type` - The type of error (e.g., :connection_error, :message_error)
  * `context` - Additional context about the error
  * `state` - Current handler state

  ## Returns

  * `:ok`
  """
  @callback log_error(term(), context(), state()) :: :ok

  @doc """
  Optional callback for classifying errors.

  Called to categorize errors for different handling strategies.

  ## Parameters

  * `error` - The error to classify
  * `context` - Additional context about the error

  ## Returns

  * The error category (any term, typically an atom like :transient or :critical)
  """
  @callback classify_error(error(), context()) :: term()

  @optional_callbacks [classify_error: 2]
end
