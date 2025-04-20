defmodule WebsockexNova.Integration.EchoConnectionWrapperTest do
  @moduledoc """
  The Echo adapter is intentionally minimal and only supports echoing text and JSON messages.
  All advanced features (subscriptions, authentication, ping, etc.) return inert values.
  """

  use ExUnit.Case, async: false

  alias WebsockexNova.Connection

  @moduletag :integration

  setup do
    {:ok, conn} =
      Connection.start_link(adapter: WebsockexNova.Platform.Echo.Adapter, host: "echo.websocket.org", port: 443)

    on_exit(fn ->
      if Process.alive?(conn.pid), do: Process.exit(conn.pid, :normal)
    end)

    %{conn: conn}
  end

  test "process is alive and monitorable", %{conn: conn} do
    assert Process.alive?(conn.pid)
    ref = Process.monitor(conn.pid)
    Process.unlink(conn.pid)
    Process.exit(conn.pid, :kill)
    pid = conn.pid
    assert_receive {:DOWN, ^ref, :process, ^pid, :killed}, 1000
  end

  test "echoes text messages", %{conn: conn} do
    send(conn.pid, {:platform_message, conn.stream_ref, "Hello", self()})
    assert_receive {:reply, {:text, "Hello"}}, 500
  end

  test "echoes JSON messages", %{conn: conn} do
    msg = %{foo: "bar", n: 42}
    send(conn.pid, {:platform_message, conn.stream_ref, msg, self()})
    assert_receive {:reply, {:text, json}}, 500
    assert Jason.decode!(json) == %{"foo" => "bar", "n" => 42}
  end
end
