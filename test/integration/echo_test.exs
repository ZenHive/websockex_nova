defmodule WebsockexNova.Integration.EchoTest do
  use ExUnit.Case, async: false

  alias WebsockexNova.Gun.ConnectionWrapper

  @timeout 5000
  @host "ws.postman-echo.com"
  @port 443
  @ws_path "/raw"

  setup do
    opts = %{
      transport: :tls,
      transport_opts: [],
      callback_pid: self()
    }

    {:ok, conn} = ConnectionWrapper.open(@host, @port, @ws_path, opts)
    assert_receive {:websockex_nova, {:connection_up, :http}}, @timeout
    %{conn: conn}
  end

  test "echoes text frames", %{conn: conn} do
    msg = %{"type" => "echo", "payload" => "hello"}
    :ok = ConnectionWrapper.send_frame(conn, conn.stream_ref, {:text, Jason.encode!(msg)})
    response = receive_json_response(conn.stream_ref, @timeout)
    decoded = Jason.decode!(response)
    assert decoded["type"] == "echo"
    assert decoded["payload"] == "hello"
  end

  @tag :skip
  test "echoes binary frames", %{conn: conn} do
    payload = <<1, 2, 3, 4, 5>>
    :ok = ConnectionWrapper.send_frame(conn, conn.stream_ref, {:binary, payload})
    response = receive_binary_response(conn.stream_ref, @timeout)
    assert response == payload
  end

  test "simulated request_id tracking", %{conn: conn} do
    stream_ref = conn.stream_ref
    # Create requests with different request IDs
    requests = [
      %{id: "req-1", method: "test.method", params: %{data: "value"}},
      %{id: "req-2", method: "test.method", params: %{data: "value"}},
      %{id: "req-3", method: "test.method", params: %{data: "value"}}
    ]

    # Process each request one at a time
    Enum.each(requests, fn request ->
      # Clear any previous messages from the mailbox
      flush_messages()

      # Send a request
      json_request = Jason.encode!(request)
      :ok = ConnectionWrapper.send_frame(conn, stream_ref, {:text, json_request})

      # Wait to receive the echo frame directly from the handler
      assert_receive {:websockex_nova, {:websocket_frame, ^stream_ref, {:text, response}}}, @timeout

      # Decode and verify the response has the same request ID
      response_data = Jason.decode!(response)
      assert response_data["id"] == request.id
    end)
  end

  # Helper function to flush messages from mailbox
  defp flush_messages do
    receive do
      _ -> flush_messages()
    after
      0 -> :ok
    end
  end

  defp receive_json_response(stream_ref, timeout) do
    assert_receive {:websockex_nova, {:websocket_frame, ^stream_ref, {:text, response}}}, timeout
    response
  end

  defp receive_binary_response(stream_ref, timeout) do
    assert_receive {:websockex_nova, {:websocket_frame, ^stream_ref, {:binary, response}}}, timeout
    response
  end
end
