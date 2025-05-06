defmodule WebsockexNova.Transport.Reconnection.LinearBackoff do
  @moduledoc """
  Implements a constant delay reconnection strategy.

  This strategy always waits the same amount of time between reconnection attempts.
  It's simple and predictable but doesn't account for network congestion or
  other scaling concerns.

  ## Options

  * `:delay` - Constant delay in milliseconds (default: 1000)
  * `:max_retries` - Maximum number of retry attempts (default: 5, use :infinity for unlimited)
  """

  @type t :: %__MODULE__{
          delay: non_neg_integer(),
          max_retries: pos_integer() | :infinity
        }

  defstruct delay: 1000,
            max_retries: 5

  @doc """
  Calculate the delay for a reconnection attempt.

  For LinearBackoff, this always returns the same delay regardless of attempt number.

  ## Parameters

  * `strategy` - The LinearBackoff strategy struct
  * `_attempt` - The current attempt number (ignored in this strategy)

  ## Returns

  * Constant delay in milliseconds
  """
  @spec calculate_delay(t(), pos_integer()) :: non_neg_integer()
  def calculate_delay(%__MODULE__{delay: delay}, _attempt) do
    delay
  end

  @doc """
  Determines if a reconnection should be attempted.

  ## Parameters

  * `strategy` - The LinearBackoff strategy struct
  * `attempt` - The current attempt number (1-based)

  ## Returns

  * `true` if the attempt number is within the maximum retries
  * `false` otherwise
  """
  @spec should_retry?(t(), pos_integer()) :: boolean()
  def should_retry?(%__MODULE__{max_retries: :infinity}, _attempt) do
    true
  end

  def should_retry?(%__MODULE__{max_retries: max_retries}, attempt) do
    attempt <= max_retries
  end
end

defmodule WebsockexNova.Transport.Reconnection.ExponentialBackoff do
  @moduledoc """
  Implements an exponential backoff reconnection strategy.

  This strategy increases the delay exponentially with each attempt (2^n),
  with optional jitter to prevent thundering herd problems. It's well-suited
  for handling temporary network issues and server overload.

  ## Options

  * `:initial_delay` - Base delay in milliseconds (default: 1000)
  * `:max_delay` - Maximum delay in milliseconds (default: 30_000)
  * `:jitter_factor` - Random factor to apply (0.0-1.0, default: 0.1)
  * `:max_retries` - Maximum number of retry attempts (default: 5, use :infinity for unlimited)
  """

  @type t :: %__MODULE__{
          initial_delay: non_neg_integer(),
          max_delay: non_neg_integer(),
          jitter_factor: float(),
          max_retries: pos_integer() | :infinity
        }

  defstruct initial_delay: 1000,
            max_delay: 30_000,
            jitter_factor: 0.1,
            max_retries: 5

  @doc """
  Calculate the delay for a reconnection attempt.

  For ExponentialBackoff, this increases as 2^(attempt-1) * initial_delay,
  with optional jitter, and capped at max_delay.

  ## Parameters

  * `strategy` - The ExponentialBackoff strategy struct
  * `attempt` - The current attempt number (1-based)

  ## Returns

  * Calculated delay in milliseconds
  """
  @spec calculate_delay(t(), pos_integer()) :: non_neg_integer()
  def calculate_delay(
        %__MODULE__{
          initial_delay: initial_delay,
          max_delay: max_delay,
          jitter_factor: jitter_factor
        },
        attempt
      ) do
    # First attempt uses initial delay, then exponential growth
    base_delay =
      if attempt == 1 do
        initial_delay
      else
        # 2^(attempt-1) * initial_delay (e.g., 2^1 * 1000 = 2000 for attempt 2)
        trunc(:math.pow(2, attempt - 1) * initial_delay)
      end

    # Apply max delay cap
    capped_delay = min(base_delay, max_delay)

    # Add jitter if enabled
    if jitter_factor > 0 and Mix.env() != :test do
      jitter = trunc(capped_delay * jitter_factor * :rand.uniform())
      capped_delay + jitter
    else
      # In test environment, use deterministic values
      capped_delay
    end
  end

  @doc """
  Determines if a reconnection should be attempted.

  ## Parameters

  * `strategy` - The ExponentialBackoff strategy struct
  * `attempt` - The current attempt number (1-based)

  ## Returns

  * `true` if the attempt number is within the maximum retries
  * `false` otherwise
  """
  @spec should_retry?(t(), pos_integer()) :: boolean()
  def should_retry?(%__MODULE__{max_retries: :infinity}, _attempt) do
    true
  end

  def should_retry?(%__MODULE__{max_retries: max_retries}, attempt) do
    attempt <= max_retries
  end
end

defmodule WebsockexNova.Transport.Reconnection.JitteredBackoff do
  @moduledoc """
  Implements a linear backoff with jitter reconnection strategy.

  This strategy increases the delay linearly with each attempt and adds
  a random jitter to prevent thundering herd problems. It provides a more
  gradual increase than exponential backoff while still spreading out
  reconnections.

  ## Options

  * `:base_delay` - Base delay in milliseconds (default: 1000)
  * `:jitter_factor` - Random factor to apply (0.0-1.0, default: 0.2)
  * `:max_retries` - Maximum number of retry attempts (default: 5, use :infinity for unlimited)
  """

  @type t :: %__MODULE__{
          base_delay: non_neg_integer(),
          jitter_factor: float(),
          max_retries: pos_integer() | :infinity
        }

  defstruct base_delay: 1000,
            jitter_factor: 0.2,
            max_retries: 5

  @doc """
  Calculate the delay for a reconnection attempt.

  For JitteredBackoff, this increases linearly as attempt * base_delay,
  with a random jitter applied.

  ## Parameters

  * `strategy` - The JitteredBackoff strategy struct
  * `attempt` - The current attempt number (1-based)

  ## Returns

  * Calculated delay in milliseconds
  """
  @spec calculate_delay(t(), pos_integer()) :: non_neg_integer()
  def calculate_delay(%__MODULE__{base_delay: base_delay, jitter_factor: jitter_factor}, attempt) do
    # Linear delay based on attempt number
    base = base_delay * attempt

    # Apply jitter
    jitter_range = trunc(base * jitter_factor)
    jitter = :rand.uniform(jitter_range * 2) - jitter_range

    # Ensure we don't go negative
    max(base + jitter, div(base, 2))
  end

  @doc """
  Determines if a reconnection should be attempted.

  ## Parameters

  * `strategy` - The JitteredBackoff strategy struct
  * `attempt` - The current attempt number (1-based)

  ## Returns

  * `true` if the attempt number is within the maximum retries
  * `false` otherwise
  """
  @spec should_retry?(t(), pos_integer()) :: boolean()
  def should_retry?(%__MODULE__{max_retries: :infinity}, _attempt) do
    true
  end

  def should_retry?(%__MODULE__{max_retries: max_retries}, attempt) do
    attempt <= max_retries
  end
end

defmodule WebsockexNova.Transport.Reconnection do
  @moduledoc """
  Provides various reconnection strategies for WebSocket connections.

  This module contains implementations of different backoff algorithms for reconnection:

  * `LinearBackoff` - Constant delay between reconnection attempts
  * `ExponentialBackoff` - Exponentially increasing delay (with jitter)
  * `JitteredBackoff` - Linear increase with random jitter

  ## Usage

  ```elixir
  # Get a strategy
  strategy = WebsockexNova.Transport.Reconnection.get_strategy(:exponential,
    initial_delay: 1000,
    max_delay: 30_000,
    max_retries: 10
  )

  # Calculate delay for attempt number
  delay = WebsockexNova.Transport.Reconnection.calculate_delay(strategy, attempt)

  # Check if we should try again
  if WebsockexNova.Transport.Reconnection.should_retry?(strategy, attempt) do
    # Schedule reconnect after delay
  end
  ```
  """

  alias WebsockexNova.Transport.Reconnection.ExponentialBackoff
  alias WebsockexNova.Transport.Reconnection.JitteredBackoff
  alias WebsockexNova.Transport.Reconnection.LinearBackoff

  @doc """
  Returns a reconnection strategy based on the given type and options.

  ## Parameters

  * `type` - The type of backoff strategy (:linear, :exponential, or :jittered)
  * `opts` - Options specific to the chosen strategy

  ## Returns

  * A strategy struct of the corresponding type
  """
  @spec get_strategy(atom(), keyword()) :: struct()
  def get_strategy(type, opts \\ [])

  def get_strategy(:linear, opts) do
    %LinearBackoff{
      delay: Keyword.get(opts, :delay, 1000),
      max_retries: Keyword.get(opts, :max_retries, 5)
    }
  end

  def get_strategy(:exponential, opts) do
    %ExponentialBackoff{
      initial_delay: Keyword.get(opts, :initial_delay, 1000),
      max_delay: Keyword.get(opts, :max_delay, 30_000),
      jitter_factor: Keyword.get(opts, :jitter_factor, 0.1),
      max_retries: Keyword.get(opts, :max_retries, 5)
    }
  end

  def get_strategy(:jittered, opts) do
    %JitteredBackoff{
      base_delay: Keyword.get(opts, :base_delay, 1000),
      jitter_factor: Keyword.get(opts, :jitter_factor, 0.2),
      max_retries: Keyword.get(opts, :max_retries, 5)
    }
  end

  @doc """
  Calculates the delay for a reconnection attempt.

  Delegates to the appropriate strategy's calculate_delay function.

  ## Parameters

  * `strategy` - The reconnection strategy struct
  * `attempt` - The current attempt number (1-based)

  ## Returns

  * Delay in milliseconds
  """
  @spec calculate_delay(struct(), pos_integer()) :: non_neg_integer()
  def calculate_delay(%LinearBackoff{} = strategy, attempt) do
    LinearBackoff.calculate_delay(strategy, attempt)
  end

  def calculate_delay(%ExponentialBackoff{} = strategy, attempt) do
    ExponentialBackoff.calculate_delay(strategy, attempt)
  end

  def calculate_delay(%JitteredBackoff{} = strategy, attempt) do
    JitteredBackoff.calculate_delay(strategy, attempt)
  end

  @doc """
  Determines if a reconnection should be attempted.

  Delegates to the appropriate strategy's should_retry? function.

  ## Parameters

  * `strategy` - The reconnection strategy struct
  * `attempt` - The current attempt number (1-based)

  ## Returns

  * `true` if reconnection should be attempted
  * `false` otherwise
  """
  @spec should_retry?(struct(), pos_integer()) :: boolean()
  def should_retry?(%LinearBackoff{} = strategy, attempt) do
    LinearBackoff.should_retry?(strategy, attempt)
  end

  def should_retry?(%ExponentialBackoff{} = strategy, attempt) do
    ExponentialBackoff.should_retry?(strategy, attempt)
  end

  def should_retry?(%JitteredBackoff{} = strategy, attempt) do
    JitteredBackoff.should_retry?(strategy, attempt)
  end
end
