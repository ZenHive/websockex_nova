defmodule WebsockexNova.Behaviors.ErrorHandlerTest do
  use ExUnit.Case, async: true

  # Define a mock module that implements the ErrorHandler behavior
  defmodule MockErrorHandler do
    @moduledoc false
    @behaviour WebsockexNova.Behaviors.ErrorHandler

    def error_init(opts) do
      send(opts[:test_pid], {:error_init, opts})
      {:ok, opts}
    end

    def handle_error(:connection_closed, _context, state) do
      send(self(), {:handle_error, :connection_closed})
      {:reconnect, state}
    end

    def handle_error(:auth_failed, _context, state) do
      send(self(), {:handle_error, :auth_failed})
      {:retry, 1000, Map.put(state, :auth_retries, Map.get(state, :auth_retries, 0) + 1)}
    end

    def handle_error(:critical_error, _context, state) do
      send(self(), {:handle_error, :critical_error})
      {:stop, :critical_error, state}
    end

    def handle_error(error, _context, state) do
      send(self(), {:handle_error, :generic, error})
      {:ok, state}
    end

    def should_reconnect?(:temporary_error, _attempt, _state) do
      {true, 1000}
    end

    def should_reconnect?(:persistent_error, attempt, _state) do
      max_delay = min(30_000, 1000 * :math.pow(2, attempt))
      {true, round(max_delay)}
    end

    def should_reconnect?(:fatal_error, _attempt, _state) do
      {false, nil}
    end

    def should_reconnect?(_error, attempt, _state) when attempt > 10 do
      {false, nil}
    end

    def should_reconnect?(_error, _attempt, _state) do
      {true, 5000}
    end

    def log_error(:connection_error, %{reason: reason}, _state) do
      send(self(), {:log_error, :connection_error, reason})
    end

    def log_error(:message_error, %{message: message}, _state) do
      send(self(), {:log_error, :message_error, message})
    end

    def log_error(error_type, context, _state) do
      send(self(), {:log_error, error_type, context})
    end
  end

  describe "ErrorHandler behavior" do
    setup do
      {:ok, state: %{test: true}}
    end

    test "handle_error/3 handles connection closure", %{state: state} do
      assert {:reconnect, ^state} = MockErrorHandler.handle_error(:connection_closed, %{}, state)
      assert_received {:handle_error, :connection_closed}
    end

    test "handle_error/3 handles authentication failure", %{state: state} do
      expected_state = Map.put(state, :auth_retries, 1)

      assert {:retry, 1000, ^expected_state} =
               MockErrorHandler.handle_error(:auth_failed, %{}, state)

      assert_received {:handle_error, :auth_failed}
    end

    test "handle_error/3 handles critical errors", %{state: state} do
      assert {:stop, :critical_error, ^state} =
               MockErrorHandler.handle_error(:critical_error, %{}, state)

      assert_received {:handle_error, :critical_error}
    end

    test "handle_error/3 handles generic errors", %{state: state} do
      error = %{code: 123, message: "Unknown error"}
      assert {:ok, ^state} = MockErrorHandler.handle_error(error, %{}, state)
      assert_received {:handle_error, :generic, ^error}
    end

    test "should_reconnect?/3 for temporary errors" do
      assert {true, 1000} = MockErrorHandler.should_reconnect?(:temporary_error, 1, %{})
    end

    test "should_reconnect?/3 for persistent errors with exponential backoff" do
      assert {true, 2000} = MockErrorHandler.should_reconnect?(:persistent_error, 1, %{})
      assert {true, 4000} = MockErrorHandler.should_reconnect?(:persistent_error, 2, %{})
      assert {true, 8000} = MockErrorHandler.should_reconnect?(:persistent_error, 3, %{})
    end

    test "should_reconnect?/3 for fatal errors" do
      assert {false, nil} = MockErrorHandler.should_reconnect?(:fatal_error, 1, %{})
    end

    test "should_reconnect?/3 exceeding max attempts" do
      assert {false, nil} = MockErrorHandler.should_reconnect?(:any_error, 11, %{})
    end

    test "should_reconnect?/3 for other errors" do
      assert {true, 5000} = MockErrorHandler.should_reconnect?(:other_error, 1, %{})
    end

    test "log_error/3 for connection errors" do
      reason = {:remote, 1000, "Normal closure"}
      MockErrorHandler.log_error(:connection_error, %{reason: reason}, %{})
      assert_received {:log_error, :connection_error, ^reason}
    end

    test "log_error/3 for message errors" do
      message = %{"error" => "Invalid message format"}
      MockErrorHandler.log_error(:message_error, %{message: message}, %{})
      assert_received {:log_error, :message_error, ^message}
    end

    test "log_error/3 for generic errors" do
      context = %{module: "TestModule", function: "test_function"}
      MockErrorHandler.log_error(:generic_error, context, %{})
      assert_received {:log_error, :generic_error, ^context}
    end
  end
end
