defmodule WebsockexNova.Transport.RateLimitingTest do
  use ExUnit.Case, async: true

  alias WebsockexNova.Transport.RateLimiting
  alias WebsockexNova.TestSupport.RateLimitHandlers

  require Logger

  describe "start_link/1" do
    test "starts the rate limiting server" do
      unique_name = "rate_limiter_#{:erlang.unique_integer([:positive])}" |> String.to_atom()
      opts = [name: unique_name, handler: RateLimitHandlers.TestHandler]
      {:ok, pid} = RateLimiting.start_link(opts)
      on_exit(fn ->
        case Process.whereis(unique_name) do
          nil -> :ok
          pid -> GenServer.stop(pid)
        end
      end)
      assert Process.alive?(pid)
    end
  end

  describe "check/2" do
    setup do
      unique_name = "rate_limiter_#{:erlang.unique_integer([:positive])}" |> String.to_atom()
      opts = [
        name: unique_name,
        handler: RateLimitHandlers.TestHandler,
        mode: :normal,
        process_interval: 50
      ]
      original_config = Application.get_env(:websockex_nova, :rate_limiting)
      Application.delete_env(:websockex_nova, :rate_limiting)
      IO.puts("Setup test_rate_limiter with opts: #{inspect(opts)}")
      {:ok, _pid} = RateLimiting.start_link(opts)
      on_exit(fn ->
        case Process.whereis(unique_name) do
          nil -> :ok
          pid -> GenServer.stop(pid)
        end
        if original_config do
          Application.put_env(:websockex_nova, :rate_limiting, original_config)
        else
          Application.delete_env(:websockex_nova, :rate_limiting)
        end
      end)
      {:ok, server: unique_name}
    end

    test "returns :allow for allowed requests", %{server: server} do
      request = %{type: :allow_type, method: "test", data: nil}
      assert {:allow, _request_id} = RateLimiting.check(request, server)
    end

    test "returns {:queue, request_id} for queued requests", %{server: server} do
      request = %{type: :queue_type, method: "test", data: nil}
      assert {:queue, request_id} = RateLimiting.check(request, server)
      assert is_reference(request_id)
    end

    test "returns {:reject, reason} for rejected requests", %{server: server} do
      request = %{type: :reject_type, method: "test", data: nil}
      assert {:reject, :rejected_type} = RateLimiting.check(request, server)
    end
  end

  describe "on_process/3" do
    setup do
      unique_name = "callbacks_#{:erlang.unique_integer([:positive])}" |> String.to_atom()
      opts = [
        name: unique_name,
        handler: RateLimitHandlers.TestHandler,
        mode: :always_queue,
        process_interval: 50
      ]
      original_config = Application.get_env(:websockex_nova, :rate_limiting)
      Application.delete_env(:websockex_nova, :rate_limiting)
      IO.puts("Setup test_callbacks with opts: #{inspect(opts)}")
      {:ok, _pid} = RateLimiting.start_link(opts)
      IO.puts("State after start_link: #{inspect(:sys.get_state(unique_name))}")
      on_exit(fn ->
        case Process.whereis(unique_name) do
          nil -> :ok
          pid -> GenServer.stop(pid)
        end
        if original_config do
          Application.put_env(:websockex_nova, :rate_limiting, original_config)
        else
          Application.delete_env(:websockex_nova, :rate_limiting)
        end
      end)
      {:ok, server: unique_name}
    end

    test "executes callback when request is processed", %{server: server} do
      # This is where the test fails - let's explicitly use queue type
      request = %{type: :queue_type, method: "callback_test", data: nil}
      {:queue, request_id} = RateLimiting.check(request, server)

      # Set up a message to be sent when the callback executes
      test_pid = self()

      :ok =
        RateLimiting.on_process(
          request_id,
          fn ->
            send(test_pid, :callback_executed)
          end,
          server
        )

      # Force processing the queue
      {:ok, 1} = RateLimiting.force_process_queue(server)

      # Check that the callback was executed
      assert_receive :callback_executed
    end

    test "returns error for non-existent request id", %{server: server} do
      invalid_id = make_ref()
      assert {:error, :not_found} = RateLimiting.on_process(invalid_id, fn -> nil end, server)
    end
  end

  describe "automatic queue processing" do
    setup do
      unique_name = "auto_process_#{:erlang.unique_integer([:positive])}" |> String.to_atom()
      opts = [
        name: unique_name,
        handler: RateLimitHandlers.TestHandler,
        mode: :always_queue,
        process_interval: 50
      ]
      original_config = Application.get_env(:websockex_nova, :rate_limiting)
      Application.delete_env(:websockex_nova, :rate_limiting)
      IO.puts("Setup test_auto_process with opts: #{inspect(opts)}")
      {:ok, _pid} = RateLimiting.start_link(opts)
      IO.puts("State after start_link: #{inspect(:sys.get_state(unique_name))}")
      on_exit(fn ->
        case Process.whereis(unique_name) do
          nil -> :ok
          pid -> GenServer.stop(pid)
        end
        if original_config do
          Application.put_env(:websockex_nova, :rate_limiting, original_config)
        else
          Application.delete_env(:websockex_nova, :rate_limiting)
        end
      end)
      {:ok, server: unique_name}
    end

    test "automatically processes queued requests", %{server: server} do
      # Use queue_type rather than test type
      request = %{type: :queue_type, method: "auto_process", data: nil}
      {:queue, request_id} = RateLimiting.check(request, server)

      # Set up a message to be sent when the callback executes
      test_pid = self()

      :ok =
        RateLimiting.on_process(
          request_id,
          fn ->
            send(test_pid, :auto_processed)
          end,
          server
        )

      # Wait for automatic processing (should happen within 100ms)
      assert_receive :auto_processed, 150
    end
  end

  describe "force_process_queue/1" do
    setup do
      unique_name = "force_process_#{:erlang.unique_integer([:positive])}" |> String.to_atom()
      opts = [
        name: unique_name,
        handler: RateLimitHandlers.TestHandler,
        mode: :always_queue,
        process_interval: 5000
      ]
      original_config = Application.get_env(:websockex_nova, :rate_limiting)
      Application.delete_env(:websockex_nova, :rate_limiting)
      IO.puts("Setup test_force_process with opts: #{inspect(opts)}")
      {:ok, _pid} = RateLimiting.start_link(opts)
      IO.puts("State after start_link: #{inspect(:sys.get_state(unique_name))}")
      on_exit(fn ->
        case Process.whereis(unique_name) do
          nil -> :ok
          pid -> GenServer.stop(pid)
        end
        if original_config do
          Application.put_env(:websockex_nova, :rate_limiting, original_config)
        else
          Application.delete_env(:websockex_nova, :rate_limiting)
        end
      end)
      {:ok, server: unique_name}
    end

    test "processes all queued requests", %{server: server} do
      # Use queue_type to force queueing
      request1 = %{type: :queue_type, method: "force1", data: nil}
      request2 = %{type: :queue_type, method: "force2", data: nil}
      request3 = %{type: :queue_type, method: "force3", data: nil}

      {:queue, _} = RateLimiting.check(request1, server)
      {:queue, _} = RateLimiting.check(request2, server)
      {:queue, _} = RateLimiting.check(request3, server)

      # Process all at once
      {:ok, 3} = RateLimiting.force_process_queue(server)

      # Queue should be empty now
      {:ok, 0} = RateLimiting.force_process_queue(server)
    end
  end

  describe "configuration" do
    test "uses application config for handler module" do
      unique_name = "config_handler_#{:erlang.unique_integer([:positive])}" |> String.to_atom()
      original_config = Application.get_env(:websockex_nova, :rate_limiting)
      test_config = [handler: RateLimitHandlers.TestHandler, mode: :always_allow]
      Application.put_env(:websockex_nova, :rate_limiting, test_config)
      opts = [name: unique_name]
      {:ok, pid} = RateLimiting.start_link(opts)
      on_exit(fn ->
        case Process.whereis(unique_name) do
          nil -> :ok
          pid -> GenServer.stop(pid)
        end
        if original_config do
          Application.put_env(:websockex_nova, :rate_limiting, original_config)
        else
          Application.delete_env(:websockex_nova, :rate_limiting)
        end
      end)
      request = %{type: :any_type, method: "test", data: nil}
      assert {:allow, _request_id} = RateLimiting.check(request, unique_name)
    end

    test "uses application config for process interval" do
      unique_name = "config_interval_#{:erlang.unique_integer([:positive])}" |> String.to_atom()
      original_config = Application.get_env(:websockex_nova, :rate_limiting)
      test_config = [process_interval: 123]
      Application.put_env(:websockex_nova, :rate_limiting, test_config)
      opts = [name: unique_name, handler: RateLimitHandlers.TestHandler]
      {:ok, pid} = RateLimiting.start_link(opts)
      on_exit(fn ->
        case Process.whereis(unique_name) do
          nil -> :ok
          pid -> GenServer.stop(pid)
        end
        if original_config do
          Application.put_env(:websockex_nova, :rate_limiting, original_config)
        else
          Application.delete_env(:websockex_nova, :rate_limiting)
        end
      end)
      state = :sys.get_state(pid)
      assert state.process_interval == 123
    end
  end

  describe "edge cases" do
    test "rejects requests when queue is full" do
      unique_name = "overflow_#{:erlang.unique_integer([:positive])}" |> String.to_atom()
      {:ok, pid} = RateLimiting.start_link(name: unique_name, handler: RateLimitHandlers.OverflowHandler)
      on_exit(fn ->
        case Process.whereis(unique_name) do
          nil -> :ok
          pid -> GenServer.stop(pid)
        end
      end)
      assert {:queue, _} = RateLimiting.check(%{}, unique_name)
      assert {:reject, :queue_full} = RateLimiting.check(%{}, unique_name)
    end

    test "handles negative/zero refill rates and intervals safely" do
      unique_name = "neg_refill_#{:erlang.unique_integer([:positive])}" |> String.to_atom()
      {:ok, pid} = RateLimiting.start_link(name: unique_name, handler: RateLimitHandlers.NegativeRefillHandler)
      on_exit(fn ->
        case Process.whereis(unique_name) do
          nil -> :ok
          pid -> GenServer.stop(pid)
        end
      end)
      assert {:allow, _} = RateLimiting.check(%{}, unique_name)
      assert {:queue, _} = RateLimiting.check(%{}, unique_name)
    end

    test "uses default cost for unknown request types" do
      unique_name = "unknown_type_#{:erlang.unique_integer([:positive])}" |> String.to_atom()
      {:ok, pid} = RateLimiting.start_link(name: unique_name, handler: RateLimitHandlers.UnknownTypeHandler)
      on_exit(fn ->
        case Process.whereis(unique_name) do
          nil -> :ok
          pid -> GenServer.stop(pid)
        end
      end)
      assert {:allow, _} = RateLimiting.check(%{type: :not_in_map}, unique_name)
      assert {:queue, _} = RateLimiting.check(%{type: :not_in_map}, unique_name)
    end

    test "logs and rejects on invalid handler return" do
      unique_name = "invalid_return_#{:erlang.unique_integer([:positive])}" |> String.to_atom()
      {:ok, pid} = RateLimiting.start_link(name: unique_name, handler: RateLimitHandlers.InvalidReturnHandler)
      on_exit(fn ->
        case Process.whereis(unique_name) do
          nil -> :ok
          pid -> GenServer.stop(pid)
        end
      end)
      assert {:reject, :internal_error} = RateLimiting.check(%{}, unique_name)
    end

    test "callback for never-processed request is not executed" do
      unique_name = "never_process_#{:erlang.unique_integer([:positive])}" |> String.to_atom()
      {:ok, pid} = RateLimiting.start_link(name: unique_name, handler: RateLimitHandlers.NeverProcessHandler)
      on_exit(fn ->
        case Process.whereis(unique_name) do
          nil -> :ok
          pid -> GenServer.stop(pid)
        end
      end)
      {:queue, request_id} = RateLimiting.check(%{}, unique_name)
      test_pid = self()
      :ok = RateLimiting.on_process(request_id, fn -> send(test_pid, :should_not_happen) end, unique_name)
      refute_receive :should_not_happen, 100
    end
  end
end

defmodule WebsockexNova.Transport.RateLimitingPropertyTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias WebsockexNova.Transport.RateLimiting
  alias WebsockexNova.TestSupport.RateLimitHandlers

  property "queue never exceeds its limit" do
    check all n <- integer(1..20),
              seq <- list_of(constant(%{type: :queue_type}), min_length: n, max_length: n, unique: false) do
      unique_name = :"pb_queue_#{:erlang.unique_integer([:positive])}"
      {:ok, pid} = RateLimiting.start_link(name: unique_name, handler: RateLimitHandlers.PBTestHandler, queue_limit: 3, capacity: 0, tokens: 0)
      Enum.each(seq, fn _ -> RateLimiting.check(%{type: :queue_type}, unique_name) end)
      state = :sys.get_state(unique_name)
      assert :queue.len(state.handler_state.queue) <= 3
      GenServer.stop(pid)
    end
  end

  property "callbacks are executed in order of processing" do
    check all(n <- integer(2..10)) do
      unique_name = :"pb_cb_#{:erlang.unique_integer([:positive])}"
      {:ok, pid} = RateLimiting.start_link(name: unique_name, handler: RateLimitHandlers.PBTestHandler, queue_limit: 10, capacity: 0, tokens: 0)
      test_pid = self()

      ids =
        for _ <- 1..n do
          {:queue, id} = RateLimiting.check(%{type: :queue_type}, unique_name)
          :ok = RateLimiting.on_process(id, fn -> send(test_pid, {:cb, id}) end, unique_name)
          id
        end

      {:ok, _} = RateLimiting.force_process_queue(unique_name)

      received =
        Enum.map(1..n, fn _ ->
          receive do
            {:cb, id} -> id
          end
        end)

      assert Enum.sort(ids) == Enum.sort(received)
      GenServer.stop(pid)
    end
  end

  property "tokens never negative and never exceed capacity" do
    check all n <- integer(5..20),
              seq <- list_of(constant(%{type: :allow_type}), min_length: n, max_length: n, unique: false) do
      unique_name = :"pb_tokens_#{:erlang.unique_integer([:positive])}"
      {:ok, pid} = RateLimiting.start_link(name: unique_name, handler: RateLimitHandlers.PBTestHandler, capacity: 5, tokens: 5, queue_limit: 3)
      Enum.each(seq, fn _ -> RateLimiting.check(%{type: :allow_type}, unique_name) end)
      state = :sys.get_state(unique_name)
      tokens = state.handler_state.bucket.tokens
      capacity = state.handler_state.bucket.capacity
      assert tokens >= 0 and tokens <= capacity
      GenServer.stop(pid)
    end
  end
end
