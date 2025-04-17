defmodule WebsockexNova.Defaults.DefaultErrorHandlerTest do
  use ExUnit.Case, async: true
  alias WebsockexNova.Defaults.DefaultErrorHandler

  require Logger

  describe "DefaultErrorHandler.handle_error/3" do
    test "handles connection errors" do
      error = {:connection_error, :timeout}
      context = %{attempt: 1}
      state = %{max_reconnect_attempts: 5}

      assert {:retry, delay, new_state} = DefaultErrorHandler.handle_error(error, context, state)
      assert is_integer(delay)
      assert delay > 0
      assert new_state.last_error == error
      assert new_state.error_context == context
    end

    test "handles message processing errors" do
      error = {:message_error, :invalid_format}
      context = %{message: %{"broken" => true}}
      state = %{}

      assert {:ok, new_state} = DefaultErrorHandler.handle_error(error, context, state)
      assert new_state.last_error == error
      assert new_state.error_context == context
    end

    test "handles critical errors" do
      error = {:critical_error, :connection_refused}
      context = %{host: "example.com", port: 443}
      state = %{}

      assert {:stop, :critical_error, new_state} =
               DefaultErrorHandler.handle_error(error, context, state)

      assert new_state.last_error == error
      assert new_state.error_context == context
    end
  end

  describe "DefaultErrorHandler.should_reconnect?/3" do
    test "allows reconnection for transient errors" do
      error = {:connection_error, :timeout}
      attempt = 1
      state = %{max_reconnect_attempts: 5}

      assert {true, delay} = DefaultErrorHandler.should_reconnect?(error, attempt, state)
      assert is_integer(delay)
      assert delay > 0
    end

    test "respects max reconnection attempts" do
      error = {:connection_error, :timeout}
      attempt = 6
      state = %{max_reconnect_attempts: 5}

      assert {false, _} = DefaultErrorHandler.should_reconnect?(error, attempt, state)
    end

    test "doesn't reconnect for authentication errors" do
      error = {:auth_error, :invalid_credentials}
      attempt = 1
      state = %{max_reconnect_attempts: 5}

      assert {false, _} = DefaultErrorHandler.should_reconnect?(error, attempt, state)
    end

    test "uses exponential backoff for reconnection delays" do
      error = {:connection_error, :timeout}
      state = %{max_reconnect_attempts: 10}

      {true, delay1} = DefaultErrorHandler.should_reconnect?(error, 1, state)
      {true, delay2} = DefaultErrorHandler.should_reconnect?(error, 2, state)
      {true, delay3} = DefaultErrorHandler.should_reconnect?(error, 3, state)

      assert delay2 > delay1
      assert delay3 > delay2
    end
  end

  describe "DefaultErrorHandler.log_error/3" do
    import ExUnit.CaptureLog

    test "logs errors with context" do
      error = {:connection_error, :timeout}
      context = %{host: "example.com", port: 443}
      state = %{}

      log =
        capture_log(fn ->
          assert :ok = DefaultErrorHandler.log_error(error, context, state)
        end)

      assert log =~ "WebSocket error"
      assert log =~ "connection_error"
      assert log =~ "timeout"
      assert log =~ "example.com"
    end

    test "logs critical errors with warning level" do
      error = {:critical_error, :connection_refused}
      context = %{host: "example.com", port: 443}
      state = %{}

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
