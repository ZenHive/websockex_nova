defmodule WebsockexNova.Behaviours.RateLimitHandlerTest do
  use ExUnit.Case, async: true

  alias WebsockexNova.Behaviours.RateLimitHandler

  # Define a test implementation that just wraps the behavior for testing
  defmodule TestRateLimitHandler do
    @moduledoc false
    @behaviour WebsockexNova.Behaviours.RateLimitHandler

    @impl true
    def rate_limit_init(opts) do
      {:ok, opts}
    end

    @impl true
    def check_rate_limit(request, state) do
      case request.type do
        :test_allow -> {:allow, state}
        :test_queue -> {:queue, state}
        :test_reject -> {:reject, :test_reason, state}
      end
    end

    @impl true
    def handle_tick(state) do
      if state[:process_request] do
        request = %{type: :test_process, method: "test", data: nil}
        {:process, request, state}
      else
        {:ok, state}
      end
    end
  end

  describe "behavior definition" do
    test "defines required callbacks" do
      # We can verify that our test implementation correctly implements the behavior
      # If it implements it successfully with @impl true, then the callbacks exist
      assert {:module, TestRateLimitHandler} = Code.ensure_loaded(TestRateLimitHandler)

      # Directly check for callbacks in the behavior module
      callbacks = RateLimitHandler.behaviour_info(:callbacks)
      assert Enum.member?(callbacks, {:rate_limit_init, 1})
      assert Enum.member?(callbacks, {:check_rate_limit, 2})
    end

    test "handle_tick is optional" do
      callbacks = RateLimitHandler.behaviour_info(:optional_callbacks)
      assert Enum.member?(callbacks, {:handle_tick, 1})
    end
  end

  describe "TestRateLimitHandler implementation" do
    test "rate_limit_init/1 returns state" do
      assert {:ok, %{test: :value}} = TestRateLimitHandler.rate_limit_init(%{test: :value})
    end

    test "check_rate_limit/2 returns :allow for allowed requests" do
      request = %{type: :test_allow, method: "test", data: nil}
      state = %{test: :state}
      assert {:allow, %{test: :state}} = TestRateLimitHandler.check_rate_limit(request, state)
    end

    test "check_rate_limit/2 returns :queue for queued requests" do
      request = %{type: :test_queue, method: "test", data: nil}
      state = %{test: :state}
      assert {:queue, %{test: :state}} = TestRateLimitHandler.check_rate_limit(request, state)
    end

    test "check_rate_limit/2 returns :reject for rejected requests" do
      request = %{type: :test_reject, method: "test", data: nil}
      state = %{test: :state}

      assert {:reject, :test_reason, %{test: :state}} =
               TestRateLimitHandler.check_rate_limit(request, state)
    end

    test "handle_tick/1 processes queued requests" do
      state = %{process_request: true}
      assert {:process, %{type: :test_process}, ^state} = TestRateLimitHandler.handle_tick(state)
    end

    test "handle_tick/1 returns ok when no requests to process" do
      state = %{process_request: false}
      assert {:ok, ^state} = TestRateLimitHandler.handle_tick(state)
    end
  end
end
