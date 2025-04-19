defmodule WebsockexNova.Integration.EchoAdapterIntegrationTest do
  use ExUnit.Case, async: false

  alias WebsockexNova.Connection

  @moduletag :integration

  setup do
    {:ok, pid} = Connection.start_link(adapter: WebsockexNova.Platform.Echo.Adapter)

    on_exit(fn ->
      if Process.alive?(pid), do: Process.exit(pid, :kill)
    end)

    %{pid: pid}
  end

  test "echoes text messages", %{pid: pid} do
    send(pid, {:platform_message, "Hello", self()})
    assert_receive {:reply, {:text, "Hello"}}, 1000
  end

  test "echoes JSON messages", %{pid: pid} do
    msg = %{foo: "bar", n: 42}
    send(pid, {:platform_message, msg, self()})
    assert_receive {:reply, {:text, json}}, 1000
    assert Jason.decode!(json) == %{"foo" => "bar", "n" => 42}
  end

  test "echoes non-binary, non-map messages as string", %{pid: pid} do
    send(pid, {:platform_message, 12_345, self()})
    assert_receive {:reply, {:text, "12345"}}, 1000
  end
end
