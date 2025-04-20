defmodule WebsockexNova.ConnectionOrchestrationTest do
  use ExUnit.Case, async: true

  alias WebsockexNova.Client
  alias WebsockexNova.Platform.Echo.Adapter

  @moduletag :integration

  setup do
    # Start a connection process with the Echo adapter
    {:ok, conn_pid} = WebsockexNova.Connection.start_link(adapter: Adapter, host: "echo.websocket.org", port: 80)
    %{conn_pid: conn_pid}
  end

  test "send_text/2 forwards to the wrapper and returns echo reply", %{conn_pid: conn_pid} do
    assert {:text, "Hello"} = Client.send_text(conn_pid, "Hello")
  end

  test "send_json/2 forwards to the wrapper and returns echo reply", %{conn_pid: conn_pid} do
    assert {:text, json} = Client.send_json(conn_pid, %{"foo" => "bar"})
    assert Jason.decode!(json) == %{"foo" => "bar"}
  end

  test "subscribe/3 forwards to the wrapper and returns inert reply", %{conn_pid: conn_pid} do
    assert {:text, ""} = Client.subscribe(conn_pid, "test_channel")
  end

  test "authenticate/2 forwards to the wrapper and returns inert reply", %{conn_pid: conn_pid} do
    assert {:text, ""} = Client.authenticate(conn_pid, %{"token" => "abc"})
  end

  test "ping/1 forwards to the wrapper and returns inert reply", %{conn_pid: conn_pid} do
    assert {:text, ""} = Client.ping(conn_pid)
  end

  test "status/1 forwards to the wrapper and returns inert reply", %{conn_pid: conn_pid} do
    assert {:text, ""} = Client.status(conn_pid)
  end
end
