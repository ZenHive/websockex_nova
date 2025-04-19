defmodule WebsockexNova.Behaviors.LoggingHandlerTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias WebsockexNova.Defaults.DefaultLoggingHandler

  @default_state %{}
  @json_state %{log_level: :info, log_format: :json}
  @warn_state %{log_level: :warn, log_format: :plain}

  describe "log_connection_event/3" do
    test "logs plain format by default" do
      log =
        capture_log(fn ->
          DefaultLoggingHandler.log_connection_event(:connected, %{host: "localhost"}, @default_state)
        end)

      assert log =~ "[CONNECTION] :connected"
      assert log =~ "host: \"localhost\""
    end

    test "logs in JSON format when configured" do
      log =
        capture_log(fn ->
          DefaultLoggingHandler.log_connection_event(:disconnected, %{reason: :timeout}, @json_state)
        end)

      assert log =~ "\"category\":"
      assert log =~ "disconnected"
      assert log =~ "timeout"
    end
  end

  describe "log_message_event/3" do
    test "logs message events at info level by default" do
      log =
        capture_log(fn ->
          DefaultLoggingHandler.log_message_event(:sent, %{payload: "hi"}, @default_state)
        end)

      assert log =~ "[MESSAGE] :sent"
      assert log =~ "payload: \"hi\""
    end

    test "logs at warn level when configured" do
      log =
        capture_log(fn ->
          DefaultLoggingHandler.log_message_event(:received, %{payload: "pong"}, @warn_state)
        end)

      assert log =~ "[MESSAGE] :received"
      assert log =~ "payload: \"pong\""
    end
  end

  describe "log_error_event/3" do
    test "logs error events at info level by default" do
      log =
        capture_log(fn ->
          DefaultLoggingHandler.log_error_event(:ws_error, %{code: 1006, reason: "abnormal"}, @default_state)
        end)

      assert log =~ "[ERROR] :ws_error"
      assert log =~ "code: 1006"
      assert log =~ "reason: \"abnormal\""
    end

    test "logs error events in JSON format" do
      log =
        capture_log(fn ->
          DefaultLoggingHandler.log_error_event(:ws_error, %{code: 1001, reason: "going away"}, @json_state)
        end)

      assert log =~ "\"category\":"
      assert log =~ "ws_error"
      assert log =~ "going away"
    end
  end

  describe "edge cases" do
    test "handles unknown log format gracefully" do
      log =
        capture_log(fn ->
          DefaultLoggingHandler.log_connection_event(:foo, %{bar: 1}, %{log_format: :unknown})
        end)

      assert log =~ "[LOG]["
      assert log =~ ":foo"
      assert log =~ "bar: 1"
    end

    test "handles invalid log level by falling back to :info" do
      log =
        capture_log(fn ->
          DefaultLoggingHandler.log_message_event(:foo, %{bar: 2}, %{log_level: :notalevel})
        end)

      # Logger will treat :notalevel as :info (Logger.log/2 will not crash)
      assert log =~ "[MESSAGE] :foo"
      assert log =~ "bar: 2"
    end
  end
end
