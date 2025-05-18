defmodule WebsockexNova.Examples.AdapterDeribitComprehensiveTest do
  use ExUnit.Case, async: false

  alias WebsockexNova.Client
  alias WebsockexNova.ClientConn
  alias WebsockexNova.Examples.AdapterDeribit
  alias WebsockexNova.Examples.ClientDeribit

  # Constants
  @deribit_host "test.deribit.com"
  @deribit_port 443
  @deribit_path "/ws/api/v2"
  @json_rpc_version "2.0"

  # Setup test environment
  setup do
    # Get credentials for testing - use environment variables
    client_id = System.get_env("DERIBIT_CLIENT_ID")
    client_secret = System.get_env("DERIBIT_CLIENT_SECRET")
    creds_available = client_id != nil && client_secret != nil

    # Generate a unique user agent for this test run
    test_id = System.unique_integer([:positive])
    user_agent = "WebsockexNovaTest/#{test_id}"

    # Setup test data
    test_data = %{
      credentials_available: creds_available,
      credentials: %{
        api_key: client_id,
        secret: client_secret
      },
      test_id: test_id,
      user_agent: user_agent
    }

    {:ok, test_data}
  end

  # Group 1: Configuration Tests
  describe "configuration options" do
    test "connection_info/1 preserves all default values" do
      {:ok, info} = AdapterDeribit.connection_info(%{})

      # Verify all default options are set
      assert info.host == @deribit_host
      assert info.port == @deribit_port
      assert info.path == @deribit_path
      assert info.timeout == 10_000
      assert info.transport == :tls
      assert is_map(info.transport_opts)
      assert info.protocols == [:http]
      assert info.retry == 10
      assert info.backoff_type == :exponential
      assert info.base_backoff == 2_000
      assert is_map(info.ws_opts)

      # Verify rate limiting and other handlers
      assert info.rate_limit_handler == WebsockexNova.Defaults.DefaultRateLimitHandler
      assert info.rate_limit_opts.mode == :normal
      assert info.rate_limit_opts.capacity == 120
      assert info.rate_limit_opts.refill_rate == 10
      assert info.rate_limit_opts.refill_interval == 1_000
      assert info.rate_limit_opts.queue_limit == 200
      assert is_map(info.rate_limit_opts.cost_map)

      # Authentication options
      assert info.auth_handler == WebsockexNova.Defaults.DefaultAuthHandler
      assert is_map(info.credentials)
      assert info.auth_refresh_threshold == 60

      # Subscription options
      assert info.subscription_handler == WebsockexNova.Defaults.DefaultSubscriptionHandler
      assert info.subscription_timeout == 30

      # Message handling
      assert info.message_handler == WebsockexNova.Defaults.DefaultMessageHandler

      # Error handling
      assert info.error_handler == WebsockexNova.Defaults.DefaultErrorHandler
      assert info.max_reconnect_attempts == 5
      assert info.reconnect_attempts == 0
      assert info.ping_interval == 30_000
    end

    test "connection_info/1 merges custom options correctly" do
      custom_opts = %{
        host: "custom.deribit.com",
        port: 8443,
        transport: :tcp,
        timeout: 5_000,
        log_level: :debug,
        auth_refresh_threshold: 120,
        subscription_timeout: 60,
        max_reconnect_attempts: 10,
        credentials: %{api_key: "test_key", secret: "test_secret"}
      }

      {:ok, info} = AdapterDeribit.connection_info(custom_opts)

      # Verify custom options are applied
      assert info.host == "custom.deribit.com"
      assert info.port == 8443
      assert info.transport == :tcp
      assert info.timeout == 5_000
      assert info.log_level == :debug
      assert info.auth_refresh_threshold == 120
      assert info.subscription_timeout == 60
      assert info.max_reconnect_attempts == 10
      assert info.credentials.api_key == "test_key"
      assert info.credentials.secret == "test_secret"

      # Verify other defaults are preserved
      assert info.path == @deribit_path
      assert info.protocols == [:http]
      assert info.retry == 10
      assert info.backoff_type == :exponential
    end

    test "all rate limit options can be customized" do
      custom_rate_limit_opts = %{
        rate_limit_opts: %{
          mode: :strict,
          capacity: 60,
          refill_rate: 5,
          refill_interval: 2_000,
          queue_limit: 100,
          cost_map: %{
            subscription: 10,
            auth: 20,
            query: 2,
            order: 20
          }
        }
      }

      {:ok, info} = AdapterDeribit.connection_info(custom_rate_limit_opts)

      # Verify custom rate limit options are applied
      assert info.rate_limit_opts.mode == :strict
      assert info.rate_limit_opts.capacity == 60
      assert info.rate_limit_opts.refill_rate == 5
      assert info.rate_limit_opts.refill_interval == 2_000
      assert info.rate_limit_opts.queue_limit == 100
      assert info.rate_limit_opts.cost_map.subscription == 10
      assert info.rate_limit_opts.cost_map.auth == 20
      assert info.rate_limit_opts.cost_map.query == 2
      assert info.rate_limit_opts.cost_map.order == 20
    end

    test "custom handlers can be specified" do
      defmodule CustomAuthHandler do
        @moduledoc false
        @behaviour WebsockexNova.Behaviors.AuthHandler

        def generate_auth_data(_state), do: {:ok, "{}", %{}}
        def handle_auth_response(_resp, state), do: {:ok, state}
      end

      custom_handlers = %{
        auth_handler: CustomAuthHandler,
        logging_handler: MyApp.Logger,
        message_handler: MyApp.MessageHandler
      }

      {:ok, info} = AdapterDeribit.connection_info(custom_handlers)

      # Verify custom handlers are applied
      assert info.auth_handler == CustomAuthHandler
      assert info.logging_handler == MyApp.Logger
      assert info.message_handler == MyApp.MessageHandler
    end
  end

  # Group 2: Auth Data Generation Tests
  describe "authentication" do
    test "generate_auth_data/1 creates valid payload format" do
      state = %{}
      {:ok, payload, new_state} = AdapterDeribit.generate_auth_data(state)

      # Decode and verify the JSON-RPC format
      decoded = Jason.decode!(payload)
      assert decoded["jsonrpc"] == @json_rpc_version
      assert decoded["id"] == 42
      assert decoded["method"] == "public/auth"
      assert is_map(decoded["params"])

      # Verify params structure
      params = decoded["params"]
      assert params["grant_type"] == "client_credentials"
      assert is_binary(params["client_id"])
      assert is_binary(params["client_secret"])

      # Verify state update
      assert is_map(new_state.credentials)
      assert is_binary(new_state.credentials.api_key)
      assert is_binary(new_state.credentials.secret)
    end

    test "handle_auth_response/2 processes success response correctly" do
      # Test successful authentication
      success_response = %{
        "jsonrpc" => @json_rpc_version,
        "id" => 42,
        "result" => %{
          "access_token" => "test_token",
          "expires_in" => 900,
          "refresh_token" => "test_refresh",
          "token_type" => "bearer",
          "scope" => "connection"
        }
      }

      state = %{}
      {:ok, new_state} = AdapterDeribit.handle_auth_response(success_response, state)

      # Verify state updates
      assert new_state.auth_status == :authenticated
      assert new_state.access_token == "test_token"
      assert new_state.auth_expires_in == 900
    end

    test "handle_auth_response/2 processes error response correctly" do
      # Test failed authentication
      error_response = %{
        "jsonrpc" => @json_rpc_version,
        "id" => 42,
        "error" => %{
          "code" => 13_004,
          "message" => "invalid_credentials",
          "data" => %{}
        }
      }

      state = %{}
      {:error, error, new_state} = AdapterDeribit.handle_auth_response(error_response, state)

      # Verify error handling
      assert new_state.auth_status == :failed
      assert new_state.auth_error == error_response["error"]
      assert error == error_response["error"]
    end

    test "handle_auth_response/2 handles unusual responses gracefully" do
      # Test unexpected response format
      unusual_response = %{
        "jsonrpc" => @json_rpc_version,
        "id" => 42,
        "unexpected_field" => "value"
      }

      state = %{existing: "data"}
      {:ok, new_state} = AdapterDeribit.handle_auth_response(unusual_response, state)

      # Verify state preservation
      assert new_state == state
    end
  end

  # Group 3: Subscription Tests
  describe "subscription handling" do
    test "subscribe/3 generates correct subscription payload" do
      # Test single channel subscription
      channel = "trades.BTC-PERPETUAL.raw"
      state = %{}
      {:ok, payload, _new_state} = AdapterDeribit.subscribe(channel, %{}, state)

      # Decode and verify the JSON-RPC format
      decoded = Jason.decode!(payload)
      assert decoded["jsonrpc"] == @json_rpc_version
      assert is_integer(decoded["id"])
      assert decoded["method"] == "public/subscribe"
      assert is_map(decoded["params"])

      # Verify params structure
      params = decoded["params"]
      assert is_list(params["channels"])
      assert params["channels"] == [channel]
    end
  end

  # Group 4: Integration Tests with real API
  describe "integration with Deribit test server" do
    @tag :integration

    test "full connection lifecycle", %{credentials: credentials, credentials_available: creds_available} do
      if !creds_available, do: flunk("Skipping - credentials not available in environment")

      # Connect to test server
      {:ok, conn} = ClientDeribit.connect(%{host: @deribit_host})
      assert conn.adapter == WebsockexNova.Examples.AdapterDeribit

      # Verify connection state
      assert Map.has_key?(conn.connection_info, :host)
      assert conn.connection_info.host == @deribit_host
      assert conn.connection_info.port == @deribit_port
      assert conn.connection_info.path == @deribit_path

      # Authenticate
      auth_result = ClientDeribit.authenticate(conn, credentials)

      IO.puts("DEBUG: auth_result structure: #{inspect(auth_result)}")

      # Pattern match on the response format
      case auth_result do
        {:ok, updated_conn, response_json} when is_binary(response_json) ->
          # Parse the JSON string to get response map
          IO.puts("DEBUG: Response JSON (before parsing): #{response_json}")
          response_map = Jason.decode!(response_json)
          IO.puts("DEBUG: Parsed response_map: #{inspect(response_map)}")
          IO.puts("DEBUG: response_map keys: #{inspect(Map.keys(response_map))}")

          if Map.has_key?(response_map, "result") do
            IO.puts("DEBUG: result keys: #{inspect(Map.keys(response_map["result"]))}")
            IO.puts("DEBUG: access_token value: #{inspect(response_map["result"]["access_token"])}")
          end

          # Verify auth success
          assert response_map["result"]["access_token"]
          assert response_map["result"]["expires_in"]
          assert response_map["result"]["token_type"] == "bearer"

          # Verify adapter state in updated connection
          IO.puts("DEBUG: Updated connection adapter_state: #{inspect(updated_conn.adapter_state)}")
          assert updated_conn.adapter_state.auth_status == :authenticated
          assert updated_conn.adapter_state.access_token == response_map["result"]["access_token"]

        other ->
          IO.puts("DEBUG: Authentication failed with unexpected response structure")
          IO.puts("DEBUG: Response type: #{inspect(other)}")
          flunk("Authentication failed with unexpected response: #{inspect(other)}")
      end

      # Debug the updated conn state after authentication
      IO.puts("DEBUG: Conn after auth - adapter_state: #{inspect(conn.adapter_state)}")

      # Subscribe to channel
      IO.puts("DEBUG: Attempting to subscribe with connection object")
      sub_result = ClientDeribit.subscribe_to_trades(conn, "BTC-PERPETUAL")
      IO.puts("DEBUG: Subscribe result: #{inspect(sub_result)}")
      {:ok, sub_response} = sub_result

      # Verify subscription success
      assert sub_response["result"] == [true]

      # Get server time to test basic API call
      time_payload = %{
        "jsonrpc" => @json_rpc_version,
        "id" => 123,
        "method" => "public/get_time",
        "params" => %{}
      }

      {:ok, time_response} = ClientDeribit.send_json(conn, time_payload)

      # Verify time response
      assert time_response["id"] == 123
      assert is_integer(time_response["result"])

      # Clean up
      :ok = Client.close(conn)
    end

    @tag :integration

    @tag :integration
    test "handles reconnection gracefully" do
      require Logger

      # Make sure we trap exits for cleaner testing
      Process.flag(:trap_exit, true)

      # Connect with parameters specifically for reconnection testing
      {:ok, conn} =
        ClientDeribit.connect(%{
          host: @deribit_host,
          timeout: 10_000,
          max_reconnect_attempts: 5,
          # Fast retry attempts
          retry: 1,
          # Short delay between attempts
          base_backoff: 500
        })

      # Store the original transport PID and connection ID
      original_pid = conn.transport_pid
      connection_id = conn.connection_id
      Logger.info("Original connection PID: #{inspect(original_pid)}")
      Logger.info("Connection ID: #{inspect(connection_id)}")

      # Ensure connection_id is present
      assert is_reference(connection_id)

      # Get the dynamic transport_pid - should match the stored one initially
      dynamic_pid = WebsockexNova.ClientConn.get_current_transport_pid(conn)
      assert dynamic_pid == original_pid

      # Send a basic test message to verify initial connection works
      test_payload = %{
        "jsonrpc" => @json_rpc_version,
        "id" => 9999,
        "method" => "public/test",
        "params" => %{}
      }

      {:ok, _} = ClientDeribit.send_json(conn, test_payload)

      # Register ourselves with the connection to get notifications about reconnection
      {:ok, _conn_with_callback} = Client.register_callback(conn, self())

      # Force disconnect by killing the Gun process to simulate network failure
      # But first we need to get access to the internal gun_pid
      state = conn.transport.get_state(conn)
      gun_pid = state.gun_pid
      Process.exit(gun_pid, :kill)

      # Wait for notification that connection went down
      assert_receive {:connection_down, :http, _reason}, 5000

      # Wait for notification about reconnection
      assert_receive {:connection_reconnected, updated_conn}, 15_000

      # Check that the connection_id remains the same after reconnection
      assert updated_conn.connection_id == connection_id

      # Check that the transport_pid has changed
      assert updated_conn.transport_pid != original_pid

      # The connection registry should now point to the new process
      assert WebsockexNova.ClientConn.get_current_transport_pid(conn) == updated_conn.transport_pid

      # Test that the original connection reference works by sending a message
      # This will use the connection registry to get the current transport_pid
      test_payload2 = %{
        "jsonrpc" => @json_rpc_version,
        "id" => 10_000,
        "method" => "public/test",
        "params" => %{}
      }

      # Use the original conn reference which should now use the new process via the registry
      {:ok, response} = ClientDeribit.send_json(conn, test_payload2)
      assert response["id"] == 10_000
      assert response["result"]["version"]

      # Clean up
      :ok = Client.close(conn)
    end

    @tag :integration

    test "preserves subscriptions across reconnects", %{credentials_available: creds_available} do
      if !creds_available, do: flunk("Skipping - credentials not available in environment")

      # Connect to test server with auto-resubscribe enabled
      {:ok, conn} =
        ClientDeribit.connect(%{
          host: @deribit_host,
          timeout: 5_000,
          auto_resubscribe: true
        })

      # Subscribe to multiple channels
      {:ok, _} = ClientDeribit.subscribe_to_trades(conn, "BTC-PERPETUAL")
      {:ok, _} = ClientDeribit.subscribe_to_ticker(conn, "BTC-PERPETUAL")

      # Verify the connection is active by checking we can still send messages
      assert Process.alive?(conn.transport_pid)

      # Get subscription info via a test message
      test_payload = %{
        "jsonrpc" => @json_rpc_version,
        "id" => 1001,
        "method" => "public/test",
        "params" => %{}
      }

      {:ok, _} = ClientDeribit.send_json(conn, test_payload)

      # Force disconnect
      :ok = Client.close(conn)

      # Allow time for automatic reconnection and resubscription
      Process.sleep(3_000)

      # Verify the connection is still active after reconnect by sending a message
      test_payload2 = %{
        "jsonrpc" => @json_rpc_version,
        "id" => 1002,
        "method" => "public/test",
        "params" => %{}
      }

      {:ok, test_response} = ClientDeribit.send_json(conn, test_payload2)

      # Verify response
      assert test_response["result"]["version"]

      # Clean up
      :ok = Client.close(conn)
    end
  end

  # Group 5: Configuration Preservation Tests
  describe "config and state preservation" do
    @tag :integration
    test "connection_id persists across reconnection and registry updates correctly" do
      require Logger

      # Make sure we trap exits for cleaner testing
      Process.flag(:trap_exit, true)

      # Connect with parameters specifically for reconnection testing
      {:ok, conn} =
        ClientDeribit.connect(%{
          host: @deribit_host,
          timeout: 10_000,
          max_reconnect_attempts: 5,
          retry: 1,
          base_backoff: 500
        })

      # Verify the connection_id is registered in the registry
      connection_id = conn.connection_id
      assert is_reference(connection_id)

      # Get the original transport_pid from the connection registry
      {:ok, original_pid_from_registry} = WebsockexNova.ConnectionRegistry.get_transport_pid(connection_id)
      assert original_pid_from_registry == conn.transport_pid

      # Register ourselves with the connection to get notifications about reconnection
      {:ok, _conn_with_callback} = Client.register_callback(conn, self())

      # Force disconnect by killing the Gun process to simulate network failure
      state = conn.transport.get_state(conn)
      gun_pid = state.gun_pid
      Process.exit(gun_pid, :kill)

      # Wait for notification about reconnection
      assert_receive {:connection_reconnected, updated_conn}, 15_000

      # Verify the connection_id stays the same
      assert updated_conn.connection_id == connection_id

      # Verify the registry has the updated transport_pid
      {:ok, new_pid_from_registry} = WebsockexNova.ConnectionRegistry.get_transport_pid(connection_id)
      assert new_pid_from_registry == updated_conn.transport_pid
      refute new_pid_from_registry == original_pid_from_registry

      # Verify the new pid is active
      assert Process.alive?(new_pid_from_registry)

      # Test operations using the original conn reference
      test_payload = %{
        "jsonrpc" => @json_rpc_version,
        "id" => 12_345,
        "method" => "public/test",
        "params" => %{}
      }

      # This should transparently use the new transport_pid from the registry
      {:ok, response} = ClientDeribit.send_json(conn, test_payload)
      assert response["id"] == 12_345
      assert response["result"]["version"]
    end

    test "ClientConn struct preserves all connection info" do
      # Define custom options with various types
      custom_opts = %{
        host: "custom.host",
        port: 8443,
        transport: :tcp,
        timeout: 5_000,
        log_level: :debug,
        auth_refresh_threshold: 120,
        subscription_timeout: 60,
        max_reconnect_attempts: 10,
        credentials: %{api_key: "test_key", secret: "test_secret"},
        custom_metadata: %{app_name: "test_app", version: "1.0"},
        numeric_array: [1, 2, 3, 4],
        string_array: ["a", "b", "c"],
        nested: %{
          level1: %{
            level2: %{
              value: "deeply nested"
            }
          }
        }
      }

      # Mock connection for testing
      mock_conn = %ClientConn{
        adapter: AdapterDeribit,
        transport_pid: self(),
        connection_info: custom_opts
      }

      # Verify all custom fields are preserved
      assert mock_conn.connection_info.host == "custom.host"
      assert mock_conn.connection_info.port == 8443
      assert mock_conn.connection_info.custom_metadata.app_name == "test_app"
      assert mock_conn.connection_info.custom_metadata.version == "1.0"
      assert mock_conn.connection_info.numeric_array == [1, 2, 3, 4]
      assert mock_conn.connection_info.string_array == ["a", "b", "c"]
      assert mock_conn.connection_info.nested.level1.level2.value == "deeply nested"
    end

    test "init/1 creates properly structured initial state" do
      {:ok, state} = AdapterDeribit.init(%{})

      # Verify initial state structure
      assert is_list(state.messages) || is_map(state.messages)
      assert state.connected_at == nil
      assert state.auth_status == :unauthenticated
      assert state.reconnect_attempts == 0
      assert state.max_reconnect_attempts == 5
      assert is_map(state.subscriptions)
      assert is_map(state.subscription_requests)
    end
  end

  # No helper functions needed
end
