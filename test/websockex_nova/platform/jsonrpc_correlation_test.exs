defmodule WebsockexNova.Platform.JsonrpcCorrelationTest do
  use ExUnit.Case, async: false

  alias WebsockexNova.Client
  alias WebsockexNova.Connection
  alias WebsockexNova.Platform.Deribit.Adapter

  @moduletag :integration

  @endpoint "wss://test.deribit.com/ws/api/v2"

  test "JSON-RPC request/response correlation for public/ping" do
    {:ok, pid} =
      Connection.start_link(
        adapter: Adapter,
        host: "test.deribit.com",
        port: 443,
        path: "/ws/api/v2"
      )

    id = :os.system_time(:millisecond)

    req = %{
      "jsonrpc" => "2.0",
      "id" => id,
      "method" => "public/ping",
      "params" => %{}
    }

    reply = Client.send_raw(pid, req, 3_000)
    assert {:reply, {:text, json}} = {:reply, reply}
    decoded = Jason.decode!(json)
    assert %{"jsonrpc" => "2.0", "id" => ^id, "result" => "pong"} = decoded
  end
end
