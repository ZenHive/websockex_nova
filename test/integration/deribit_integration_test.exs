defmodule WebsockexNova.Integration.DeribitIntegrationTest do
  use ExUnit.Case, async: false

  alias WebsockexNova.Gun.ConnectionWrapper

  @moduletag :external

  @host "test.deribit.com"
  @port 443
  @ws_path "/ws/api/v2"
  @timeout 5000

  setup do
    client_id = System.fetch_env!("DERIBIT_CLIENT_ID")
    client_secret = System.fetch_env!("DERIBIT_CLIENT_SECRET")

    opts = %{
      transport: :tls,
      transport_opts: [
        verify: :verify_peer,
        cacerts: :certifi.cacerts(),
        server_name_indication: ~c"test.deribit.com"
      ],
      callback_pid: self()
    }

    {:ok, conn_pid} = ConnectionWrapper.open(@host, @port, opts)
    # Wait for connection_up
    assert_receive {:websockex_nova, {:connection_up, :http}}, @timeout
    {:ok, stream_ref} = ConnectionWrapper.upgrade_to_websocket(conn_pid, @ws_path)
    assert_receive {:websockex_nova, {:websocket_upgrade, ^stream_ref, _headers}}, @timeout
    %{conn_pid: conn_pid, stream_ref: stream_ref, client_id: client_id, client_secret: client_secret}
  end

  test "authenticates with credentials", %{
    conn_pid: conn_pid,
    stream_ref: stream_ref,
    client_id: client_id,
    client_secret: client_secret
  } do
    auth_msg = %{
      "jsonrpc" => "2.0",
      "id" => 1,
      "method" => "public/auth",
      "params" => %{
        "grant_type" => "client_credentials",
        "client_id" => client_id,
        "client_secret" => client_secret
      }
    }

    :ok = ConnectionWrapper.send_frame(conn_pid, stream_ref, {:text, Jason.encode!(auth_msg)})
    response = receive_json_response(stream_ref, @timeout)
    assert response["result"]["access_token"]
    assert response["result"]["expires_in"]
  end

  test "tracks and responds with matching request_id", %{
    conn_pid: conn_pid,
    stream_ref: stream_ref,
    client_id: client_id,
    client_secret: client_secret
  } do
    # Authenticate first
    auth_msg = %{
      "jsonrpc" => "2.0",
      "id" => 1,
      "method" => "public/auth",
      "params" => %{
        "grant_type" => "client_credentials",
        "client_id" => client_id,
        "client_secret" => client_secret
      }
    }

    :ok = ConnectionWrapper.send_frame(conn_pid, stream_ref, {:text, Jason.encode!(auth_msg)})
    _auth_response = receive_json_response(stream_ref, @timeout)

    for request_id <- [123, "abc-123", "request-#{:rand.uniform(1000)}"] do
      message = %{
        "jsonrpc" => "2.0",
        "id" => request_id,
        "method" => "public/test",
        "params" => %{}
      }

      :ok = ConnectionWrapper.send_frame(conn_pid, stream_ref, {:text, Jason.encode!(message)})
      response = receive_json_response(stream_ref, @timeout)
      assert response["id"] == request_id
    end
  end

  test "fetches account summary after authentication", %{
    conn_pid: conn_pid,
    stream_ref: stream_ref,
    client_id: client_id,
    client_secret: client_secret
  } do
    auth_msg = %{
      "jsonrpc" => "2.0",
      "id" => 1,
      "method" => "public/auth",
      "params" => %{
        "grant_type" => "client_credentials",
        "client_id" => client_id,
        "client_secret" => client_secret
      }
    }

    :ok = ConnectionWrapper.send_frame(conn_pid, stream_ref, {:text, Jason.encode!(auth_msg)})
    auth_response = receive_json_response(stream_ref, @timeout)
    assert access_token = auth_response["result"]["access_token"]

    summary_msg = %{
      "jsonrpc" => "2.0",
      "id" => 2,
      "method" => "private/get_account_summary",
      "params" => %{"currency" => "BTC"}
    }

    :ok = ConnectionWrapper.send_frame(conn_pid, stream_ref, {:text, Jason.encode!(summary_msg)})
    summary_response = receive_json_response(stream_ref, @timeout)
    assert summary_response["result"]["currency"] == "BTC"
  end

  @tag :skip
  test "handles rate limiting and backoff", _ do
    # Skipped: cannot reliably trigger rate limiting on the real API in a test
    :ok
  end

  @tag :skip
  test "handles token expiration and refresh", _ do
    # Skipped: cannot reliably force token expiration on the real API in a test
    :ok
  end

  defp receive_json_response(stream_ref, timeout) do
    receive do
      {:websockex_nova, {:websocket_frame, ^stream_ref, {:text, msg}}} -> Jason.decode!(msg)
    after
      timeout -> flunk("No response from Deribit API")
    end
  end
end
