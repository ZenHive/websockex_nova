defmodule WebsockexNova.Integration.EchoAdapterIntegrationTest do
  use ExUnit.Case, async: false

  alias WebsockexNova.Connection

  @moduletag :integration

  setup do
    {:ok, conn} =
      Connection.start_link(adapter: WebsockexNova.Platform.Echo.Adapter, host: "echo.websocket.org", port: 443)

    on_exit(fn ->
      if Process.alive?(conn.pid), do: Process.exit(conn.pid, :kill)
    end)

    %{conn: conn}
  end

  test "echoes text messages", %{conn: conn} do
    send(conn.pid, {:platform_message, conn.stream_ref, "Hello", self()})
    assert_receive {:reply, {:text, "Hello"}}, 1000
  end

  test "echoes JSON messages", %{conn: conn} do
    msg = %{foo: "bar", n: 42}
    send(conn.pid, {:platform_message, conn.stream_ref, msg, self()})
    assert_receive {:reply, {:text, json}}, 1000
    assert Jason.decode!(json) == %{"foo" => "bar", "n" => 42}
  end

  test "echoes non-binary, non-map messages as string", %{conn: conn} do
    send(conn.pid, {:platform_message, conn.stream_ref, 12_345, self()})
    assert_receive {:reply, {:text, "12345"}}, 1000
  end
end
