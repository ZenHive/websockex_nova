defmodule WebsockexNova.Behaviors.ErrorHandler do
  @moduledoc """
  Defines the behavior for handling WebSocket errors.

  The ErrorHandler behavior is an essential part of WebsockexNova's thin adapter architecture,
  separating error handling concerns from both application logic and transport implementation
  details.

  ## Thin Adapter Pattern

  Within the thin adapter architecture:

  1. This behavior focuses exclusively on error handling and recovery strategies
  2. The connection wrapper delegates error handling decisions to implementations
  3. Your implementation can define domain-specific retry policies and logging
  4. The adapter handles the mechanical aspects of reconnection and cleanup

  ## Delegation Pattern

  The error handling delegation flow works as follows:

  1. Transport or application errors are caught by the connection layer
  2. The error is passed to your implementation for decision-making
  3. Your implementation decides on the appropriate recovery strategy
  4. The adapter executes the mechanical aspects of your decision

  ## Implementation Example

  ```elixir
  defmodule MyApp.FinancialErrorHandler do
    @behaviour WebsockexNova.Behaviors.ErrorHandler
    require Logger

    @impl true
    def handle_error(:timeout, %{retry_count: retry_count, url: url}, state) do
      # Special handling for timeout errors
      if retry_count < 3 do
        {:retry, exponential_backoff(retry_count), state}
      else
        Logger.error("Connection to \#{url} timed out after \#{retry_count} attempts")
        {:stop, :too_many_timeouts, state}
      end
    end

    @impl true
    def handle_error(:connection_closed, context, state) do
      # Auto-reconnect for connection closed errors
      {:reconnect, state}
    end

    @impl true
    def handle_error(error, context, state) do
      # Default error handling
      error_category = classify_error(error, context)

      case error_category do
        :critical -> {:stop, error, state}
        :transient -> {:retry, 1000, state}
        _ -> {:reconnect, state}
      end
    end

    @impl true
    def should_reconnect?(_error, attempt, _state) when attempt > 10 do
      # Stop trying after 10 attempts
      {false, nil}
    end

    @impl true
    def should_reconnect?(:network_error, attempt, _state) do
      # Use exponential backoff for network errors
      delay = trunc(:math.pow(2, attempt) * 1000) + :rand.uniform(1000)
      {true, delay}
    end

    @impl true
    def should_reconnect?(_error, _attempt, _state) do
      # Default reconnection strategy
      {true, 1000}
    end

    @impl true
    def log_error(:network_error, context, _state) do
      Logger.warn("Network error: \#{inspect(context.reason)}")
      :ok
    end

    @impl true
    def log_error(error_type, context, _state) do
      Logger.error("WebSocket error (\#{error_type}): \#{inspect(context)}")
      :ok
    end

    @impl true
    def classify_error(:timeout, _context), do: :transient
    def classify_error(:connection_closed, _context), do: :transient
    def classify_error(:authentication_failed, _context), do: :critical
    def classify_error(_error, _context), do: :unknown

    # Private helper function
    defp exponential_backoff(retry_count) do
      base_delay = 1000
      max_delay = 30_000

      delay = trunc(:math.pow(2, retry_count) * base_delay)
      min(delay, max_delay)
    end
  end

  ## Callbacks

  * `error_init/1` - Initialize the handler's state
  * `handle_error/3` - Process an error and determine the appropriate action
  * `should_reconnect?/3` - Determine if reconnection should be attempted
  * `log_error/3` - Log an error with appropriate context
  * `classify_error/2` - (Optional) Classify errors for different handling strategies
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
  Initialize the handler's state.

  Called when the error handler is started. The return value becomes the initial state.

  ## Parameters

  * `opts` - The options passed to the handler

  ## Returns

  * `{:ok, state}` - The initialized state
  * `{:error, reason}` - Initialization failed
  """
  @callback error_init(opts :: term()) :: {:ok, state()} | {:error, term()}

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
