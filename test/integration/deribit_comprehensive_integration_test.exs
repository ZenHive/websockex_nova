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

    # Configure TLS for secure connection - must be a keyword list, not a map
    transport_opts = [
      verify: :verify_peer,
      cacerts: :certifi.cacerts(),
      server_name_indication: ~c"test.deribit.com"
    ]

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
    # ClientDeribit.connect will use the adapter's default configuration
    {:ok, client_conn} = ClientDeribit.connect(%{host: @host})

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
      # Note: build_number may not always be present in the response
    end

    test "subscribes to public channels", %{raw_conn: conn} do
      # Subscribe to a truly public channel (no auth required)
      # Book data is public
      test_channel = "book.#{@test_instrument}.100ms"

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

      # The result should be the list of subscribed channels, not [true]
      assert response["result"] == [test_channel]

      # Wait for a notification from the subscribed channel
      # Note: May timeout if no market data is available
      case receive_json_notification(2000) do
        notification when is_map(notification) ->
          # Verify notification format
          assert notification["jsonrpc"] == "2.0"
          assert notification["method"] == "subscription"
          assert Map.has_key?(notification, "params")
          assert notification["params"]["channel"] == test_channel

        _ ->
          # It's okay if we timeout waiting for market data
          true
      end
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
        assert String.contains?(response["result"]["scope"], "connection")
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

      {:ok, response_json} = ClientDeribit.send_json(conn, time_payload)
      response = Jason.decode!(response_json)

      assert response["jsonrpc"] == "2.0"
      assert response["id"] == 100
      assert is_integer(response["result"])
    end

    test "trades channel subscription", %{
      client_conn: conn,
      credentials: credentials,
      credentials_available: creds_available
    } do
      # For raw channels, we need to authenticate first
      updated_conn =
        if creds_available do
          {:ok, authenticated_conn, _} = ClientDeribit.authenticate(conn, credentials)
          authenticated_conn
        else
          conn
        end

      {:ok, response_json} = ClientDeribit.subscribe_to_trades(updated_conn, @test_instrument)
      response = Jason.decode!(response_json)

      assert response["jsonrpc"] == "2.0"
      assert is_integer(response["id"])

      # If we're authenticated, we should get the subscribed channel(s), otherwise error
      if creds_available do
        assert response["result"] == ["trades.#{@test_instrument}.raw"]
      else
        assert response["error"]["code"] == 13_778
      end
    end

    test "ticker channel subscription", %{
      client_conn: conn,
      credentials: credentials,
      credentials_available: creds_available
    } do
      # For raw channels, we need to authenticate first
      updated_conn =
        if creds_available do
          {:ok, authenticated_conn, _} = ClientDeribit.authenticate(conn, credentials)
          authenticated_conn
        else
          conn
        end

      {:ok, response_json} = ClientDeribit.subscribe_to_ticker(updated_conn, @test_instrument)
      response = Jason.decode!(response_json)

      assert response["jsonrpc"] == "2.0"
      assert is_integer(response["id"])

      # If we're authenticated, we should get the subscribed channel(s), otherwise error
      if creds_available do
        assert response["result"] == ["ticker.#{@test_instrument}.raw"]
      else
        assert response["error"]["code"] == 13_778
      end
    end

    test "authenticates client and sends authenticated request", %{
      client_conn: conn,
      credentials: credentials,
      credentials_available: creds_available
    } do
      if creds_available do
        # Authenticate
        auth_result = ClientDeribit.authenticate(conn, credentials)
        IO.inspect(auth_result, label: "Auth result")

        {:ok, updated_conn, json_response} = auth_result

        # The raw response is a JSON string, we need to decode it
        parsed_response = Jason.decode!(json_response)
        assert parsed_response["result"]["token_type"] == "bearer"
        assert parsed_response["result"]["access_token"]

        # Also verify the access token is stored in the adapter state
        assert updated_conn.adapter_state.access_token
        assert updated_conn.adapter_state.auth_status == :authenticated

        # Send an authenticated request (get account summary)
        # Note: For Deribit, we need to include the access token in the params
        account_payload = %{
          "jsonrpc" => "2.0",
          "id" => 101,
          "method" => "private/get_account_summary",
          "params" => %{
            "currency" => "BTC",
            "access_token" => updated_conn.adapter_state.access_token
          }
        }

        {:ok, acct_response_json} = ClientDeribit.send_json(updated_conn, account_payload)

        # send_json returns a JSON string, need to decode it
        acct_response = Jason.decode!(acct_response_json)

        assert acct_response["jsonrpc"] == "2.0"
        assert acct_response["id"] == 101
        assert Map.has_key?(acct_response, "result")
        assert acct_response["result"]["currency"] == "BTC"
      else
        IO.puts("Skipping authenticated request test - credentials not available")
      end
    end

    test "reconnection behavior", %{credentials: credentials, credentials_available: creds_available} do
      # Create a new connection to test reconnection
      {:ok, conn} = ClientDeribit.connect(%{host: @host})

      # Authenticate if credentials are available
      if creds_available do
        {:ok, _conn, _} = ClientDeribit.authenticate(conn, credentials)
      end

      # Make a simple request to ensure connection is working
      test_payload = %{
        "jsonrpc" => "2.0",
        "id" => 101,
        "method" => "public/test",
        "params" => %{}
      }

      {:ok, response_json} = ClientDeribit.send_json(conn, test_payload)
      response = Jason.decode!(response_json)
      assert response["jsonrpc"] == "2.0"
      assert response["id"] == 101

      # Note: WebsockexNova doesn't support automatic reconnection after explicit close.
      # To test reconnection, we would need to simulate network failures or
      # implement a reconnection mechanism in the adapter.

      # Close the connection
      :ok = WebsockexNova.Client.close(conn)
    end

    test "handles multiple concurrent subscriptions", %{
      client_conn: conn,
      credentials: credentials,
      credentials_available: creds_available
    } do
      # For raw channels, we need to authenticate first
      updated_conn =
        if creds_available do
          {:ok, authenticated_conn, _} = ClientDeribit.authenticate(conn, credentials)
          authenticated_conn
        else
          conn
        end

      # Subscribe to multiple channels
      results =
        Enum.map(@test_channels, fn channel ->
          # Determine if this is a raw channel that needs authentication
          needs_auth = String.contains?(channel, ".raw")
          
          # Use the appropriate method based on channel type and authentication status
          method = if needs_auth && creds_available && updated_conn.adapter_state[:access_token] do
            "private/subscribe"
          else
            "public/subscribe"
          end
          
          # Build the payload
          params = %{"channels" => [channel]}
          params = if needs_auth && creds_available && updated_conn.adapter_state[:access_token] do
            Map.put(params, "access_token", updated_conn.adapter_state[:access_token])
          else
            params
          end
          
          req_id = System.unique_integer([:positive])
          payload = %{
            "jsonrpc" => "2.0",
            "id" => req_id,
            "method" => method,
            "params" => params
          }

          # Send the subscription with custom matcher to filter by ID
          options = %{
            matcher: fn msg ->
              case msg do
                {:websockex_nova, {:websocket_frame, _ref, {:text, response_json}}} ->
                  response = Jason.decode!(response_json)
                  if response["id"] == req_id do
                    {:ok, response_json}
                  else
                    :skip
                  end
                _ ->
                  :skip
              end
            end
          }
          
          {:ok, response_json} = ClientDeribit.send_json(updated_conn, payload, options)
          response = Jason.decode!(response_json)
          {channel, response}
        end)

      # Verify all subscriptions were successful (or failed as expected if not authenticated)
      for {channel, response} <- results do
        needs_auth = String.contains?(channel, ".raw")
        
        if needs_auth && !creds_available do
          # Raw channels without auth should fail with error 13778
          assert response["error"]["code"] == 13_778, "Expected unauthorized error for channel: #{channel}"
        else
          # All other cases (public channels or authenticated raw channels) should succeed
          # Let's add some debug output to see what we're getting
          if !response["result"] || response["result"] != [channel] do
            IO.inspect(response, label: "Response for #{channel}")
          end
          assert response["result"] == [channel], "Failed to subscribe to channel: #{channel}"
        end
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
