defmodule WebsockexNova.Integration.EchoTest do
  use ExUnit.Case, async: false

  alias WebsockexNova.Gun.ConnectionWrapper
  alias WebsockexNova.Test.Support.MockWebSockServer

  @timeout 5000

  setup do
    {:ok, pid, port} = MockWebSockServer.start_link()
    # Store the server pid in a process dictionary to ensure we only attempt to stop it once
    Process.put(:mock_server_pid, pid)

    on_exit(fn ->
      server_pid = Process.get(:mock_server_pid)

      if server_pid && Process.alive?(server_pid) do
        MockWebSockServer.stop(server_pid)
      end
    end)

    {:ok, port: port, server_pid: pid}
  end

  test "basic echo functionality", %{port: port} do
    # Open a connection with this test process as the callback process
    {:ok, conn_pid} = ConnectionWrapper.open("echo.websocket.org", 443, %{transport: :tls, callback_pid: self()})

    # Wait for the connection to be established
    assert_receive {:websockex_nova, {:connection_up, :http}}, @timeout

    # Attempt to upgrade to a WebSocket connection
    {:ok, stream_ref} = ConnectionWrapper.upgrade_to_websocket(conn_pid, "/ws", [])

    # Wait for the WebSocket upgrade to complete
    assert_receive {:websockex_nova, {:websocket_upgrade, ^stream_ref, _headers}}, @timeout

    # Send a text frame through the WebSocket
    message = "Hello, WebSocket!"
    :ok = ConnectionWrapper.send_frame(conn_pid, stream_ref, {:text, message})

    # Wait to receive the frame back (the mock handler echoes directly)
    assert_receive {:websockex_nova, {:websocket_frame, ^stream_ref, {:text, ^message}}}, @timeout

    # Cleanup
    ConnectionWrapper.close(conn_pid)
  end

  test "simulated request_id tracking", %{port: port} do
    # Open a connection with this test process as the callback process
    {:ok, conn_pid} = ConnectionWrapper.open("echo.websocket.org", port, %{transport: :tls, callback_pid: self()})

    # Wait for the connection to be established
    assert_receive {:websockex_nova, {:connection_up, :http}}, @timeout

    # Attempt to upgrade to a WebSocket connection
    {:ok, stream_ref} = ConnectionWrapper.upgrade_to_websocket(conn_pid, "/ws", [])

    # Wait for the WebSocket upgrade to complete
    assert_receive {:websockex_nova, {:websocket_upgrade, ^stream_ref, _headers}}, @timeout

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
      :ok = ConnectionWrapper.send_frame(conn_pid, stream_ref, {:text, json_request})

      # Wait to receive the echo frame directly from the handler
      assert_receive {:websockex_nova, {:websocket_frame, ^stream_ref, {:text, response}}}, @timeout

      # Decode and verify the response has the same request ID
      response_data = Jason.decode!(response)
      assert response_data["id"] == request.id
    end)

    # Cleanup
    ConnectionWrapper.close(conn_pid)
  end

  # Helper function to flush messages from mailbox
  defp flush_messages do
    receive do
      _ -> flush_messages()
    after
      0 -> :ok
    end
  end
end
