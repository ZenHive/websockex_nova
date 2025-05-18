defmodule WebsockexNova.Integration.DeribitComprehensiveIntegrationTest do
  use ExUnit.Case, async: false

  alias WebsockexNova.Examples.ClientDeribit
  alias WebsockexNova.Gun.ConnectionWrapper

  @moduletag :integration
  @moduletag :external

  @host "test.deribit.com"
  @port 443
  @ws_path "/ws/api/v2"
  @timeout 10_000

  # Test channels
  @test_instrument "BTC-PERPETUAL"
  @test_channels [
    "trades.#{@test_instrument}.raw",
    "ticker.#{@test_instrument}.raw",
    "book.#{@test_instrument}.100ms"
  ]

  setup do
    # Get API credentials (will skip auth tests if not available)
    client_id = System.get_env("DERIBIT_CLIENT_ID")
    client_secret = System.get_env("DERIBIT_CLIENT_SECRET")
    creds_available = client_id != nil && client_secret != nil

    # Configure TLS for secure connection
    transport_opts = %{
      verify: :verify_peer,
      cacerts: :certifi.cacerts(),
      server_name_indication: ~c"test.deribit.com"
    }

    # Open raw connection for low-level tests
    {:ok, raw_conn} =
      ConnectionWrapper.open(
        @host,
        @port,
        @ws_path,
        %{
          transport: :tls,
          transport_opts: transport_opts,
          callback_pid: self()
        }
      )

    # Wait for raw connection to be established
    assert_receive {:websockex_nova, {:connection_up, :http}}, @timeout

    # Open high-level client connection for client API tests
    {:ok, client_conn} =
      ClientDeribit.connect(%{
        host: @host,
        transport: :tls,
        transport_opts: transport_opts
      })

    %{
      raw_conn: raw_conn,
      client_conn: client_conn,
      credentials_available: creds_available,
      credentials: %{
        api_key: client_id,
        client_secret: client_secret
      }
    }
  end

  describe "raw connection functionality" do
    test "sends and receives JSON-RPC messages", %{raw_conn: conn} do
      # Test the simplest API call
      test_msg = %{
        "jsonrpc" => "2.0",
        "id" => 1,
        "method" => "public/test",
        "params" => %{}
      }

      # Send request
      :ok = ConnectionWrapper.send_frame(conn, conn.stream_ref, {:text, Jason.encode!(test_msg)})

      # Receive response
      response = receive_json_response(conn.stream_ref, @timeout)

      # Verify response
      assert response["jsonrpc"] == "2.0"
      assert response["id"] == 1
      assert Map.has_key?(response, "result")
      assert response["result"]["version"]
    end

    test "retrieves server time", %{raw_conn: conn} do
      time_msg = %{
        "jsonrpc" => "2.0",
        "id" => 2,
        "method" => "public/get_time",
        "params" => %{}
      }

      # Send request
      :ok = ConnectionWrapper.send_frame(conn, conn.stream_ref, {:text, Jason.encode!(time_msg)})

      # Receive response
      response = receive_json_response(conn.stream_ref, @timeout)

      # Verify response
      assert response["jsonrpc"] == "2.0"
      assert response["id"] == 2
      assert is_integer(response["result"])

      # Verify timestamp is recent (within last minute)
      now_ms = :os.system_time(:millisecond)
      time_diff_ms = now_ms - response["result"]
      assert time_diff_ms < 60_000
    end

    test "supports server hello message", %{raw_conn: conn} do
      hello_msg = %{
        "jsonrpc" => "2.0",
        "id" => 3,
        "method" => "public/hello",
        "params" => %{
          "client_name" => "WebsockexNovaTest",
          "client_version" => "1.0.0"
        }
      }

      # Send request
      :ok = ConnectionWrapper.send_frame(conn, conn.stream_ref, {:text, Jason.encode!(hello_msg)})

      # Receive response
      response = receive_json_response(conn.stream_ref, @timeout)

      # Verify response
      assert response["jsonrpc"] == "2.0"
      assert response["id"] == 3
      assert Map.has_key?(response, "result")
      assert response["result"]["version"]
      assert response["result"]["build_number"]
    end

    test "subscribes to public channels", %{raw_conn: conn} do
      # Subscribe to a public channel (no auth required)
      test_channel = Enum.at(@test_channels, 0)

      subscribe_msg = %{
        "jsonrpc" => "2.0",
        "id" => 4,
        "method" => "public/subscribe",
        "params" => %{
          "channels" => [test_channel]
        }
      }

      # Send request
      :ok = ConnectionWrapper.send_frame(conn, conn.stream_ref, {:text, Jason.encode!(subscribe_msg)})

      # Receive response
      response = receive_json_response(conn.stream_ref, @timeout)

      # Verify subscription was successful
      assert response["jsonrpc"] == "2.0"
      assert response["id"] == 4
      assert response["result"] == [true]

      # Wait for a notification from the subscribed channel
      notification = receive_json_notification(@timeout)

      # Verify notification format
      assert notification["jsonrpc"] == "2.0"
      assert notification["method"] == "subscription"
      assert Map.has_key?(notification, "params")
      assert notification["params"]["channel"] == test_channel
    end

    test "authenticates with valid credentials", %{
      raw_conn: conn,
      credentials: credentials,
      credentials_available: creds_available
    } do
      if creds_available do
        auth_msg = %{
          "jsonrpc" => "2.0",
          "id" => 5,
          "method" => "public/auth",
          "params" => %{
            "grant_type" => "client_credentials",
            "client_id" => credentials.api_key,
            "client_secret" => credentials.client_secret
          }
        }

        # Send request
        :ok = ConnectionWrapper.send_frame(conn, conn.stream_ref, {:text, Jason.encode!(auth_msg)})

        # Receive response
        response = receive_json_response(conn.stream_ref, @timeout)

        # Verify authentication was successful
        assert response["jsonrpc"] == "2.0"
        assert response["id"] == 5
        assert Map.has_key?(response, "result")
        assert response["result"]["token_type"] == "bearer"
        assert response["result"]["scope"] == "connection"
        assert response["result"]["access_token"]
        assert response["result"]["refresh_token"]
        assert response["result"]["expires_in"]
      else
        IO.puts("Skipping authentication test - credentials not available")
      end
    end
  end

  describe "client API functionality" do
    test "connects and gets server time", %{client_conn: conn} do
      time_payload = %{
        "jsonrpc" => "2.0",
        "id" => 100,
        "method" => "public/get_time",
        "params" => %{}
      }

      {:ok, response} = ClientDeribit.send_json(conn, time_payload)

      assert response["jsonrpc"] == "2.0"
      assert response["id"] == 100
      assert is_integer(response["result"])
    end

    test "trades channel subscription", %{client_conn: conn} do
      {:ok, response} = ClientDeribit.subscribe_to_trades(conn, @test_instrument)

      assert response["jsonrpc"] == "2.0"
      assert is_integer(response["id"])
      assert response["result"] == [true]
    end

    test "ticker channel subscription", %{client_conn: conn} do
      {:ok, response} = ClientDeribit.subscribe_to_ticker(conn, @test_instrument)

      assert response["jsonrpc"] == "2.0"
      assert is_integer(response["id"])
      assert response["result"] == [true]
    end

    test "authenticates client and sends authenticated request", %{
      client_conn: conn,
      credentials: credentials,
      credentials_available: creds_available
    } do
      if creds_available do
        # Authenticate
        {:ok, auth_response, _auth_state} = ClientDeribit.authenticate(conn, credentials)

        assert auth_response["result"]["token_type"] == "bearer"
        assert auth_response["result"]["access_token"]

        # Send an authenticated request (get account summary)
        account_payload = %{
          "jsonrpc" => "2.0",
          "id" => 101,
          "method" => "private/get_account_summary",
          "params" => %{
            "currency" => "BTC"
          }
        }

        {:ok, acct_response} = ClientDeribit.send_json(conn, account_payload)

        assert acct_response["jsonrpc"] == "2.0"
        assert acct_response["id"] == 101
        assert Map.has_key?(acct_response, "result")
        assert acct_response["result"]["currency"] == "BTC"
      else
        IO.puts("Skipping authenticated request test - credentials not available")
      end
    end

    test "reconnection behavior", %{client_conn: conn} do
      # First subscribe to ensure we have an active connection
      {:ok, _} = ClientDeribit.subscribe_to_ticker(conn, @test_instrument)

      # Force close the connection
      :ok = WebsockexNova.Client.close(conn)

      # Wait for automatic reconnection
      Process.sleep(3000)

      # Test that the connection is functioning again by making a simple request
      test_payload = %{
        "jsonrpc" => "2.0",
        "id" => 102,
        "method" => "public/test",
        "params" => %{}
      }

      # This should work if reconnection was successful
      {:ok, response} = ClientDeribit.send_json(conn, test_payload)

      assert response["jsonrpc"] == "2.0"
      assert response["id"] == 102
      assert Map.has_key?(response, "result")
      assert response["result"]["version"]
    end

    test "handles multiple concurrent subscriptions", %{client_conn: conn} do
      # Subscribe to multiple channels
      results =
        Enum.map(@test_channels, fn channel ->
          payload = %{
            "jsonrpc" => "2.0",
            "id" => System.unique_integer([:positive]),
            "method" => "public/subscribe",
            "params" => %{
              "channels" => [channel]
            }
          }

          {:ok, response} = ClientDeribit.send_json(conn, payload)
          {channel, response["result"]}
        end)

      # Verify all subscriptions were successful
      for {channel, result} <- results do
        assert result == [true], "Failed to subscribe to channel: #{channel}"
      end
    end
  end

  # Helper functions
  defp receive_json_response(stream_ref, timeout) do
    receive do
      {:websockex_nova, {:websocket_frame, ^stream_ref, {:text, msg}}} -> Jason.decode!(msg)
    after
      timeout -> flunk("No response from Deribit API within #{timeout}ms")
    end
  end

  defp receive_json_notification(timeout) do
    receive do
      {:websockex_nova, {:websocket_frame, _stream_ref, {:text, msg}}} ->
        decoded = Jason.decode!(msg)

        if Map.has_key?(decoded, "method") and decoded["method"] == "subscription" do
          decoded
        else
          receive_json_notification(timeout)
        end
    after
      timeout -> flunk("No subscription notification received within #{timeout}ms")
    end
  end
end
