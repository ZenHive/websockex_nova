defmodule WebsockexNova.Transport.RateLimitingTest do
  use ExUnit.Case, async: false

  alias WebsockexNova.Transport.RateLimiting

  require Logger

  # Define a test handler for testing with predictable behavior
  defmodule TestHandler do
    @moduledoc false
    @behaviour WebsockexNova.Behaviors.RateLimitHandler

    @impl true
    def init(opts) do
      # Debug the options
      IO.puts("TestHandler.init with opts: #{inspect(opts)}")

      # We need to make sure the mode gets properly set from either
      # the opts or the handle state, since there are different ways
      # the options can be passed
      mode =
        cond do
          is_map(opts) and Map.has_key?(opts, :mode) -> Map.get(opts, :mode)
          is_list(opts) and Keyword.has_key?(opts, :mode) -> Keyword.get(opts, :mode)
          true -> :normal
        end

      IO.puts("Selected mode: #{inspect(mode)}")

      # Convert to a map if it's a keyword list
      state = if is_list(opts), do: Map.new(opts), else: opts

      # Make sure we set the mode explicitly
      state = Map.put(state, :mode, mode)
      state = Map.put_new(state, :processed_count, 0)
      state = Map.put_new(state, :queue, :queue.new())

      {:ok, state}
    end

    @impl true
    def check_rate_limit(request, state) do
      # Debug
      IO.puts("check_rate_limit with mode: #{inspect(state.mode)}")

      case state.mode do
        :always_allow ->
          IO.puts("Mode is :always_allow -> returning :allow")
          {:allow, state}

        :always_queue ->
          IO.puts("Mode is :always_queue -> returning :queue")
          new_queue = :queue.in(request, state.queue)
          {:queue, %{state | queue: new_queue}}

        :always_reject ->
          IO.puts("Mode is :always_reject -> returning :reject")
          {:reject, :test_rejection, state}

        :normal ->
          # Normal mode: allow some types, queue others based on type
          IO.puts("Mode is :normal, checking request type: #{inspect(request.type)}")

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
      # Debug
      IO.puts("handle_tick with state: #{inspect(state)}")

      case :queue.out(state.queue) do
        {{:value, request}, new_queue} ->
          # Process one request
          new_state = %{
            state
            | queue: new_queue,
              processed_count: state.processed_count + 1
          }

          {:process, request, new_state}

        {:empty, _} ->
          {:ok, state}
      end
    end
  end

  describe "start_link/1" do
    test "starts the rate limiting server" do
      opts = [name: :test_rate_limiter, handler: TestHandler]
      {:ok, pid} = RateLimiting.start_link(opts)
      assert Process.alive?(pid)

      # Cleanup
      GenServer.stop(pid)
    end
  end

  describe "check/2" do
    setup do
      # Start a rate limiter with our test handler in normal mode
      opts = [
        name: :test_rate_limiter,
        handler: TestHandler,
        mode: :normal,
        process_interval: 50
      ]

      # Clean the application env for testing
      original_config = Application.get_env(:websockex_nova, :rate_limiting)
      Application.delete_env(:websockex_nova, :rate_limiting)

      # Print the options we're using
      IO.puts("Setup test_rate_limiter with opts: #{inspect(opts)}")

      {:ok, _pid} = RateLimiting.start_link(opts)

      on_exit(fn ->
        # Cleanup
        try do
          GenServer.stop(:test_rate_limiter)
        catch
          :exit, _ -> :ok
        end

        # Restore original config
        if original_config do
          Application.put_env(:websockex_nova, :rate_limiting, original_config)
        else
          Application.delete_env(:websockex_nova, :rate_limiting)
        end
      end)

      {:ok, server: :test_rate_limiter}
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
      # Force always_queue mode to ensure predictable behavior
      opts = [
        name: :test_callbacks,
        handler: TestHandler,
        mode: :always_queue,
        process_interval: 50
      ]

      # Clean the application env for testing
      original_config = Application.get_env(:websockex_nova, :rate_limiting)
      Application.delete_env(:websockex_nova, :rate_limiting)

      # Print the options we're using
      IO.puts("Setup test_callbacks with opts: #{inspect(opts)}")

      {:ok, _pid} = RateLimiting.start_link(opts)

      # Debug the state
      IO.puts("State after start_link: #{inspect(:sys.get_state(:test_callbacks))}")

      on_exit(fn ->
        # Cleanup
        try do
          GenServer.stop(:test_callbacks)
        catch
          :exit, _ -> :ok
        end

        # Restore original config
        if original_config do
          Application.put_env(:websockex_nova, :rate_limiting, original_config)
        else
          Application.delete_env(:websockex_nova, :rate_limiting)
        end
      end)

      {:ok, server: :test_callbacks}
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
      # Use a short process interval for faster tests
      # Force always_queue mode to ensure predictable behavior
      opts = [
        name: :test_auto_process,
        handler: TestHandler,
        mode: :always_queue,
        process_interval: 50
      ]

      # Clean the application env for testing
      original_config = Application.get_env(:websockex_nova, :rate_limiting)
      Application.delete_env(:websockex_nova, :rate_limiting)

      # Print the options we're using
      IO.puts("Setup test_auto_process with opts: #{inspect(opts)}")

      {:ok, _pid} = RateLimiting.start_link(opts)

      # Debug the state
      IO.puts("State after start_link: #{inspect(:sys.get_state(:test_auto_process))}")

      on_exit(fn ->
        # Cleanup
        try do
          GenServer.stop(:test_auto_process)
        catch
          :exit, _ -> :ok
        end

        # Restore original config
        if original_config do
          Application.put_env(:websockex_nova, :rate_limiting, original_config)
        else
          Application.delete_env(:websockex_nova, :rate_limiting)
        end
      end)

      {:ok, server: :test_auto_process}
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
      # Use a long process interval and force always_queue mode
      opts = [
        name: :test_force_process,
        handler: TestHandler,
        mode: :always_queue,
        # Long interval so auto-processing doesn't interfere
        process_interval: 5000
      ]

      # Clean the application env for testing
      original_config = Application.get_env(:websockex_nova, :rate_limiting)
      Application.delete_env(:websockex_nova, :rate_limiting)

      # Print the options we're using
      IO.puts("Setup test_force_process with opts: #{inspect(opts)}")

      {:ok, _pid} = RateLimiting.start_link(opts)

      # Debug the state
      IO.puts("State after start_link: #{inspect(:sys.get_state(:test_force_process))}")

      on_exit(fn ->
        # Cleanup
        try do
          GenServer.stop(:test_force_process)
        catch
          :exit, _ -> :ok
        end

        # Restore original config
        if original_config do
          Application.put_env(:websockex_nova, :rate_limiting, original_config)
        else
          Application.delete_env(:websockex_nova, :rate_limiting)
        end
      end)

      {:ok, server: :test_force_process}
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
      # Set application config
      original_config = Application.get_env(:websockex_nova, :rate_limiting)

      # Configure to use our test handler in always_allow mode
      test_config = [handler: TestHandler, mode: :always_allow]
      Application.put_env(:websockex_nova, :rate_limiting, test_config)

      opts = [name: :test_config_handler]
      {:ok, pid} = RateLimiting.start_link(opts)

      # Check that it's using our handler in always_allow mode
      request = %{type: :any_type, method: "test", data: nil}
      assert {:allow, _request_id} = RateLimiting.check(request, :test_config_handler)

      # Cleanup
      GenServer.stop(pid)

      # Restore original config
      if original_config do
        Application.put_env(:websockex_nova, :rate_limiting, original_config)
      else
        Application.delete_env(:websockex_nova, :rate_limiting)
      end
    end

    test "uses application config for process interval" do
      # Set application config
      original_config = Application.get_env(:websockex_nova, :rate_limiting)

      # Use a distinctive interval
      test_config = [process_interval: 123]
      Application.put_env(:websockex_nova, :rate_limiting, test_config)

      opts = [name: :test_config_interval, handler: TestHandler]
      {:ok, pid} = RateLimiting.start_link(opts)

      # Inspect server state to check the process interval
      state = :sys.get_state(pid)
      assert state.process_interval == 123

      # Cleanup
      GenServer.stop(pid)

      # Restore original config
      if original_config do
        Application.put_env(:websockex_nova, :rate_limiting, original_config)
      else
        Application.delete_env(:websockex_nova, :rate_limiting)
      end
    end
  end
end
