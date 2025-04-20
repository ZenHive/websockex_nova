defmodule WebsockexNova.Integration.DeribitAdapterIntegrationTest do
  use ExUnit.Case, async: false

  alias WebsockexNova.Connection
  alias WebsockexNova.Platform.Deribit.Adapter

  @moduletag :integration

  setup do
    {:ok, pid} = Connection.start_link(adapter: Adapter)

    on_exit(fn ->
      if Process.alive?(pid), do: Process.exit(pid, :kill)
    end)

    %{pid: pid}
  end

  test "echoes public/hello", %{pid: pid} do
    msg = %{"method" => "public/hello", "id" => 42}
    send(pid, {:platform_message, msg, self()})
    assert_receive {:reply, {:text, json}}, 1000
    assert %{"result" => "hello", "id" => 42} = Jason.decode!(json)
  end

  test "encodes authentication request" do
    creds = %{client_id: "demo_id", client_secret: "demo_secret"}
    {:text, json} = Adapter.encode_auth_request(creds)
    decoded = Jason.decode!(json)
    assert decoded["method"] == "public/auth"
    assert decoded["params"]["client_id"] == "demo_id"
    assert decoded["params"]["client_secret"] == "demo_secret"
  end

  test "encodes subscription request" do
    {:text, json} = Adapter.encode_subscription_request("deribit_price_index.btc_usd")
    decoded = Jason.decode!(json)
    assert decoded["method"] == "public/subscribe"
    assert decoded["params"]["channels"] == ["deribit_price_index.btc_usd"]
  end

  test "handles generic JSON-RPC message", %{pid: pid} do
    msg = %{"method" => "public/get_book_summary_by_currency", "params" => %{"currency" => "BTC"}, "id" => 99}
    send(pid, {:platform_message, msg, self()})
    assert_receive {:reply, {:text, json}}, 1000
    assert %{"result" => "ok", "id" => 99} = Jason.decode!(json)
  end
end
