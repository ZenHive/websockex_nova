defmodule WebsockexNova.Telemetry.TelemetryEventsTest do
  use ExUnit.Case, async: true

  alias WebsockexNova.Telemetry.TelemetryEvents

  describe "event name functions" do
    test "connection_open/0 returns the correct event name" do
      assert TelemetryEvents.connection_open() == [:websockex_nova, :connection, :open]
    end

    test "connection_close/0 returns the correct event name" do
      assert TelemetryEvents.connection_close() == [:websockex_nova, :connection, :close]
    end

    test "connection_websocket_upgrade/0 returns the correct event name" do
      assert TelemetryEvents.connection_websocket_upgrade() == [
               :websockex_nova,
               :connection,
               :websocket_upgrade
             ]
    end

    test "message_sent/0 returns the correct event name" do
      assert TelemetryEvents.message_sent() == [:websockex_nova, :message, :sent]
    end

    test "message_received/0 returns the correct event name" do
      assert TelemetryEvents.message_received() == [:websockex_nova, :message, :received]
    end

    test "error_occurred/0 returns the correct event name" do
      assert TelemetryEvents.error_occurred() == [:websockex_nova, :error, :occurred]
    end
  end

  describe "documentation" do
    test "module has a moduledoc" do
      {:docs_v1, _, _, _, %{"en" => moduledoc}, _, _} = Code.fetch_docs(TelemetryEvents)
      assert String.contains?(moduledoc, "telemetry events")
    end
  end
end
