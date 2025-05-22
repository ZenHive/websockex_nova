defmodule WebsockexNew.Integration.ComprehensiveLifecycleTest do
  @moduledoc """
  Comprehensive test scenarios covering the complete client lifecycle.
  
  Tests the full range of WebSocket client operations including:
  - Connection establishment and teardown
  - Authentication flows
  - Subscription management
  - Error handling and recovery
  - Network condition resilience
  - Performance characteristics
  """

  use ExUnit.Case, async: false
  
  import WebsockexNew.ApiTestHelpers
  
  alias WebsockexNew.{Client, TestEnvironment, TestData, NetworkSimulator}
  
  @moduletag :integration
  @moduletag timeout: 60_000

  setup_all do
    # Ensure registries are available for test infrastructure
    start_supervised({Registry, keys: :unique, name: :network_simulators})
    start_supervised({Registry, keys: :unique, name: :configurable_servers})
    :ok
  end

  describe "complete client lifecycle" do
    test "deribit full lifecycle with real API" do
      with_real_api(:deribit_test, [], fn config ->
        # Step 1: Connect to endpoint
        {:ok, client} = Client.connect(config.endpoint)
        assert_connection_lifecycle(client)
        
        # Step 2: Test basic message sending
        auth_message = TestData.auth_messages().valid
        :ok = Client.send_message(client, auth_message)
        
        # Step 3: Test subscription flow
        subscription_channels = ["ticker.BTC-PERPETUAL"]
        assert_subscription_lifecycle(client, subscription_channels)
        
        # Step 4: Verify client state throughout
        assert Client.get_state(client) == :connected
        
        # Step 5: Clean shutdown
        :ok = Client.close(client)
        assert eventually(fn -> Client.get_state(client) == :disconnected end)
      end)
    end

    test "local server full lifecycle with custom behavior" do
      server_opts = [
        behavior: %{
          latency: 50,
          error_rate: 0.0,
          disconnect_rate: 0.0
        }
      ]
      
      with_real_api(:local_server, [server_opts: server_opts], fn config ->
        # Connect and test full lifecycle
        {:ok, client} = Client.connect(config.endpoint)
        
        # Test message patterns
        messages = TestData.subscription_messages()
        Enum.each(messages, fn message ->
          :ok = Client.send_message(client, message)
          Process.sleep(10)  # Allow processing
        end)
        
        # Verify connection stability
        assert Client.get_state(client) == :connected
        
        :ok = Client.close(client)
      end)
    end
  end

  describe "error handling and recovery" do
    test "handles authentication failures gracefully" do
      with_real_api(:deribit_test, [], fn config ->
        {:ok, client} = Client.connect(config.endpoint)
        
        # Send invalid authentication
        invalid_auth = TestData.auth_messages().invalid
        :ok = Client.send_message(client, invalid_auth)
        
        # Client should remain connected despite auth failure
        Process.sleep(1000)
        assert Client.get_state(client) == :connected
        
        :ok = Client.close(client)
      end)
    end

    test "recovers from malformed messages" do
      with_real_api(:local_server, [], fn config ->
        {:ok, client} = Client.connect(config.endpoint)
        
        # Send various malformed messages
        malformed_messages = TestData.malformed_messages()
        Enum.each(malformed_messages, fn message ->
          # These should not crash the client
          :ok = Client.send_message(client, message)
          Process.sleep(10)
        end)
        
        # Client should still be connected
        assert Client.get_state(client) == :connected
        
        # Should still be able to send valid messages
        valid_message = TestData.heartbeat_messages() |> hd()
        :ok = Client.send_message(client, valid_message)
        
        :ok = Client.close(client)
      end)
    end

    test "handles server errors and continues operation" do
      server_opts = [
        behavior: %{
          latency: 0,
          error_rate: 0.3,  # 30% error rate
          disconnect_rate: 0.0
        }
      ]
      
      with_real_api(:local_server, [server_opts: server_opts], fn config ->
        {:ok, client} = Client.connect(config.endpoint)
        
        # Send multiple messages, some will trigger errors
        messages = TestData.stress_test_messages(20)
        Enum.each(messages, fn message ->
          :ok = Client.send_message(client, message)
          Process.sleep(10)
        end)
        
        # Client should remain operational
        assert Client.get_state(client) == :connected
        
        :ok = Client.close(client)
      end)
    end
  end

  describe "network condition resilience" do
    test "handles slow network conditions" do
      with_real_api(:local_server, [], fn config ->
        {:ok, client} = Client.connect(config.endpoint)
        
        # Start network simulation
        {:ok, _simulator} = NetworkSimulator.simulate_condition(
          client, 
          :slow_connection,
          duration: 10_000
        )
        
        # Send messages during slow conditions
        messages = TestData.heartbeat_messages()
        Enum.each(messages, fn message ->
          {_result, time_us} = measure_performance(fn ->
            Client.send_message(client, message)
          end)
          
          # Messages should still be sent, but may be slower
          assert time_us < 10_000_000  # Less than 10 seconds
        end)
        
        # Restore normal conditions
        NetworkSimulator.restore_normal_conditions(client)
        
        :ok = Client.close(client)
      end)
    end

    test "recovers from intermittent connectivity" do
      with_real_api(:local_server, [], fn config ->
        {:ok, client} = Client.connect(config.endpoint)
        
        # Simulate intermittent connection
        {:ok, _simulator} = NetworkSimulator.simulate_condition(
          client,
          :intermittent,
          duration: 5_000
        )
        
        # Continue sending messages
        messages = TestData.subscription_messages()
        Enum.each(messages, fn message ->
          :ok = Client.send_message(client, message)
          Process.sleep(100)  # Allow for network disruption
        end)
        
        # Client should either stay connected or reconnect
        # (depending on implementation)
        final_state = Client.get_state(client)
        assert final_state in [:connected, :connecting, :disconnected]
        
        NetworkSimulator.restore_normal_conditions(client)
        
        if final_state != :disconnected do
          :ok = Client.close(client)
        end
      end)
    end

    test "handles high packet loss scenarios" do
      with_real_api(:local_server, [], fn config ->
        {:ok, client} = Client.connect(config.endpoint)
        
        # Simulate packet loss
        {:ok, _simulator} = NetworkSimulator.simulate_condition(
          client,
          :packet_loss,
          custom_config: %{packet_loss_rate: 0.1}  # 10% loss
        )
        
        # Send messages and verify some get through
        success_count = Enum.reduce(1..20, 0, fn _i, acc ->
          message = TestData.heartbeat_messages() |> hd()
          
          try do
            :ok = Client.send_message(client, message)
            acc + 1
          rescue
            _ -> acc
          end
        end)
        
        # At least some messages should succeed
        assert success_count > 0
        
        NetworkSimulator.restore_normal_conditions(client)
        :ok = Client.close(client)
      end)
    end
  end

  describe "performance characteristics" do
    test "measures connection establishment time" do
      with_real_api(:local_server, [], fn config ->
        {_result, connection_time} = measure_performance(fn ->
          {:ok, client} = Client.connect(config.endpoint)
          client
        end)
        
        # Connection should be reasonably fast (less than 1 second)
        assert connection_time < 1_000_000  # 1 second in microseconds
        
        # Note: We can't close the client here since it's in the result
        # The with_real_api helper will handle cleanup
      end)
    end

    test "measures message throughput" do
      with_real_api(:local_server, [], fn config ->
        {:ok, client} = Client.connect(config.endpoint)
        
        # Measure time to send multiple messages
        message_count = 100
        messages = TestData.stress_test_messages(message_count)
        
        {_result, total_time} = measure_performance(fn ->
          Enum.each(messages, fn message ->
            :ok = Client.send_message(client, message)
          end)
        end)
        
        # Calculate throughput
        throughput = (message_count * 1_000_000) / total_time
        
        # Should handle at least 50 messages per second
        assert throughput > 50.0
        
        :ok = Client.close(client)
      end)
    end

    test "handles large message sizes" do
      with_real_api(:local_server, [], fn config ->
        {:ok, client} = Client.connect(config.endpoint)
        
        # Test various message sizes
        test_sizes = [1, 10, 100, 1000]  # KB
        
        Enum.each(test_sizes, fn size_kb ->
          large_message = TestData.generate_large_message(size_kb)
          
          {_result, send_time} = measure_performance(fn ->
            Client.send_message(client, large_message)
          end)
          
          # Larger messages should not take excessively long
          max_time = size_kb * 1000  # 1ms per KB as rough guideline
          assert send_time < max_time * 1000  # Convert to microseconds
        end)
        
        :ok = Client.close(client)
      end)
    end
  end

  describe "stress testing scenarios" do
    test "concurrent connections" do
      with_real_api(:local_server, [], fn config ->
        # Create multiple concurrent connections
        client_count = 5
        
        clients = Enum.map(1..client_count, fn _i ->
          {:ok, client} = Client.connect(config.endpoint)
          client
        end)
        
        # Send messages from all clients concurrently
        tasks = Enum.map(clients, fn client ->
          Task.async(fn ->
            message = TestData.heartbeat_messages() |> hd()
            :ok = Client.send_message(client, message)
          end)
        end)
        
        # Wait for all tasks to complete
        Enum.each(tasks, &Task.await/1)
        
        # All clients should still be connected
        Enum.each(clients, fn client ->
          assert Client.get_state(client) == :connected
        end)
        
        # Clean up all clients
        Enum.each(clients, &Client.close/1)
      end)
    end

    test "sustained high-frequency messaging" do
      with_real_api(:local_server, [], fn config ->
        {:ok, client} = Client.connect(config.endpoint)
        
        # Send messages at high frequency for sustained period
        duration_ms = 5_000  # 5 seconds
        start_time = System.monotonic_time(:millisecond)
        message_count = 0
        
        message_count = Stream.iterate(0, &(&1 + 1))
        |> Enum.reduce_while(0, fn _i, acc ->
          current_time = System.monotonic_time(:millisecond)
          
          if current_time - start_time >= duration_ms do
            {:halt, acc}
          else
            message = TestData.heartbeat_messages() |> hd()
            :ok = Client.send_message(client, message)
            {:cont, acc + 1}
          end
        end)
        
        # Calculate actual rate
        actual_duration = System.monotonic_time(:millisecond) - start_time
        rate = (message_count * 1000) / actual_duration
        
        # Should handle reasonable message rate
        assert rate > 10.0  # At least 10 messages per second
        assert Client.get_state(client) == :connected
        
        :ok = Client.close(client)
      end)
    end

    test "memory usage stability" do
      with_real_api(:local_server, [], fn config ->
        {:ok, client} = Client.connect(config.endpoint)
        
        # Measure initial memory
        initial_memory = get_process_memory()
        
        # Send many messages to test for memory leaks
        large_messages = Enum.map(1..50, fn _i ->
          TestData.generate_large_message(10)  # 10KB each
        end)
        
        Enum.each(large_messages, fn message ->
          :ok = Client.send_message(client, message)
        end)
        
        # Force garbage collection
        :erlang.garbage_collect()
        Process.sleep(100)
        
        # Measure final memory
        final_memory = get_process_memory()
        
        # Memory usage should not grow excessively
        memory_growth = final_memory - initial_memory
        max_growth = 50 * 1024 * 1024  # 50MB max growth
        
        assert memory_growth < max_growth
        
        :ok = Client.close(client)
      end)
    end
  end

  # Helper functions

  defp get_process_memory do
    :erlang.memory(:total)
  end
end