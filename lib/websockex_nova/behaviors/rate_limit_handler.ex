defmodule WebsockexNova.Behaviors.RateLimitHandler do
  @moduledoc """
  Defines the behavior for handling rate limiting and throttling of WebSocket requests.

  This behavior enables client applications to implement rate limiting strategies
  that conform to service provider limitations and prevent request rejection due to
  exceeding allowed API call rates.

  ## Token Bucket Algorithm

  The default implementation uses a token bucket algorithm:

  - Each "bucket" has a maximum capacity of tokens
  - Tokens are added to the bucket at a defined refill rate
  - Each request consumes one or more tokens
  - If insufficient tokens are available, the request is either:
    - Queued until sufficient tokens are available (default)
    - Rejected with an error
    - Allowed to proceed but with a warning

  ## Common Implementation Patterns

  ```elixir
  defmodule MyApp.RateLimitHandler do
    @behaviour WebsockexNova.Behaviors.RateLimitHandler

    @impl true
    def init(opts) do
      # Initialize with configured limits
      state = %{
        bucket: %{
          capacity: opts[:capacity] || 60,
          tokens: opts[:capacity] || 60,
          refill_rate: opts[:refill_rate] || 1,
          refill_interval: opts[:refill_interval] || 1000,
          last_refill: System.monotonic_time(:millisecond)
        },
        queue: :queue.new(),
        queue_limit: opts[:queue_limit] || 100
      }
      {:ok, state}
    end

    @impl true
    def check_rate_limit(request, state) do
      # Calculate available tokens since last refill
      current_time = System.monotonic_time(:millisecond)
      elapsed = current_time - state.bucket.last_refill
      tokens_to_add = trunc(elapsed / state.bucket.refill_interval * state.bucket.refill_rate)

      # Update bucket state
      updated_bucket =
        if tokens_to_add > 0 do
          %{
            state.bucket |
            tokens: min(state.bucket.capacity, state.bucket.tokens + tokens_to_add),
            last_refill: current_time
          }
        else
          state.bucket
        end

      # Check if we have enough tokens
      cost = calculate_cost(request)

      cond do
        updated_bucket.tokens >= cost ->
          # We have enough tokens, allow the request
          new_bucket = %{updated_bucket | tokens: updated_bucket.tokens - cost}
          new_state = %{state | bucket: new_bucket}
          {:allow, new_state}

        :queue.len(state.queue) < state.queue_limit ->
          # Queue the request for later
          new_queue = :queue.in({request, cost}, state.queue)
          new_state = %{state | bucket: updated_bucket, queue: new_queue}
          {:queue, new_state}

        true ->
          # Queue is full, reject the request
          {:reject, :rate_limit_exceeded, state}
      end
    end

    @impl true
    def handle_tick(state) do
      # Process queued requests if we have tokens available
      process_queue(state)
    end

    defp calculate_cost(request) do
      # Different request types may have different costs
      case request.type do
        :subscription -> 5
        :auth -> 10
        _ -> 1
      end
    end

    defp process_queue(state) do
      case :queue.out(state.queue) do
        {{:value, {request, cost}}, new_queue} ->
          if state.bucket.tokens >= cost do
            # We have enough tokens for the next queued request
            new_bucket = %{state.bucket | tokens: state.bucket.tokens - cost}
            new_state = %{state | bucket: new_bucket, queue: new_queue}
            {:process, request, new_state}
          else
            # Not enough tokens yet
            {:ok, state}
          end

        {:empty, _} ->
          # No queued requests
          {:ok, state}
      end
    end
  end
  ```

  ## Callbacks

  * `init/1` - Initialize the rate limiting state
  * `check_rate_limit/2` - Check if a request can proceed based on rate limits
  * `handle_tick/1` - (Optional) Process any queued requests when called periodically
  """

  @typedoc """
  Rate limit handler state - typically contains bucket information and request queue.
  """
  @type state :: term()

  @typedoc """
  Request information map.

  Contains details about the request to be rate limited:
  * `:type` - The type of request (e.g., :auth, :subscription, :query)
  * `:method` - The method or command being called
  * `:priority` - Optional priority level (higher priority may bypass limits)
  * `:data` - The request payload
  """
  @type request :: %{
          type: atom(),
          method: String.t(),
          priority: non_neg_integer() | nil,
          data: term()
        }

  @typedoc """
  Return values for check_rate_limit callback.

  * `{:allow, new_state}` - Allow the request to proceed
  * `{:queue, new_state}` - Queue the request for later processing
  * `{:reject, reason, new_state}` - Reject the request with the given reason
  """
  @type check_rate_limit_return ::
          {:allow, state()}
          | {:queue, state()}
          | {:reject, term(), state()}

  @typedoc """
  Return values for handle_tick callback.

  * `{:ok, new_state}` - No queued requests to process
  * `{:process, request, new_state}` - Process a queued request
  """
  @type handle_tick_return ::
          {:ok, state()}
          | {:process, request(), state()}

  @doc """
  Initialize the rate limit handler's state.

  Called when the handler is started. The return value becomes the initial state.

  ## Parameters

  * `opts` - Options for configuring rate limits

  ## Returns

  * `{:ok, state}` - The initialized state
  """
  @callback init(opts :: keyword()) :: {:ok, state()}

  @doc """
  Check if a request can proceed based on current rate limits.

  Called before sending a request to determine if it should proceed.

  ## Parameters

  * `request` - Information about the request
  * `state` - Current rate limit state

  ## Returns

  * `{:allow, new_state}` - Allow the request to proceed
  * `{:queue, new_state}` - Queue the request for later processing
  * `{:reject, reason, new_state}` - Reject the request with the given reason
  """
  @callback check_rate_limit(request(), state()) :: check_rate_limit_return()

  @doc """
  Process queued requests on a periodic tick.

  Called at regular intervals to process any queued requests.

  ## Parameters

  * `state` - Current rate limit state

  ## Returns

  * `{:ok, new_state}` - No queued requests to process
  * `{:process, request, new_state}` - Process a queued request
  """
  @callback handle_tick(state()) :: handle_tick_return()

  @optional_callbacks [handle_tick: 1]
end
