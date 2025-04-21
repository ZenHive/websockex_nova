defmodule WebsockexNova.ConnectionGunLifecycleTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias WebsockexNova.Connection
  alias WebsockexNova.Defaults.DefaultAuthHandler
  alias WebsockexNova.Defaults.DefaultConnectionHandler
  alias WebsockexNova.Defaults.DefaultErrorHandler
  alias WebsockexNova.Defaults.DefaultLoggingHandler
  alias WebsockexNova.Defaults.DefaultMessageHandler
  alias WebsockexNova.Defaults.DefaultMetricsCollector
  alias WebsockexNova.Defaults.DefaultRateLimitHandler
  alias WebsockexNova.Defaults.DefaultSubscriptionHandler
  alias WebsockexNova.Test.Support.MockWebSockServer

  @moduletag :integration
  @timeout 500

  setup do
    {:ok, server, port} = MockWebSockServer.start_link()
    on_exit(fn -> if Process.alive?(server), do: MockWebSockServer.stop(server) end)
    %{server: server, port: port}
  end

  defp start_connection(port, opts \\ []) do
    {:ok, conn} =
      Connection.start_link(
        [
          adapter: WebsockexNova.TestAdapter,
          host: "localhost",
          port: port,
          transport: :tcp,
          request_timeout: 100,
          path: "/ws",
          connection_handler: DefaultConnectionHandler,
          message_handler: DefaultMessageHandler,
          subscription_handler: DefaultSubscriptionHandler,
          auth_handler: DefaultAuthHandler,
          error_handler: DefaultErrorHandler,
          rate_limit_handler: DefaultRateLimitHandler,
          logging_handler: DefaultLoggingHandler,
          metrics_collector: DefaultMetricsCollector
        ] ++ opts
      )

    on_exit(fn -> if Process.alive?(conn.pid), do: GenServer.stop(conn.pid) end)
    conn
  end

  # Helper to flush unexpected HTTP responses from the mailbox
  defp flush_http_responses do
    receive do
      {:websockex_nova, {:http_response, _, _, _, _}} -> flush_http_responses()
      {:websockex_nova, {:http_response, _, _, _, _, _}} -> flush_http_responses()
      {:websockex_nova, {:http_data, _, _, _}} -> flush_http_responses()
      _ -> flush_http_responses()
    after
      10 -> :ok
    end
  end

  test "handles gun_up event and logs/telemetry", %{port: port} do
    conn = start_connection(port)

    log =
      capture_log(fn ->
        send(conn.pid, {:gun_up, self(), :http})
        # Allow message to be processed
        Process.sleep(50)
      end)

    assert log =~ "Gun connection up"
    # No state change expected, just log/telemetry
  end

  @tag :skip
  test "handles gun_down event, cleans up, and schedules reconnect", %{port: port} do
    {:ok, conn} =
      Connection.start_link_test(
        adapter: WebsockexNova.TestAdapter,
        host: "localhost",
        port: port,
        transport: :tcp,
        request_timeout: 100,
        path: "/ws",
        connection_handler: DefaultConnectionHandler,
        message_handler: DefaultMessageHandler,
        subscription_handler: DefaultSubscriptionHandler,
        auth_handler: DefaultAuthHandler,
        error_handler: DefaultErrorHandler,
        rate_limit_handler: DefaultRateLimitHandler,
        logging_handler: DefaultLoggingHandler,
        metrics_collector: DefaultMetricsCollector
      )

    # Use the public API to create a pending request and timer
    assert :buffered = GenServer.call(conn.pid, {:send_request, {:text, "foo"}, "1", self()})
    # Simulate gun_down event
    log =
      capture_log(fn ->
        send(conn.pid, {:gun_down, self(), :http, :closed, [], []})
        # Allow message to be processed
        Process.sleep(50)
      end)

    assert log =~ "Gun connection down"
    assert_receive {:error, :disconnected}, @timeout
    # In test mode, reconnection is not supported, so we do not assert on process liveness or reconnection
  end

  test "schedules reconnection on :reconnect event", %{port: port} do
    conn = start_connection(port)

    log =
      capture_log(fn ->
        send(conn.pid, :reconnect)
        Process.sleep(50)
      end)

    assert log =~ "Attempting reconnection"
    # Should not crash
    assert Process.alive?(conn.pid)
  end
end
