defmodule WebsockexNova.Integration.EchoConnectionWrapperTest do
  @moduledoc """
  The Echo adapter is intentionally minimal and only supports echoing text and JSON messages.
  All advanced features (subscriptions, authentication, ping, etc.) return inert values.
  """

  use ExUnit.Case, async: false

  alias WebsockexNova.Connection

  @moduletag :integration

  setup do
    {:ok, pid} =
      Connection.start_link(adapter: WebsockexNova.Platform.Echo.Adapter, host: "echo.websocket.org", port: 443)

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
    assert_receive {:reply, {:text, "Hello"}}, 500
  end

  test "echoes JSON messages", %{pid: pid} do
    msg = %{foo: "bar", n: 42}
    send(pid, {:platform_message, msg, self()})
    assert_receive {:reply, {:text, json}}, 500
    assert Jason.decode!(json) == %{"foo" => "bar", "n" => 42}
  end
end
