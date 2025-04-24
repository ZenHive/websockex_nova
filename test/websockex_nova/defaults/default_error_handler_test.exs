defmodule WebsockexNova.Defaults.DefaultErrorHandlerTest do
  use ExUnit.Case, async: true

  alias WebsockexNova.ClientConn
  alias WebsockexNova.Defaults.DefaultErrorHandler

  require Logger

  describe "DefaultErrorHandler.handle_error/3" do
    test "handles connection errors and uses attempt from state" do
      error = {:connection_error, :timeout}
      context = %{}
      state = %ClientConn{reconnection: %{max_reconnect_attempts: 5}, reconnect_attempts: 3}

      assert {:retry, delay, new_state} = DefaultErrorHandler.handle_error(error, context, state)
      assert is_integer(delay)
      assert delay > 0
      assert new_state.last_error == error
      assert new_state.error_context == context
    end

    test "handles message processing errors" do
      error = {:message_error, :invalid_format}
      context = %{message: %{"broken" => true}}
      state = %ClientConn{}

      assert {:ok, new_state} = DefaultErrorHandler.handle_error(error, context, state)
      assert new_state.last_error == error
      assert new_state.error_context == context
    end

    test "handles critical errors" do
      error = {:critical_error, :connection_refused}
      context = %{host: "example.com", port: 443}
      state = %ClientConn{}

      assert {:stop, :critical_error, new_state} =
               DefaultErrorHandler.handle_error(error, context, state)

      assert new_state.last_error == error
      assert new_state.error_context == context
    end
  end

  describe "DefaultErrorHandler.should_reconnect?/3" do
    test "allows reconnection for transient errors using attempt from state" do
      error = {:connection_error, :timeout}
      state = %ClientConn{reconnection: %{max_reconnect_attempts: 5}, reconnect_attempts: 2}

      assert {true, delay} = DefaultErrorHandler.should_reconnect?(error, 999, state)
      assert is_integer(delay)
      assert delay > 0
    end

    test "respects max reconnection attempts from state" do
      error = {:connection_error, :timeout}
      state = %ClientConn{reconnection: %{max_reconnect_attempts: 5}, reconnect_attempts: 6}

      assert {false, _} = DefaultErrorHandler.should_reconnect?(error, 1, state)
    end

    test "doesn't reconnect for authentication errors" do
      error = {:auth_error, :invalid_credentials}
      state = %ClientConn{reconnection: %{max_reconnect_attempts: 5}, reconnect_attempts: 1}

      assert {false, _} = DefaultErrorHandler.should_reconnect?(error, 1, state)
    end

    test "uses exponential backoff for reconnection delays" do
      error = {:connection_error, :timeout}
      state = %ClientConn{reconnection: %{max_reconnect_attempts: 10}, reconnect_attempts: 1}

      {true, delay1} = DefaultErrorHandler.should_reconnect?(error, 0, %{state | reconnect_attempts: 1})
      {true, delay2} = DefaultErrorHandler.should_reconnect?(error, 0, %{state | reconnect_attempts: 2})
      {true, delay3} = DefaultErrorHandler.should_reconnect?(error, 0, %{state | reconnect_attempts: 3})

      assert delay2 > delay1
      assert delay3 > delay2
    end
  end

  describe "DefaultErrorHandler.increment_reconnect_attempts/1 and reset_reconnect_attempts/1" do
    test "increments the attempt count in state" do
      state = %ClientConn{reconnect_attempts: 2}
      new_state = DefaultErrorHandler.increment_reconnect_attempts(state)
      assert new_state.reconnect_attempts == 3
    end

    test "increments from default if not present" do
      state = %ClientConn{}
      new_state = DefaultErrorHandler.increment_reconnect_attempts(state)
      assert new_state.reconnect_attempts == 1
    end

    test "resets the attempt count in state" do
      state = %ClientConn{reconnect_attempts: 5}
      new_state = DefaultErrorHandler.reset_reconnect_attempts(state)
      assert new_state.reconnect_attempts == 1
    end
  end

  describe "DefaultErrorHandler.log_error/3" do
    import ExUnit.CaptureLog

    @tag :skip
    test "logs errors with context" do
      error = {:connection_error, :timeout}
      context = %{host: "example.com", port: 443}
      state = %ClientConn{}

      log =
        capture_log(fn ->
          assert :ok = DefaultErrorHandler.log_error(error, context, state)
        end)

      assert log =~ "WebSocket error"
      assert log =~ "connection_error"
      assert log =~ "timeout"
      assert log =~ "example.com"
    end

    @tag :skip
    test "logs critical errors with warning level" do
      error = {:critical_error, :connection_refused}
      context = %{host: "example.com", port: 443}
      state = %ClientConn{}

      log =
        capture_log(fn ->
          assert :ok = DefaultErrorHandler.log_error(error, context, state)
        end)

      assert log =~ "CRITICAL WebSocket error"
      assert log =~ "connection_refused"
    end
  end

  describe "DefaultErrorHandler.classify_error/2" do
    test "classifies connection errors as transient" do
      error = {:connection_error, :timeout}
      context = %{attempt: 1}

      assert DefaultErrorHandler.classify_error(error, context) == :transient
    end

    test "classifies authentication errors as critical" do
      error = {:auth_error, :invalid_credentials}
      context = %{attempt: 1}

      assert DefaultErrorHandler.classify_error(error, context) == :critical
    end

    test "classifies message errors as normal" do
      error = {:message_error, :invalid_format}
      context = %{message: %{"broken" => true}}

      assert DefaultErrorHandler.classify_error(error, context) == :normal
    end

    test "treats unknown errors as transient" do
      error = {:unknown_error, :something_happened}
      context = %{}

      assert DefaultErrorHandler.classify_error(error, context) == :transient
    end
  end
end
