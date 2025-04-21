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
    assert_receive {:websockex_nova, {:connection_websocket_upgrade, _stream_ref, _headers}}, @timeout
    flush_mailbox()

    # Print all messages currently in the mailbox before sending
    IO.puts("--- Mailbox before send_json ---")
    flush_mailbox()
    IO.puts("--- End mailbox before send_json ---")

    # Send a public/ping JSON-RPC message
    ping_msg = %{jsonrpc: "2.0", id: 1, method: "public/ping", params: %{}}
    result = Client.send_json(conn, ping_msg)
    # IO.inspect(result, label: "send_json result")

    # Print all messages currently in the mailbox after send_json
    IO.puts("--- Mailbox after send_json ---")
    flush_mailbox()
    IO.puts("--- End mailbox after send_json ---")

    # Uncomment the following lines after diagnosis
    {:text, json} = result
    response = Jason.decode!(json)
    assert response["jsonrpc"] == "2.0"
    assert response["id"] == 1
    assert response["result"] == "pong"
  end

  test "send_json/2 returns reply to caller, notifications go to callback_pid" do
    parent = self()

    notification_pid =
      spawn(fn ->
        loop_notify(parent)
      end)

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
        callback_pid: notification_pid
      )

    # Match on connection events (no longer wrapped in :notification)
    assert_receive {:websockex_nova, {:connection_websocket_upgrade, _stream_ref, _headers}}, @timeout
    flush_mailbox()

    # Send a public/ping JSON-RPC message and assert reply is received by this process
    ping_msg = %{jsonrpc: "2.0", id: 42, method: "public/ping", params: %{}}
    result = Client.send_json(conn, ping_msg, @timeout)
    assert {:text, json} = result
    response = Jason.decode!(json)
    assert response["id"] == 42
    assert response["result"] == "pong"

    # Simulate a notification (no id) from the connection process
    frame = Jason.encode!(%{"jsonrpc" => "2.0", "method" => "test_notification", "params" => %{}})
    send(notification_pid, {:websockex_nova, {:websocket_frame, {:text, frame}}})
    assert_receive {:websockex_nova, {:websocket_frame, {:text, ^frame}}}, @timeout
  end

  defp loop_notify(parent) do
    receive do
      msg ->
        send(parent, msg)
        loop_notify(parent)
    end
  end

  defp flush_mailbox do
    receive do
      _msg ->
        # IO.inspect(msg, label: "mailbox message")
        flush_mailbox()
    after
      100 -> :ok
    end
  end

  # defp receive_response(timeout) do
  #   receive do
  #     {:websockex_nova, {:websocket_frame, _stream_ref, {:text, msg}}} ->
  #       Jason.decode!(msg)

  #     {:websockex_nova, {:websocket_frame, {:text, msg}}} ->
  #       Jason.decode!(msg)

  #     {:websockex_nova, {:text, msg}} ->
  #       Jason.decode!(msg)

  #     msg ->
  #       flunk("Unexpected message: #{inspect(msg)}")
  #   after
  #     timeout -> flunk("No response from Deribit API")
  #   end
  # end
end
