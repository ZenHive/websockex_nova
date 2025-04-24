defmodule WebsockexNova.Defaults.DefaultRateLimitHandlerTest do
  use ExUnit.Case, async: true

  alias WebsockexNova.Defaults.DefaultRateLimitHandler

  defp get_rate_limit(conn), do: conn.rate_limit

  describe "init/1" do
    test "initializes state with default values when no options provided" do
      {:ok, conn} = DefaultRateLimitHandler.rate_limit_init([])
      rl = get_rate_limit(conn)
      assert rl.bucket.capacity == 60
      assert rl.bucket.tokens == 60
      assert rl.bucket.refill_rate == 1
      assert rl.bucket.refill_interval == 1000
      assert rl.queue_limit == 100
      assert is_map(rl.cost_map)
      assert :queue.is_queue(rl.queue)
      assert :queue.is_empty(rl.queue)
    end

    test "initializes state with custom values" do
      custom_cost_map = %{
        subscription: 10,
        auth: 20,
        query: 5
      }

      {:ok, conn} =
        DefaultRateLimitHandler.rate_limit_init(
          capacity: 100,
          refill_rate: 5,
          refill_interval: 500,
          queue_limit: 50,
          cost_map: custom_cost_map
        )

      rl = get_rate_limit(conn)
      assert rl.bucket.capacity == 100
      assert rl.bucket.tokens == 100
      assert rl.bucket.refill_rate == 5
      assert rl.bucket.refill_interval == 500
      assert rl.queue_limit == 50
      assert rl.cost_map == custom_cost_map
    end
  end

  describe "check_rate_limit/2" do
    setup do
      {:ok, conn} =
        DefaultRateLimitHandler.rate_limit_init(
          capacity: 10,
          tokens: 5,
          refill_rate: 1,
          refill_interval: 1000,
          cost_map: %{
            query: 1,
            subscription: 10,
            auth: 7
          }
        )

      {:ok, conn: conn}
    end

    test "allows request when enough tokens available", %{conn: conn} do
      request = %{type: :query, method: "test", data: nil}
      {:allow, new_conn} = DefaultRateLimitHandler.check_rate_limit(request, conn)
      assert get_rate_limit(new_conn).bucket.tokens == 4
    end

    test "queues request when not enough tokens available", %{conn: conn} do
      request = %{type: :subscription, method: "test", data: nil}
      {:queue, new_conn} = DefaultRateLimitHandler.check_rate_limit(request, conn)
      rl = get_rate_limit(new_conn)
      assert rl.bucket.tokens == 5
      assert :queue.len(rl.queue) == 1
    end

    test "rejects request when queue is full" do
      {:ok, conn} =
        DefaultRateLimitHandler.rate_limit_init(
          capacity: 10,
          tokens: 1,
          queue_limit: 1,
          cost_map: %{subscription: 10}
        )

      request1 = %{type: :subscription, method: "test1", data: nil}
      {:queue, conn_with_queue} = DefaultRateLimitHandler.check_rate_limit(request1, conn)
      request2 = %{type: :subscription, method: "test2", data: nil}
      {:reject, :rate_limit_exceeded, _new_conn} = DefaultRateLimitHandler.check_rate_limit(request2, conn_with_queue)
    end

    test "handles request priorities correctly" do
      {:ok, conn} =
        DefaultRateLimitHandler.rate_limit_init(
          capacity: 5,
          tokens: 1,
          cost_map: %{query: 3}
        )

      low_priority = %{type: :query, method: "low", priority: 1, data: nil}
      {:queue, conn1} = DefaultRateLimitHandler.check_rate_limit(low_priority, conn)
      high_priority = %{type: :query, method: "high", priority: 10, data: nil}
      {:queue, conn2} = DefaultRateLimitHandler.check_rate_limit(high_priority, conn1)
      conn_with_tokens = put_in(conn2.rate_limit.bucket.tokens, 5)
      {:process, next_request, _} = DefaultRateLimitHandler.handle_tick(conn_with_tokens)
      assert next_request.method == "high"
    end
  end

  describe "token refill" do
    test "refills tokens based on elapsed time" do
      {:ok, conn} =
        DefaultRateLimitHandler.rate_limit_init(
          capacity: 10,
          tokens: 0,
          refill_rate: 1,
          refill_interval: 50
        )

      conn = put_in(conn.rate_limit.bucket.last_refill, System.monotonic_time(:millisecond) - 200)
      request = %{type: :query, method: "test", data: nil}
      {:allow, new_conn} = DefaultRateLimitHandler.check_rate_limit(request, conn)
      assert get_rate_limit(new_conn).bucket.tokens >= 2
    end

    test "doesn't exceed capacity when refilling" do
      {:ok, conn} =
        DefaultRateLimitHandler.rate_limit_init(
          capacity: 10,
          tokens: 10,
          refill_rate: 1,
          refill_interval: 50
        )

      conn = put_in(conn.rate_limit.bucket.last_refill, System.monotonic_time(:millisecond) - 1000)
      request = %{type: :query, method: "test", data: nil}
      {:allow, new_conn} = DefaultRateLimitHandler.check_rate_limit(request, conn)
      assert get_rate_limit(new_conn).bucket.tokens == 9
    end
  end

  describe "handle_tick/1" do
    test "processes queued requests when tokens available" do
      {:ok, conn} =
        DefaultRateLimitHandler.rate_limit_init(
          capacity: 10,
          tokens: 0,
          cost_map: %{query: 3}
        )

      request = %{type: :query, method: "test", data: nil}
      {:queue, conn_with_request} = DefaultRateLimitHandler.check_rate_limit(request, conn)
      conn_with_tokens = put_in(conn_with_request.rate_limit.bucket.tokens, 5)
      {:process, processed_request, new_conn} = DefaultRateLimitHandler.handle_tick(conn_with_tokens)
      assert processed_request.method == "test"
      assert :queue.is_empty(get_rate_limit(new_conn).queue)
      assert get_rate_limit(new_conn).bucket.tokens == 2
    end

    test "returns :ok when no requests can be processed" do
      {:ok, conn} =
        DefaultRateLimitHandler.rate_limit_init(
          capacity: 10,
          tokens: 0,
          cost_map: %{subscription: 5}
        )

      request = %{type: :subscription, method: "test", data: nil}
      {:queue, conn_with_request} = DefaultRateLimitHandler.check_rate_limit(request, conn)
      conn_with_tokens = put_in(conn_with_request.rate_limit.bucket.tokens, 3)
      {:ok, new_conn} = DefaultRateLimitHandler.handle_tick(conn_with_tokens)
      assert :queue.len(get_rate_limit(new_conn).queue) == 1
    end

    test "returns :ok when queue is empty" do
      {:ok, conn} = DefaultRateLimitHandler.rate_limit_init([])
      {:ok, _new_conn} = DefaultRateLimitHandler.handle_tick(conn)
    end
  end

  describe "burst handling" do
    test "allows burst of requests up to token capacity" do
      {:ok, conn} =
        DefaultRateLimitHandler.rate_limit_init(
          capacity: 10,
          tokens: 10,
          refill_rate: 1,
          refill_interval: 1000
        )

      state_after_requests =
        Enum.reduce(1..10, conn, fn i, acc_conn ->
          request = %{type: :query, method: "test#{i}", data: nil}
          {:allow, new_conn} = DefaultRateLimitHandler.check_rate_limit(request, acc_conn)
          new_conn
        end)

      assert get_rate_limit(state_after_requests).bucket.tokens == 0
      request = %{type: :query, method: "test_overflow", data: nil}
      {:queue, final_conn} = DefaultRateLimitHandler.check_rate_limit(request, state_after_requests)
      assert :queue.len(get_rate_limit(final_conn).queue) == 1
    end
  end
end
