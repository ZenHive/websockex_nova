defmodule WebsockexNova.ConnectionTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  defmodule DummyAdapter do
    @moduledoc false
    def init(_opts), do: {:ok, %{}}
  end

  defmodule DummyConnectionHandler do
    @moduledoc false
    @behaviour WebsockexNova.Behaviors.ConnectionHandler

    def init(_opts), do: {:ok, %{}}
    def handle_connect(conn_info, state), do: {:ok, Map.put(state, :connected, conn_info)}
    def handle_disconnect(reason, state), do: {:ok, Map.put(state, :disconnected, reason)}
    def handle_frame(type, data, state), do: {:ok, Map.put(state, :last_frame, {type, data})}
    def handle_timeout(state), do: {:ok, Map.put(state, :timeout, true)}
  end

  defmodule DummySubscriptionHandler do
    @moduledoc false
    @behaviour WebsockexNova.Behaviors.SubscriptionHandler

    def subscribe(channel, params, state), do: {:reply, {:subscribed, channel, params}, state}
    def unsubscribe(channel, state), do: {:reply, {:unsubscribed, channel}, state}
    def handle_subscription_response(_resp, state), do: {:ok, state}
    def active_subscriptions(state), do: {[], state}
    def find_subscription_by_channel(_channel, state), do: {nil, state}
  end

  defmodule DummyAuthHandler do
    @moduledoc false
    @behaviour WebsockexNova.Behaviors.AuthHandler

    def authenticate(credentials, state), do: {:reply, {:authenticated, credentials}, state}
    def generate_auth_data(_state), do: {:ok, %{}}
    def handle_auth_response(_resp, state), do: {:ok, state}
    def needs_reauthentication?(_state), do: false
  end

  defmodule DummyErrorHandler do
    @moduledoc false
    @behaviour WebsockexNova.Behaviors.ErrorHandler

    def handle_error(error, _context, state), do: {:reply, {:error_handled, error}, state}
    def should_reconnect?(_error, _attempt, _state), do: {false, nil}
    def log_error(_error, _context, _state), do: :ok
    def classify_error(_error, _context), do: :unknown
  end

  defmodule DummyMessageHandler do
    @moduledoc false
    @behaviour WebsockexNova.Behaviors.MessageHandler

    def handle_message(message, state), do: {:reply, {:message_handled, message}, state}
    def validate_message(message), do: {:ok, message}
    def message_type(_), do: :dummy
    def encode_message(message, _state), do: {:ok, :text, inspect(message)}
  end

  defmodule DummyLoggingHandler do
    @moduledoc false
    @behaviour WebsockexNova.Behaviors.LoggingHandler

    def log_connection_event(_event, _context, _state), do: :ok
    def log_message_event(_event, _context, _state), do: :ok
    def log_error_event(_event, _context, _state), do: :ok
  end

  defmodule DummyMetricsCollector do
    @moduledoc false
    @behaviour WebsockexNova.Behaviors.MetricsCollector

    def handle_connection_event(_event, _measurements, _metadata), do: :ok
    def handle_message_event(_event, _measurements, _metadata), do: :ok
    def handle_error_event(_event, _measurements, _metadata), do: :ok
  end

  setup do
    {:ok, pid} =
      WebsockexNova.Connection.start_link(
        adapter: DummyAdapter,
        connection_handler: DummyConnectionHandler,
        subscription_handler: DummySubscriptionHandler,
        auth_handler: DummyAuthHandler,
        error_handler: DummyErrorHandler,
        message_handler: DummyMessageHandler,
        logging_handler: DummyLoggingHandler,
        metrics_collector: DummyMetricsCollector
      )

    %{pid: pid}
  end

  test "init initializes state with handlers", %{pid: pid} do
    state = :sys.get_state(pid)
    assert state.connection_handler == DummyConnectionHandler
    assert state.subscription_handler == DummySubscriptionHandler
    assert state.auth_handler == DummyAuthHandler
    assert state.error_handler == DummyErrorHandler
    assert state.message_handler == DummyMessageHandler
  end

  test "subscribe delegates to subscription_handler", %{pid: pid} do
    send(pid, {:subscribe, "chan", %{foo: :bar}, self()})
    assert_receive {:reply, {:subscribed, "chan", %{foo: :bar}}}
  end

  test "unsubscribe delegates to subscription_handler", %{pid: pid} do
    send(pid, {:unsubscribe, "chan", self()})
    assert_receive {:reply, {:unsubscribed, "chan"}}
  end

  test "authenticate delegates to auth_handler", %{pid: pid} do
    send(pid, {:authenticate, %{user: "u"}, self()})
    assert_receive {:reply, {:authenticated, %{user: "u"}}}
  end

  test "error_event delegates to error_handler", %{pid: pid} do
    send(pid, {:error_event, :some_error, self()})
    assert_receive {:reply, {:error_handled, :some_error}}
  end

  test "message_event delegates to message_handler", %{pid: pid} do
    send(pid, {:message_event, %{foo: :bar}, self()})
    assert_receive {:reply, {:message_handled, %{foo: :bar}}}
  end

  test "websocket_connected delegates to connection_handler", %{pid: pid} do
    send(pid, {:websocket_connected, %{host: "localhost", port: 80, path: "/", protocol: nil, transport: :tcp}})
    state = :sys.get_state(pid)
    assert state.state[:connected][:host] == "localhost"
  end

  test "websocket_disconnected delegates to connection_handler", %{pid: pid} do
    send(pid, {:websocket_disconnected, {:remote, 1000, "bye"}})
    state = :sys.get_state(pid)
    assert state.state[:disconnected] == {:remote, 1000, "bye"}
  end

  test "websocket_frame delegates to connection_handler", %{pid: pid} do
    send(pid, {:websocket_frame, {:text, "hi"}})
    state = :sys.get_state(pid)
    assert state.state[:last_frame] == {:text, "hi"}
  end

  defmodule NoopAdapter do
    @moduledoc false
    def init(_opts), do: {:ok, %{}}
  end

  test "logs and returns error if adapter does not implement subscribe", %{pid: _} do
    {:ok, pid} = WebsockexNova.Connection.start_link(adapter: NoopAdapter)

    log =
      capture_log(fn ->
        send(pid, {:subscribe, "chan", %{}, self()})
        assert_receive {:error, :not_implemented}
      end)

    assert log =~ "does not implement subscribe/3"
  end

  test "logs and returns error if adapter does not implement unsubscribe", %{pid: _} do
    {:ok, pid} = WebsockexNova.Connection.start_link(adapter: NoopAdapter)

    log =
      capture_log(fn ->
        send(pid, {:unsubscribe, "chan", self()})
        assert_receive {:error, :not_implemented}
      end)

    assert log =~ "does not implement unsubscribe/2"
  end

  test "logs and returns error if adapter does not implement authenticate", %{pid: _} do
    {:ok, pid} = WebsockexNova.Connection.start_link(adapter: NoopAdapter)

    log =
      capture_log(fn ->
        send(pid, {:authenticate, %{}, self()})
        assert_receive {:error, :not_implemented}
      end)

    assert log =~ "does not implement authenticate/2"
  end

  test "logs and returns error if adapter does not implement ping", %{pid: _} do
    {:ok, pid} = WebsockexNova.Connection.start_link(adapter: NoopAdapter)

    log =
      capture_log(fn ->
        send(pid, {:ping, self()})
        assert_receive {:error, :not_implemented}
      end)

    assert log =~ "does not implement ping/1"
  end

  test "logs and returns error if adapter does not implement status", %{pid: _} do
    {:ok, pid} = WebsockexNova.Connection.start_link(adapter: NoopAdapter)

    log =
      capture_log(fn ->
        send(pid, {:status, self()})
        assert_receive {:error, :not_implemented}
      end)

    assert log =~ "does not implement status/1"
  end

  test "crashes on unexpected message", %{pid: pid} do
    Process.flag(:trap_exit, true)

    ref = Process.monitor(pid)
    send(pid, {:unknown, self()})
    assert_receive {:DOWN, ^ref, :process, ^pid, {%RuntimeError{message: msg}, _}}
    assert msg =~ "Unexpected message in WebsockexNova.Connection"
  end
end
