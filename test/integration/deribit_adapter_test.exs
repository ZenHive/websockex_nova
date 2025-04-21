defmodule WebsockexNova.Integration.DeribitAdapterTest do
  use ExUnit.Case, async: false

  alias WebsockexNova.Client
  alias WebsockexNova.Platform.Deribit.Adapter

  @moduletag :external

  @host "test.deribit.com"
  @port 443
  @ws_path "/ws/api/v2"
  @timeout 5_000

  test "connects and receives pong from Deribit public/ping" do
    # Start the connection using the Deribit adapter
    {:ok, conn} =
      WebsockexNova.Connection.start_link(
        adapter: Adapter,
        host: @host,
        port: @port,
        path: @ws_path,
        transport: :tls,
        transport_opts: [
          verify: :verify_peer,
          cacerts: :certifi.cacerts(),
          server_name_indication: ~c"test.deribit.com"
        ],
        callback_pid: self()
      )

    # Wait for websocket upgrade before sending messages
    assert_receive {:websockex_nova, {:websocket_upgrade, _stream_ref, _headers}}, @timeout

    # Send a public/ping JSON-RPC message
    ping_msg = %{jsonrpc: "2.0", id: 1, method: "public/ping", params: %{}}
    result = Client.send_json(conn, ping_msg)
    IO.inspect(result, label: "send_json result")
    # Uncomment the following lines after diagnosis
    {:text, json} = result
    response = Jason.decode!(json)
    assert response["jsonrpc"] == "2.0"
    assert response["id"] == 1
    assert response["result"] == "pong"
  end

  defp receive_response(timeout) do
    receive do
      {:websockex_nova, {:websocket_frame, _stream_ref, {:text, msg}}} ->
        Jason.decode!(msg)

      {:websockex_nova, {:websocket_frame, {:text, msg}}} ->
        Jason.decode!(msg)

      {:websockex_nova, {:text, msg}} ->
        Jason.decode!(msg)

      msg ->
        flunk("Unexpected message: #{inspect(msg)}")
    after
      timeout -> flunk("No response from Deribit API")
    end
  end
end
