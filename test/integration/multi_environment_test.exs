defmodule WebsockexNew.Integration.MultiEnvironmentTest do
  @moduledoc """
  Tests WebSocket client functionality across multiple environments.
  
  Validates that the client works consistently across:
  - Different WebSocket servers (Deribit, Binance, etc.)
  - Local test servers with various configurations
  - Mock servers with different behaviors
  - Various network conditions and protocols
  """

  use ExUnit.Case, async: false
  
  import WebsockexNew.ApiTestHelpers
  
  alias WebsockexNew.{Client, TestEnvironment, TestData}
  
  @moduletag :integration
  @moduletag timeout: 120_000

  setup_all do
    # Ensure test infrastructure is available
    start_supervised({Registry, keys: :unique, name: :network_simulators})
    start_supervised({Registry, keys: :unique, name: :configurable_servers})
    :ok
  end

  describe "environment compatibility" do
    test "deribit test environment connectivity" do
      with_real_api(:deribit_test, [], fn config ->
        {:ok, client} = Client.connect(config.endpoint)
        
        # Test Deribit-specific features
        auth_message = TestData.auth_messages().valid
        :ok = Client.send_message(client, auth_message)
        
        # Test subscription to Deribit channels
        channels = ["ticker.BTC-PERPETUAL", "book.BTC-PERPETUAL.100ms"]
        assert_subscription_lifecycle(client, channels)
        
        # Verify state throughout
        assert Client.get_state(client) == :connected
        
        :ok = Client.close(client)
      end)
    end

    test "binance test environment connectivity" do
      with_real_api(:binance_test, [], fn config ->
        {:ok, client} = Client.connect(config.endpoint)
        
        # Test basic connectivity to Binance
        # Note: Binance uses different message format than Deribit
        ping_message = "{\"id\": 1, \"method\": \"ping\"}"
        :ok = Client.send_message(client, ping_message)
        
        # Verify connection stability
        Process.sleep(1000)
        assert Client.get_state(client) == :connected
        
        :ok = Client.close(client)
      end)
    end

    test "local mock server with default behavior" do
      with_real_api(:custom_mock, [], fn config ->
        {:ok, client} = Client.connect(config.endpoint)
        
        # Test with mock server's echo behavior
        test_message = "{\"test\": \"message\"}"
        :ok = Client.send_message(client, test_message)
        
        # Mock server should echo back
        Process.sleep(100)
        assert Client.get_state(client) == :connected
        
        :ok = Client.close(client)
      end)
    end

    test "configurable test server with custom behavior" do
      server_behavior = %{
        latency: 100,
        error_rate: 0.1,
        disconnect_rate: 0.0,
        message_corruption: false,
        protocol_violations: false
      }
      
      server_opts = [behavior: server_behavior]
      
      with_real_api(:local_server, [server_opts: server_opts], fn config ->
        {:ok, client} = Client.connect(config.endpoint)
        
        # Send multiple messages to test behavior
        messages = TestData.heartbeat_messages()
        Enum.each(messages, fn message ->
          :ok = Client.send_message(client, message)
          Process.sleep(150)  # Account for configured latency
        end)
        
        assert Client.get_state(client) == :connected
        :ok = Client.close(client)
      end)
    end
  end

  describe "protocol compatibility" do
    test "handles JSON-RPC 2.0 protocol" do
      with_real_api(:deribit_test, [], fn config ->
        {:ok, client} = Client.connect(config.endpoint)
        
        # Test JSON-RPC 2.0 messages
        json_rpc_messages = TestData.protocol_specific_data(:json_rpc)
        
        Enum.each(json_rpc_messages, fn message ->
          :ok = Client.send_message(client, message)
          Process.sleep(50)
        end)
        
        assert Client.get_state(client) == :connected
        :ok = Client.close(client)
      end)
    end

    test "handles custom protocol messages" do
      with_real_api(:local_server, [], fn config ->
        {:ok, client} = Client.connect(config.endpoint)
        
        # Test custom protocol messages
        custom_messages = TestData.protocol_specific_data(:custom)
        
        Enum.each(custom_messages, fn message ->
          :ok = Client.send_message(client, message)
          Process.sleep(10)
        end)
        
        assert Client.get_state(client) == :connected
        :ok = Client.close(client)
      end)
    end

    test "handles binary data protocols" do
      with_real_api(:local_server, [], fn config ->
        {:ok, client} = Client.connect(config.endpoint)
        
        # Test binary messages
        binary_messages = TestData.binary_test_data()
        
        # Filter out extremely large messages for this test
        test_messages = Enum.filter(binary_messages, fn msg ->
          byte_size(msg) < 10_000
        end)
        
        Enum.each(test_messages, fn message ->
          :ok = Client.send_message(client, message)
          Process.sleep(10)
        end)
        
        assert Client.get_state(client) == :connected
        :ok = Client.close(client)
      end)
    end
  end

  describe "environment health monitoring" do
    test "reports health status for all environments" do
      health_status = TestEnvironment.health_check_all()
      
      # Should report status for available environments
      assert is_map(health_status)
      
      # Check that we get reasonable status values
      Enum.each(health_status, fn {env, status} ->
        assert env in [:deribit_test, :binance_test]
        assert status in [:healthy, :unhealthy, :unknown]
      end)
    end

    test "environment setup and teardown" do
      # Test each environment's setup/teardown cycle
      environments = [:deribit_test, :custom_mock, :local_server]
      
      Enum.each(environments, fn env ->
        case TestEnvironment.setup_environment(env, skip_health_check: true) do
          {:ok, config} ->
            # Environment setup succeeded
            assert is_binary(config.endpoint)
            
            # Clean teardown
            :ok = TestEnvironment.teardown_environment(config)
            
          {:error, {:missing_env_var, _var}} ->
            # Expected for environments requiring credentials
            :ok
            
          {:error, reason} ->
            flunk("Environment #{env} setup failed: #{inspect(reason)}")
        end
      end)
    end

    test "environment configuration retrieval" do
      available_envs = TestEnvironment.list_environments()
      
      assert :deribit_test in available_envs
      assert :binance_test in available_envs
      assert :custom_mock in available_envs
      assert :local_server in available_envs
      
      # Test configuration retrieval
      Enum.each(available_envs, fn env ->
        {:ok, config} = TestEnvironment.get_environment_config(env)
        
        assert is_map(config)
        assert Map.has_key?(config, :timeout)
        assert Map.has_key?(config, :tls)
        assert Map.has_key?(config, :protocols)
      end)
    end
  end

  describe "cross-environment consistency" do
    test "connection lifecycle consistency across environments" do
      # Test that basic connection lifecycle works the same way
      # across different environments
      
      test_environments = [
        {:custom_mock, []},
        {:local_server, []}
      ]
      
      Enum.each(test_environments, fn {env, opts} ->
        with_real_api(env, opts, fn config ->
          # Standard connection lifecycle
          {:ok, client} = Client.connect(config.endpoint)
          assert_connection_lifecycle(client)
        end)
      end)
    end

    test "message sending consistency" do
      # Test that message sending works consistently
      test_message = TestData.heartbeat_messages() |> hd()
      
      test_environments = [
        {:custom_mock, []},
        {:local_server, []}
      ]
      
      Enum.each(test_environments, fn {env, opts} ->
        with_real_api(env, opts, fn config ->
          {:ok, client} = Client.connect(config.endpoint)
          
          # Should be able to send message without error
          :ok = Client.send_message(client, test_message)
          
          # Connection should remain stable
          Process.sleep(100)
          assert Client.get_state(client) == :connected
          
          :ok = Client.close(client)
        end)
      end)
    end

    test "error handling consistency" do
      # Test that error handling works consistently across environments
      malformed_message = TestData.malformed_messages() |> hd()
      
      test_environments = [
        {:custom_mock, []},
        {:local_server, []}
      ]
      
      Enum.each(test_environments, fn {env, opts} ->
        with_real_api(env, opts, fn config ->
          {:ok, client} = Client.connect(config.endpoint)
          
          # Send malformed message
          :ok = Client.send_message(client, malformed_message)
          
          # Client should handle error gracefully
          Process.sleep(200)
          assert Client.get_state(client) == :connected
          
          # Should still be able to send valid messages
          valid_message = TestData.heartbeat_messages() |> hd()
          :ok = Client.send_message(client, valid_message)
          
          :ok = Client.close(client)
        end)
      end)
    end
  end

  describe "environment-specific features" do
    test "deribit authentication flow" do
      with_real_api(:deribit_test, [], fn config ->
        {:ok, client} = Client.connect(config.endpoint)
        
        # Test Deribit-specific authentication
        auth_message = %{
          id: 1,
          method: "public/auth",
          params: %{
            grant_type: "client_credentials",
            client_id: config.auth[:client_id] || "test_client",
            client_secret: config.auth[:client_secret] || "test_secret"
          }
        } |> Jason.encode!()
        
        :ok = Client.send_message(client, auth_message)
        
        # Allow time for authentication response
        Process.sleep(2000)
        assert Client.get_state(client) == :connected
        
        :ok = Client.close(client)
      end)
    end

    test "configurable server error injection" do
      # Test configurable server's error injection capabilities
      server_opts = [
        behavior: %{
          latency: 0,
          error_rate: 0.5,  # 50% error rate
          disconnect_rate: 0.0
        }
      ]
      
      with_real_api(:local_server, [server_opts: server_opts], fn config ->
        {:ok, client} = Client.connect(config.endpoint)
        
        # Extract port from endpoint for error injection
        port = case URI.parse(config.endpoint) do
          %URI{port: p} when is_integer(p) -> p
          _ -> nil
        end
        
        if port do
          # Inject specific error
          :ok = WebsockexNew.ConfigurableTestServer.inject_error(port, :send_invalid_frame)
          
          # Send message after error injection
          message = TestData.heartbeat_messages() |> hd()
          :ok = Client.send_message(client, message)
          
          Process.sleep(200)
          
          # Client should handle the injected error
          assert Client.get_state(client) in [:connected, :disconnected]
        end
        
        if Client.get_state(client) == :connected do
          :ok = Client.close(client)
        end
      end)
    end

    test "mock server statistics collection" do
      with_real_api(:custom_mock, [], fn config ->
        {:ok, client} = Client.connect(config.endpoint)
        
        # Send several messages
        messages = TestData.stress_test_messages(10)
        Enum.each(messages, fn message ->
          :ok = Client.send_message(client, message)
          Process.sleep(10)
        end)
        
        # Mock server should have collected statistics
        # (This would require enhancing the mock server to expose stats)
        
        :ok = Client.close(client)
      end)
    end
  end

  describe "load balancing and failover" do
    test "multiple server instances" do
      # Start multiple server instances
      server_configs = [
        [port: 0, behavior: %{latency: 50}],
        [port: 0, behavior: %{latency: 100}],
        [port: 0, behavior: %{latency: 150}]
      ]
      
      servers = Enum.map(server_configs, fn config ->
        {:ok, port} = WebsockexNew.ConfigurableTestServer.start_server(config)
        port
      end)
      
      try do
        # Test connecting to each server
        Enum.each(servers, fn port ->
          endpoint = "ws://localhost:#{port}/ws"
          {:ok, client} = Client.connect(endpoint)
          
          # Test basic functionality
          message = TestData.heartbeat_messages() |> hd()
          :ok = Client.send_message(client, message)
          
          assert Client.get_state(client) == :connected
          :ok = Client.close(client)
        end)
        
      after
        # Clean up servers
        Enum.each(servers, fn port ->
          WebsockexNew.ConfigurableTestServer.stop_server(port)
        end)
      end
    end

    test "failover behavior simulation" do
      # Start primary and backup servers
      {:ok, primary_port} = WebsockexNew.ConfigurableTestServer.start_server([
        behavior: %{latency: 0, error_rate: 0.0}
      ])
      
      {:ok, backup_port} = WebsockexNew.ConfigurableTestServer.start_server([
        behavior: %{latency: 50, error_rate: 0.0}
      ])
      
      try do
        # Connect to primary
        primary_endpoint = "ws://localhost:#{primary_port}/ws"
        {:ok, client} = Client.connect(primary_endpoint)
        
        # Verify primary connection
        message = TestData.heartbeat_messages() |> hd()
        :ok = Client.send_message(client, message)
        assert Client.get_state(client) == :connected
        
        # Simulate primary failure
        WebsockexNew.ConfigurableTestServer.inject_error(primary_port, :disconnect_all)
        
        # In a real failover scenario, the client would reconnect to backup
        # For now, just verify the client handles the disconnection
        Process.sleep(500)
        
        # Client should detect the disconnection
        final_state = Client.get_state(client)
        assert final_state in [:disconnected, :connecting]
        
        # Test backup server independently
        backup_endpoint = "ws://localhost:#{backup_port}/ws"
        {:ok, backup_client} = Client.connect(backup_endpoint)
        
        :ok = Client.send_message(backup_client, message)
        assert Client.get_state(backup_client) == :connected
        
        :ok = Client.close(backup_client)
        
      after
        WebsockexNew.ConfigurableTestServer.stop_server(primary_port)
        WebsockexNew.ConfigurableTestServer.stop_server(backup_port)
      end
    end
  end
end