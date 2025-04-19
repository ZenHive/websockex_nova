defmodule WebsockexNova.ClientTest do
  use ExUnit.Case, async: false

  alias WebsockexNova.Client
  alias WebsockexNova.Connection

  setup do
    {:ok, pid} = Connection.start_link(adapter: WebsockexNova.Platform.Echo.Adapter)

    on_exit(fn ->
      if Process.alive?(pid), do: Process.exit(pid, :kill)
    end)

    %{pid: pid}
  end

  test "send_text/2 echoes text", %{pid: pid} do
    assert Client.send_text(pid, "Hello") == {:text, "Hello"}
  end

  test "send_json/2 echoes JSON", %{pid: pid} do
    assert {:text, json} = Client.send_json(pid, %{foo: "bar"})
    assert Jason.decode!(json) == %{"foo" => "bar"}
  end

  test "send_text/2 returns timeout if no reply", %{pid: _pid} do
    # Use a fake pid that won't reply
    fake_pid = spawn(fn -> :ok end)
    assert Client.send_text(fake_pid, "no one home", 50) == {:error, :timeout}
  end

  test "send_json/2 returns timeout if no reply", %{pid: _pid} do
    fake_pid = spawn(fn -> :ok end)
    assert Client.send_json(fake_pid, %{foo: "bar"}, 50) == {:error, :timeout}
  end

  # The following tests use the Echo adapter, which does not support subscribe, unsubscribe, authenticate, ping, or status.
  # We expect inert or default responses (e.g., timeouts or echo of the message as text).

  test "subscribe/3 returns timeout or inert response for Echo adapter", %{pid: pid} do
    assert Client.subscribe(pid, "topic") in [{:text, ""}, {:error, :timeout}]
  end

  test "unsubscribe/2 returns timeout or inert response for Echo adapter", %{pid: pid} do
    assert Client.unsubscribe(pid, "topic") in [{:text, ""}, {:error, :timeout}]
  end

  test "authenticate/2 returns timeout or inert response for Echo adapter", %{pid: pid} do
    assert Client.authenticate(pid, %{user: "demo"}) in [{:text, ""}, {:error, :timeout}]
  end

  test "ping/1 returns timeout or inert response for Echo adapter", %{pid: pid} do
    assert Client.ping(pid) in [{:text, ""}, {:error, :timeout}]
  end

  test "status/1 returns timeout or inert response for Echo adapter", %{pid: pid} do
    assert Client.status(pid) in [{:text, ""}, {:error, :timeout}]
  end

  test "send_raw/2 echoes raw message as text", %{pid: pid} do
    assert Client.send_raw(pid, "raw") == {:text, "raw"}
  end

  test "cast_text/2 is fire-and-forget", %{pid: pid} do
    assert Client.cast_text(pid, "fire and forget") == :ok
    # No reply expected
  end
end
