defmodule WebsockexNova.TestSupport.RateLimitHandlers do
  @moduledoc """
  Test handler modules for rate limiting tests. Each handler implements the RateLimitHandler behaviour
  and is used for various test scenarios in the rate limiting test suite.
  """

  alias WebsockexNova.Behaviors.RateLimitHandler

  defmodule TestHandler do
    @moduledoc false
    @behaviour RateLimitHandler

    @impl true
    def init(opts) do
      mode =
        cond do
          is_map(opts) and Map.has_key?(opts, :mode) -> Map.get(opts, :mode)
          is_list(opts) and Keyword.has_key?(opts, :mode) -> Keyword.get(opts, :mode)
          true -> :normal
        end

      state = if is_list(opts), do: Map.new(opts), else: opts
      state = Map.put(state, :mode, mode)
      state = Map.put_new(state, :processed_count, 0)
      state = Map.put_new(state, :queue, :queue.new())
      {:ok, state}
    end

    @impl true
    def check_rate_limit(request, state) do
      case state.mode do
        :always_allow ->
          {:allow, state}

        :always_queue ->
          new_queue = :queue.in(request, state.queue)
          {:queue, %{state | queue: new_queue}}

        :always_reject ->
          {:reject, :test_rejection, state}

        :normal ->
          case request.type do
            :allow_type ->
              {:allow, state}

            :queue_type ->
              new_queue = :queue.in(request, state.queue)
              {:queue, %{state | queue: new_queue}}

            :reject_type ->
              {:reject, :rejected_type, state}

            _ ->
              {:allow, state}
          end
      end
    end

    @impl true
    def handle_tick(state) do
      case :queue.out(state.queue) do
        {{:value, request}, new_queue} ->
          new_state = %{state | queue: new_queue, processed_count: state.processed_count + 1}
          {:process, request, new_state}

        {:empty, _} ->
          {:ok, state}
      end
    end
  end

  defmodule OverflowHandler do
    @moduledoc false
    @behaviour RateLimitHandler

    @impl true
    def init(_opts), do: {:ok, %{queue: :queue.new(), queue_limit: 1}}
    @impl true
    def check_rate_limit(_req, state) do
      if :queue.len(state.queue) < state.queue_limit do
        {:queue, %{state | queue: :queue.in(:req, state.queue)}}
      else
        {:reject, :queue_full, state}
      end
    end

    @impl true
    def handle_tick(state), do: {:ok, state}
  end

  defmodule NegativeRefillHandler do
    @moduledoc false
    @behaviour RateLimitHandler

    @impl true
    def init(_opts), do: {:ok, %{bucket: %{tokens: 1, refill_rate: -1, refill_interval: 0}}}
    @impl true
    def check_rate_limit(_req, state) do
      tokens = state.bucket.tokens + max(state.bucket.refill_rate, 0)
      if tokens > 0, do: {:allow, %{state | bucket: %{state.bucket | tokens: tokens - 1}}}, else: {:queue, state}
    end

    @impl true
    def handle_tick(state), do: {:ok, state}
  end

  defmodule UnknownTypeHandler do
    @moduledoc false
    @behaviour RateLimitHandler

    @impl true
    def init(_opts), do: {:ok, %{bucket: %{tokens: 1}, cost_map: %{}}}
    @impl true
    def check_rate_limit(req, state) do
      cost = Map.get(state.cost_map, req.type, 1)

      if state.bucket.tokens >= cost,
        do: {:allow, %{state | bucket: %{tokens: state.bucket.tokens - cost}}},
        else: {:queue, state}
    end

    @impl true
    def handle_tick(state), do: {:ok, state}
  end

  defmodule InvalidReturnHandler do
    @moduledoc false
    @behaviour RateLimitHandler

    @impl true
    def init(_opts), do: {:ok, %{}}
    @impl true
    def check_rate_limit(_req, _state), do: :unexpected
    @impl true
    def handle_tick(state), do: {:ok, state}
  end

  defmodule NeverProcessHandler do
    @moduledoc false
    @behaviour RateLimitHandler

    @impl true
    def init(_opts), do: {:ok, %{}}
    @impl true
    def check_rate_limit(_req, state), do: {:queue, state}
    @impl true
    def handle_tick(state), do: {:ok, state}
  end

  defmodule PBTestHandler do
    @moduledoc false
    @behaviour RateLimitHandler

    @impl true
    def init(opts) do
      state = %{
        bucket: %{
          capacity: opts[:capacity] || 5,
          tokens: opts[:tokens] || 5
        },
        queue: :queue.new(),
        queue_limit: opts[:queue_limit] || 3,
        processed: []
      }

      {:ok, state}
    end

    @impl true
    def check_rate_limit(request, state) do
      if state.bucket.tokens > 0 do
        {:allow,
         %{state | bucket: %{state.bucket | tokens: state.bucket.tokens - 1}, processed: state.processed ++ [request.id]}}
      else
        if :queue.len(state.queue) < state.queue_limit do
          {:queue, %{state | queue: :queue.in(request, state.queue)}}
        else
          {:reject, :queue_full, state}
        end
      end
    end

    @impl true
    def handle_tick(state) do
      case :queue.out(state.queue) do
        {{:value, request}, new_queue} ->
          new_state = %{state | queue: new_queue, processed: state.processed ++ [request.id]}
          {:process, request, new_state}

        {:empty, _} ->
          {:ok, state}
      end
    end
  end
end
