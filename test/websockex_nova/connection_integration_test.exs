defmodule WebsockexNova.ConnectionIntegrationTest do
  use ExUnit.Case, async: false

  alias WebsockexNova.Connection
  alias WebsockexNova.Defaults.DefaultLoggingHandler
  alias WebsockexNova.Defaults.DefaultMetricsCollector
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
      Connection.start_link_test(
        [
          adapter: WebsockexNova.TestAdapter,
          host: "localhost",
          port: port,
          transport: :tcp,
          request_timeout: 100,
          connection_handler: WebsockexNova.Defaults.DefaultConnectionHandler,
          message_handler: WebsockexNova.Defaults.DefaultMessageHandler,
          subscription_handler: WebsockexNova.Defaults.DefaultSubscriptionHandler,
          auth_handler: WebsockexNova.Defaults.DefaultAuthHandler,
          error_handler: WebsockexNova.Defaults.DefaultErrorHandler,
          rate_limit_handler: WebsockexNova.Defaults.DefaultRateLimitHandler,
          logging_handler: DefaultLoggingHandler,
          metrics_collector: DefaultMetricsCollector
        ] ++ opts
      )

    on_exit(fn -> if Process.alive?(conn.pid), do: GenServer.stop(conn.pid) end)
    conn
  end

  test "reconnection logic is triggered on handler {:reconnect, new_state}", %{port: port} do
    defmodule ReconnectHandler do
      @moduledoc false
      def init(opts), do: {:ok, opts}
      def handle_connect(_info, state), do: {:reconnect, state}
      def handle_disconnect(_reason, state), do: {:reconnect, state}
      def handle_frame(_type, _data, state), do: {:reconnect, state}
      def handle_error(_error, _ctx, state), do: {:reconnect, state}
      def handle_message(_msg, state), do: {:reconnect, state}
      def subscribe(_channel, _params, state), do: {:reconnect, state}
      def unsubscribe(_channel, state), do: {:reconnect, state}
      def authenticate(_credentials, state), do: {:reconnect, state}
    end

    {:ok, conn} =
      Connection.start_link_test(
        adapter: WebsockexNova.TestAdapter,
        host: "localhost",
        port: port,
        transport: :tcp,
        connection_handler: ReconnectHandler,
        message_handler: ReconnectHandler,
        subscription_handler: ReconnectHandler,
        auth_handler: ReconnectHandler,
        error_handler: ReconnectHandler,
        rate_limit_handler: ReconnectHandler,
        logging_handler: DefaultLoggingHandler,
        metrics_collector: DefaultMetricsCollector
      )

    send(conn.pid, {:gun_upgrade, self(), :stream, ["websocket"], []})
    assert Process.alive?(conn.pid)
    GenServer.stop(conn.pid)
  end

  test "resource cleanup on terminate", %{port: port} do
    conn = start_connection(port)
    assert :buffered = GenServer.call(conn.pid, {:send_request, {:text, "baz"}, "5", self()})
    GenServer.stop(conn.pid)
    assert_receive {:error, :terminated}, @timeout
  end
end
