defmodule WebsockexNova.ConnectionTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  defmodule DummyAdapter do
    @moduledoc false
    def init(_opts), do: {:ok, %{}}
    def subscribe(channel, params, state), do: {:reply, {:subscribed, channel, params}, state}
    def unsubscribe(channel, state), do: {:reply, {:unsubscribed, channel}, state}
    def authenticate(credentials, state), do: {:reply, {:authenticated, credentials}, state}
    def ping(state), do: {:reply, :pong, state}
    def status(state), do: {:reply, {:ok, state}, state}
  end

  setup do
    {:ok, pid} = WebsockexNova.Connection.start_link(adapter: DummyAdapter)
    %{pid: pid}
  end

  test "init initializes state with adapter", %{pid: pid} do
    state = :sys.get_state(pid)
    assert state.adapter == DummyAdapter
    assert is_map(state.state)
  end

  test "subscribe delegates to adapter", %{pid: pid} do
    send(pid, {:subscribe, "chan", %{foo: :bar}, self()})
    assert_receive {:reply, {:subscribed, "chan", %{foo: :bar}}}
  end

  test "unsubscribe delegates to adapter", %{pid: pid} do
    send(pid, {:unsubscribe, "chan", self()})
    assert_receive {:reply, {:unsubscribed, "chan"}}
  end

  test "authenticate delegates to adapter", %{pid: pid} do
    send(pid, {:authenticate, %{user: "u"}, self()})
    assert_receive {:reply, {:authenticated, %{user: "u"}}}
  end

  test "ping delegates to adapter", %{pid: pid} do
    send(pid, {:ping, self()})
    assert_receive {:reply, :pong}
  end

  test "status delegates to adapter", %{pid: pid} do
    send(pid, {:status, self()})
    assert_receive {:reply, {:ok, %{}}}
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
