defmodule WebsockexNova.Defaults.DefaultRateLimitHandlerTest do
  use ExUnit.Case, async: true

  alias WebsockexNova.Defaults.DefaultRateLimitHandler

  describe "init/1" do
    test "initializes state with default values when no options provided" do
      {:ok, state} = DefaultRateLimitHandler.init([])

      assert state.bucket.capacity == 60
      assert state.bucket.tokens == 60
      assert state.bucket.refill_rate == 1
      assert state.bucket.refill_interval == 1000
      assert state.queue_limit == 100
      assert is_map(state.cost_map)
      assert :queue.is_queue(state.queue)
      assert :queue.is_empty(state.queue)
    end

    test "initializes state with custom values" do
      custom_cost_map = %{
        subscription: 10,
        auth: 20,
        query: 5
      }

      {:ok, state} =
        DefaultRateLimitHandler.init(
          capacity: 100,
          refill_rate: 5,
          refill_interval: 500,
          queue_limit: 50,
          cost_map: custom_cost_map
        )

      assert state.bucket.capacity == 100
      assert state.bucket.tokens == 100
      assert state.bucket.refill_rate == 5
      assert state.bucket.refill_interval == 500
      assert state.queue_limit == 50
      assert state.cost_map == custom_cost_map
    end
  end

  describe "check_rate_limit/2" do
    setup do
      # Create a state with a limited number of tokens for testing
      {:ok, state} =
        DefaultRateLimitHandler.init(
          capacity: 10,
          tokens: 5,
          refill_rate: 1,
          refill_interval: 1000,
          cost_map: %{
            query: 1,
            # Make sure subscription costs more than available tokens
            subscription: 10,
            auth: 7
          }
        )

      {:ok, state: state}
    end

    test "allows request when enough tokens available", %{state: state} do
      # Create a request with default cost (1)
      request = %{type: :query, method: "test", data: nil}

      # Should be allowed since we have 5 tokens
      {:allow, new_state} = DefaultRateLimitHandler.check_rate_limit(request, state)

      # Check that a token was consumed
      assert new_state.bucket.tokens == 4
    end

    test "queues request when not enough tokens available", %{state: state} do
      # Create a request with high cost (10)
      request = %{type: :subscription, method: "test", data: nil}

      # Should be queued since we only have 5 tokens
      {:queue, new_state} = DefaultRateLimitHandler.check_rate_limit(request, state)

      # Check that no tokens were consumed and request was queued
      assert new_state.bucket.tokens == 5
      assert :queue.len(new_state.queue) == 1
    end

    test "rejects request when queue is full" do
      # Create a state with a very small queue limit
      {:ok, state} =
        DefaultRateLimitHandler.init(
          capacity: 10,
          tokens: 1,
          queue_limit: 1,
          cost_map: %{
            # Make subscription cost high to ensure it's queued
            subscription: 10
          }
        )

      # Fill the queue with one request
      request1 = %{type: :subscription, method: "test1", data: nil}
      {:queue, state_with_queue} = DefaultRateLimitHandler.check_rate_limit(request1, state)

      # Try to add another request
      request2 = %{type: :subscription, method: "test2", data: nil}
      {:reject, :rate_limit_exceeded, _new_state} = DefaultRateLimitHandler.check_rate_limit(request2, state_with_queue)
    end

    test "handles request priorities correctly" do
      {:ok, state} =
        DefaultRateLimitHandler.init(
          capacity: 5,
          tokens: 1,
          cost_map: %{
            # Make query cost more than available tokens to force queueing
            query: 3
          }
        )

      # Add a low priority request
      low_priority = %{type: :query, method: "low", priority: 1, data: nil}
      {:queue, state_with_one} = DefaultRateLimitHandler.check_rate_limit(low_priority, state)

      # Add a high priority request
      high_priority = %{type: :query, method: "high", priority: 10, data: nil}
      {:queue, state_with_two} = DefaultRateLimitHandler.check_rate_limit(high_priority, state_with_one)

      # Check that high priority request is processed first (manually set tokens to enough for processing)
      state_with_tokens = put_in(state_with_two.bucket.tokens, 5)
      {:process, next_request, _} = DefaultRateLimitHandler.handle_tick(state_with_tokens)

      assert next_request.method == "high"
    end
  end

  describe "token refill" do
    test "refills tokens based on elapsed time" do
      # Set up initial state with no tokens
      {:ok, state} =
        DefaultRateLimitHandler.init(
          capacity: 10,
          tokens: 0,
          refill_rate: 1,
          # 50ms per token for faster testing
          refill_interval: 50
        )

      # Force last_refill to be in the past
      state = put_in(state.bucket.last_refill, System.monotonic_time(:millisecond) - 200)

      # This should add about 4 tokens (200ms / 50ms = 4)
      request = %{type: :query, method: "test", data: nil}
      {:allow, new_state} = DefaultRateLimitHandler.check_rate_limit(request, state)

      # Should have refilled tokens, then used 1 for the request
      assert new_state.bucket.tokens >= 2
    end

    test "doesn't exceed capacity when refilling" do
      # Set up initial state with max tokens
      {:ok, state} =
        DefaultRateLimitHandler.init(
          capacity: 10,
          tokens: 10,
          refill_rate: 1,
          refill_interval: 50
        )

      # Force last_refill to be in the past
      state = put_in(state.bucket.last_refill, System.monotonic_time(:millisecond) - 1000)

      # Check tokens after refill shouldn't exceed capacity
      request = %{type: :query, method: "test", data: nil}
      {:allow, new_state} = DefaultRateLimitHandler.check_rate_limit(request, state)

      # Should still be at capacity (10) - 1 token used = 9
      assert new_state.bucket.tokens == 9
    end
  end

  describe "handle_tick/1" do
    test "processes queued requests when tokens available" do
      # Create a state with a queued request
      {:ok, initial_state} =
        DefaultRateLimitHandler.init(
          capacity: 10,
          # Start with no tokens
          tokens: 0,
          cost_map: %{
            # Ensure cost is higher than available tokens to force queueing
            query: 3
          }
        )

      # Queue a request
      request = %{type: :query, method: "test", data: nil}
      {:queue, state_with_request} = DefaultRateLimitHandler.check_rate_limit(request, initial_state)

      # Simulate token refill
      state_with_tokens = put_in(state_with_request.bucket.tokens, 5)

      # Process the queue
      {:process, processed_request, new_state} = DefaultRateLimitHandler.handle_tick(state_with_tokens)

      # Check that the request was processed
      assert processed_request.method == "test"
      assert :queue.is_empty(new_state.queue)
      # 5 - 3 = 2
      assert new_state.bucket.tokens == 2
    end

    test "returns :ok when no requests can be processed" do
      # Create a state with a queued request but no tokens
      {:ok, initial_state} =
        DefaultRateLimitHandler.init(
          capacity: 10,
          tokens: 0,
          cost_map: %{
            # Subscription costs 5 tokens
            subscription: 5
          }
        )

      # Queue a high-cost request
      request = %{type: :subscription, method: "test", data: nil}
      {:queue, state_with_request} = DefaultRateLimitHandler.check_rate_limit(request, initial_state)

      # Try to process with insufficient tokens (need 5 for subscription)
      state_with_tokens = put_in(state_with_request.bucket.tokens, 3)

      # Should return :ok because not enough tokens
      {:ok, new_state} = DefaultRateLimitHandler.handle_tick(state_with_tokens)

      # Request should still be in queue
      assert :queue.len(new_state.queue) == 1
    end

    test "returns :ok when queue is empty" do
      {:ok, state} = DefaultRateLimitHandler.init([])

      # Should return :ok because queue is empty
      {:ok, _new_state} = DefaultRateLimitHandler.handle_tick(state)
    end
  end

  describe "burst handling" do
    test "allows burst of requests up to token capacity" do
      # Set up state with full token bucket
      {:ok, state} =
        DefaultRateLimitHandler.init(
          capacity: 10,
          tokens: 10,
          refill_rate: 1,
          refill_interval: 1000
        )

      # Create 10 requests
      state_after_requests =
        Enum.reduce(1..10, state, fn i, acc_state ->
          request = %{type: :query, method: "test#{i}", data: nil}
          {:allow, new_state} = DefaultRateLimitHandler.check_rate_limit(request, acc_state)
          new_state
        end)

      # Should have used all tokens
      assert state_after_requests.bucket.tokens == 0

      # The next request should be queued
      request = %{type: :query, method: "test_overflow", data: nil}
      {:queue, final_state} = DefaultRateLimitHandler.check_rate_limit(request, state_after_requests)

      # Check that the request was queued
      assert :queue.len(final_state.queue) == 1
    end
  end
end
