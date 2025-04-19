defmodule WebsockexNova.Integration.EchoConnectionWrapperTest do
  use ExUnit.Case, async: false

  alias WebsockexNova.Connection

  @moduletag :integration

  setup do
    {:ok, pid} = Connection.start_link(adapter: WebsockexNova.Platform.Echo.Adapter)

    on_exit(fn ->
      if Process.alive?(pid), do: Process.exit(pid, :normal)
    end)

    %{pid: pid}
  end

  test "process is alive and monitorable", %{pid: pid} do
    assert Process.alive?(pid)
    ref = Process.monitor(pid)
    Process.unlink(pid)
    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^ref, :process, ^pid, :killed}, 1000
  end

  test "echoes text messages", %{pid: pid} do
    send(pid, {:platform_message, "Hello", self()})
    assert_receive {:reply, {:text, "ECHO: Hello"}}, 500
  end

  test "responds to JSON ping", %{pid: pid} do
    ping = %{"type" => "ping"}
    send(pid, {:platform_message, ping, self()})
    assert_receive {:reply, {:text, pong}}, 500
    assert %{"type" => "pong"} = Jason.decode!(pong)
  end

  test "handles subscription and unsubscription", %{pid: pid} do
    sub = %{"type" => "subscribe", "channel" => "chan1"}
    send(pid, {:platform_message, sub, self()})
    assert_receive {:reply, {:text, sub_resp}}, 500
    assert %{"status" => "subscribed", "channel" => "chan1"} = Jason.decode!(sub_resp)

    unsub = %{"type" => "unsubscribe", "channel" => "chan1"}
    send(pid, {:platform_message, unsub, self()})
    assert_receive {:reply, {:text, unsub_resp}}, 500
    assert %{"status" => "unsubscribed", "channel" => "chan1"} = Jason.decode!(unsub_resp)
  end

  test "handles authentication", %{pid: pid} do
    auth = %{"type" => "auth", "success" => true}
    send(pid, {:platform_message, auth, self()})
    # Auth just updates state, no reply expected
    refute_receive {:reply, _}, 200
  end
end
