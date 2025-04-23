defmodule WebsockexNova.Defaults.DefaultRateLimitHandler do
  @moduledoc """
  Default implementation of the RateLimitHandler behavior.

  This module provides a standard token bucket algorithm implementation for rate limiting
  WebSocket requests. It supports:

  * Configurable token bucket capacity
  * Flexible token refill rates
  * Request queueing with priority handling
  * Burst handling through token accumulation

  ## Configuration Options

  * `:mode` - Rate limiting mode (`:normal`, `:always_allow`, `:always_queue`, `:always_reject`)
  * `:capacity` - Maximum number of tokens in the bucket (default: 60)
  * `:refill_rate` - Number of tokens to add per interval (default: 1)
  * `:refill_interval` - Milliseconds between token refills (default: 1000)
  * `:queue_limit` - Maximum number of queued requests (default: 100)
  * `:cost_map` - Map of request types to their token costs (default: %{})

  ## Examples

  ```elixir
  # Initialize with custom configuration
  {:ok, state} = WebsockexNova.Defaults.DefaultRateLimitHandler.rate_limit_init(
    capacity: 100,
    refill_rate: 5,
    refill_interval: 1000,
    queue_limit: 50,
    mode: :normal,
    cost_map: %{
      subscription: 5,
      auth: 10,
      query: 1
    }
  )
  ```
  """

  @behaviour WebsockexNova.Behaviors.RateLimitHandler

  require Logger

  @default_capacity 60
  @default_refill_rate 1
  @default_refill_interval 1000
  @default_queue_limit 100
  @default_cost_map %{
    # Default costs for common request types
    subscription: 5,
    auth: 10,
    query: 1
  }

  # Define possible rate limiting modes
  @modes [:normal, :always_allow, :always_queue, :always_reject]

  @impl true
  def rate_limit_init(opts) do
    # Convert to map if passed as keyword list
    opts_map = if is_list(opts), do: Map.new(opts), else: opts

    # Extract rate limiting mode
    mode = extract_mode(opts_map)
    Logger.debug("Default rate limiter initialized with mode: #{inspect(mode)}")

    # Extract specific key used both for capacity and initial tokens
    capacity = Map.get(opts_map, :capacity, @default_capacity)

    # Allow configuring initial token count separately from capacity
    initial_tokens = Map.get(opts_map, :tokens, capacity)

    state = %{
      mode: mode,
      bucket: %{
        capacity: capacity,
        tokens: initial_tokens,
        refill_rate: Map.get(opts_map, :refill_rate, @default_refill_rate),
        refill_interval: Map.get(opts_map, :refill_interval, @default_refill_interval),
        last_refill: System.monotonic_time(:millisecond)
      },
      queue: :queue.new(),
      queue_limit: Map.get(opts_map, :queue_limit, @default_queue_limit),
      cost_map: Map.get(opts_map, :cost_map, @default_cost_map)
    }

    {:ok, state}
  end

  @impl true
  def check_rate_limit(request, state) when is_map(request) and is_map(state) do
    Logger.debug("Checking rate limit for request: #{inspect(request)}, mode: #{inspect(state.mode)}")

    case state.mode do
      :always_allow ->
        # Always allow all requests, regardless of rate limits
        {:allow, state}

      :always_queue ->
        # Always queue all requests, regardless of rate limits
        new_queue = insert_with_priority(state.queue, {request, 1})
        new_state = %{state | queue: new_queue}
        {:queue, new_state}

      :always_reject ->
        # Always reject all requests, regardless of rate limits
        {:reject, :rate_limit_exceeded, state}

      :normal ->
        # Use normal rate limiting logic
        normal_check_rate_limit(request, state)
    end
  end

  @impl true
  def handle_tick(state) when is_map(state) do
    # Logger.debug("Handling tick with mode: #{inspect(state.mode)}")

    case state.mode do
      :always_allow ->
        # No need to process queue, as all requests are allowed immediately
        {:ok, state}

      :always_reject ->
        # No need to process queue, as all requests are rejected
        {:ok, state}

      _ ->
        # Process queued requests for :normal and :always_queue modes
        # Process queued requests if we have tokens available
        updated_bucket = refill_bucket(state.bucket)
        updated_state = %{state | bucket: updated_bucket}

        process_queue(updated_state)
    end
  end

  # Private helper functions

  defp extract_mode(opts) when is_map(opts) do
    mode = Map.get(opts, :mode, :normal)

    # Validate that the mode is valid
    if mode in @modes do
      mode
    else
      Logger.warning("Invalid rate limiting mode: #{inspect(mode)}. Using :normal instead.")
      :normal
    end
  end

  defp extract_mode(_), do: :normal

  defp normal_check_rate_limit(request, state) when is_map(request) and is_map(state) do
    # Calculate available tokens since last refill
    updated_bucket = refill_bucket(state.bucket)

    # Check if we have enough tokens
    cost = calculate_cost(request, state.cost_map)

    Logger.debug("Normal rate limit check - tokens: #{updated_bucket.tokens}, cost: #{cost}")

    cond do
      updated_bucket.tokens >= cost ->
        # We have enough tokens, allow the request
        new_bucket = %{updated_bucket | tokens: updated_bucket.tokens - cost}
        new_state = %{state | bucket: new_bucket}
        {:allow, new_state}

      :queue.len(state.queue) < state.queue_limit ->
        # Queue the request for later
        new_queue = insert_with_priority(state.queue, {request, cost})
        new_state = %{state | bucket: updated_bucket, queue: new_queue}
        {:queue, new_state}

      true ->
        # Queue is full, reject the request
        {:reject, :rate_limit_exceeded, %{state | bucket: updated_bucket}}
    end
  end

  defp refill_bucket(bucket) when is_map(bucket) do
    current_time = System.monotonic_time(:millisecond)
    elapsed = current_time - bucket.last_refill
    tokens_to_add = trunc(elapsed / bucket.refill_interval * bucket.refill_rate)

    if tokens_to_add > 0 do
      %{
        bucket
        | tokens: min(bucket.capacity, bucket.tokens + tokens_to_add),
          last_refill: current_time
      }
    else
      bucket
    end
  end

  defp calculate_cost(request, cost_map) when is_map(request) and is_map(cost_map) do
    # Get cost based on request type, or default to 1
    type = Map.get(request, :type)
    Map.get(cost_map, type, 1)
  end

  defp insert_with_priority(queue, {request, cost}) when is_map(request) do
    # If the request has a priority, insert it ahead of lower priority items
    priority = Map.get(request, :priority)

    if is_nil(priority) or :queue.is_empty(queue) do
      # No priority or empty queue - just append
      :queue.in({request, cost}, queue)
    else
      # Insert based on priority (higher priorities come first)
      queue_list = :queue.to_list(queue)

      # Find the first item with lower priority
      {before_items, after_items} =
        Enum.split_while(queue_list, fn {req, _} ->
          req_priority = Map.get(req, :priority, 0)
          is_nil(req_priority) or req_priority >= priority
        end)

      # Rebuild queue with the item inserted at the right position
      :queue.from_list(before_items ++ [{request, cost}] ++ after_items)
    end
  end

  defp process_queue(state) when is_map(state) do
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
