defmodule WebsockexNova.Behaviours.LoggingHandlerTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias WebsockexNova.ClientConn
  alias WebsockexNova.Defaults.DefaultLoggingHandler

  defp conn_with_logging(logging), do: %ClientConn{logging: logging}
  defp default_state, do: conn_with_logging(%{})
  defp json_state, do: conn_with_logging(%{log_level: :info, log_format: :json})
  defp warn_state, do: conn_with_logging(%{log_level: :warning, log_format: :plain})

  describe "log_connection_event/3" do
    setup do
      old_level = Logger.level()
      Logger.configure(level: :debug)
      on_exit(fn -> Logger.configure(level: old_level) end)
      :ok
    end

    test "logs plain format by default" do
      log =
        capture_log(fn ->
          DefaultLoggingHandler.log_connection_event(:connected, %{host: "localhost"}, default_state())
        end)

      assert log =~ "[CONNECTION]"
      assert log =~ "type: :connected"
      assert log =~ "host: \"localhost\""
    end

    test "logs in JSON format when configured" do
      log =
        capture_log(fn ->
          DefaultLoggingHandler.log_connection_event(:disconnected, %{reason: :timeout}, json_state())
        end)

      assert log =~ "\"category\":"
      assert log =~ "\"type\":"
      assert log =~ "disconnected"
      assert log =~ "timeout"
    end
  end

  describe "log_message_event/3" do
    setup do
      old_level = Logger.level()
      Logger.configure(level: :debug)
      on_exit(fn -> Logger.configure(level: old_level) end)
      :ok
    end

    test "logs message events at info level by default" do
      log =
        capture_log(fn ->
          DefaultLoggingHandler.log_message_event(:sent, %{payload: "hi"}, default_state())
        end)

      assert log =~ "[MESSAGE]"
      assert log =~ "type: :sent"
      assert log =~ "payload: \"hi\""
    end

    test "logs at warn level when configured" do
      log =
        capture_log(fn ->
          DefaultLoggingHandler.log_message_event(:received, %{payload: "pong"}, warn_state())
        end)

      assert log =~ "[MESSAGE]"
      assert log =~ "type: :received"
      assert log =~ "payload: \"pong\""
    end
  end

  describe "log_error_event/3" do
    setup do
      old_level = Logger.level()
      Logger.configure(level: :debug)
      on_exit(fn -> Logger.configure(level: old_level) end)
      :ok
    end

    test "logs error events at info level by default" do
      log =
        capture_log(fn ->
          DefaultLoggingHandler.log_error_event(:ws_error, %{code: 1006, reason: "abnormal"}, default_state())
        end)

      assert log =~ "[ERROR]"
      assert log =~ "type: :ws_error"
      assert log =~ "code: 1006"
      assert log =~ "reason: \"abnormal\""
    end

    test "logs error events in JSON format" do
      log =
        capture_log(fn ->
          DefaultLoggingHandler.log_error_event(:ws_error, %{code: 1001, reason: "going away"}, json_state())
        end)

      assert log =~ "\"category\":"
      assert log =~ "\"type\":"
      assert log =~ "ws_error"
      assert log =~ "going away"
    end
  end

  describe "edge cases" do
    setup do
      old_level = Logger.level()
      Logger.configure(level: :debug)
      on_exit(fn -> Logger.configure(level: old_level) end)
      :ok
    end

    test "handles unknown log format gracefully" do
      state = conn_with_logging(%{log_format: :unknown})

      log =
        capture_log(fn ->
          DefaultLoggingHandler.log_connection_event(:foo, %{bar: 1}, state)
        end)

      assert log =~ "[LOG]["
      assert log =~ "type: :foo"
      assert log =~ "bar: 1"
    end

    test "handles invalid log level by falling back to :info" do
      state = conn_with_logging(%{log_level: :notalevel})

      log =
        capture_log(fn ->
          DefaultLoggingHandler.log_message_event(:foo, %{bar: 2}, state)
        end)

      assert log =~ "[MESSAGE]"
      assert log =~ "type: :foo"
      assert log =~ "bar: 2"
    end
  end

  # Add a custom handler integration test
  defmodule TestHandler do
    @moduledoc false
    @behaviour WebsockexNova.Behaviours.LoggingHandler

    def log_connection_event(event, context, _state), do: send(self(), {:log, :connection, event, context})
    def log_message_event(event, context, _state), do: send(self(), {:log, :message, event, context})
    def log_error_event(event, context, _state), do: send(self(), {:log, :error, event, context})
  end

  describe "custom handler integration" do
    test "custom handler sends log events as messages" do
      state = %{logging_handler: TestHandler}
      TestHandler.log_connection_event(:foo, %{bar: 1}, state)
      assert_receive {:log, :connection, :foo, %{bar: 1}}

      TestHandler.log_message_event(:bar, %{baz: 2}, state)
      assert_receive {:log, :message, :bar, %{baz: 2}}

      TestHandler.log_error_event(:err, %{reason: :fail}, state)
      assert_receive {:log, :error, :err, %{reason: :fail}}
    end
  end
end
