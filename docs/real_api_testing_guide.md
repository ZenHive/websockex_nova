# Real API Testing Guide

This guide covers the comprehensive real API testing infrastructure for WebsockexNew. The testing framework emphasizes testing against real WebSocket endpoints while providing sophisticated mock servers for controlled testing scenarios.

## Quick Start

### Running Real API Tests

```bash
# Run all real API tests
mix test.api

# Run Deribit-specific tests
mix test.api --deribit

# Run performance tests
mix test.api --performance

# Run stress tests
mix test.api --stress
```

### Environment Management

```bash
# Check health of all environments
mix test.env.health

# Setup specific environment
mix test.env.setup deribit_test

# List available environments
mix test.env.list

# Clean up test resources
mix test.env.cleanup
```

### Performance Benchmarking

```bash
# Run all performance tests
mix test.performance

# Test connection performance only
mix test.performance --connection

# Test with custom parameters
mix test.performance --duration 60 --connections 10 --message-size 5
```

## Testing Architecture

### Environment Types

The testing framework supports multiple environment types:

1. **Real API Environments** (`deribit_test`, `binance_test`)
   - Connect to actual WebSocket APIs
   - Require valid credentials via environment variables
   - Test real-world behavior and compatibility

2. **Local Test Servers** (`local_server`)
   - Enhanced configurable mock servers
   - Support behavior injection (latency, errors, disconnections)
   - Full control over server responses and conditions

3. **Mock Servers** (`custom_mock`)
   - Simple echo-based WebSocket servers
   - Reliable baseline for basic functionality testing
   - No external dependencies

### Test Infrastructure Components

#### TestEnvironment Module

Manages environment setup, health checking, and teardown:

```elixir
# Setup environment with health check
{:ok, config} = TestEnvironment.setup_environment(:deribit_test)

# Skip health check for faster setup
{:ok, config} = TestEnvironment.setup_environment(:local_server, skip_health_check: true)

# Custom server configuration
{:ok, config} = TestEnvironment.setup_environment(:local_server, 
  server_opts: [behavior: %{latency: 100, error_rate: 0.1}])
```

#### ConfigurableTestServer

Advanced test server with behavior simulation:

```elixir
# Start server with custom behavior
{:ok, port} = ConfigurableTestServer.start_server([
  behavior: %{
    latency: 200,           # 200ms response delay
    error_rate: 0.15,       # 15% error rate
    disconnect_rate: 0.05,  # 5% random disconnection rate
    message_corruption: true,
    protocol_violations: false
  }
])

# Inject specific errors at runtime
ConfigurableTestServer.inject_error(port, :disconnect_all)
ConfigurableTestServer.inject_error(port, :send_invalid_frame)
ConfigurableTestServer.inject_error(port, :send_large_payload)
```

#### NetworkSimulator

Simulate various network conditions:

```elixir
# Simulate slow connection
{:ok, simulator} = NetworkSimulator.simulate_condition(client_pid, :slow_connection)

# Custom packet loss simulation
{:ok, simulator} = NetworkSimulator.simulate_condition(client_pid, :packet_loss,
  custom_config: %{packet_loss_rate: 0.2})

# Inject one-time network events
NetworkSimulator.inject_network_event(client_pid, :disconnect)
NetworkSimulator.inject_network_event(client_pid, :delay, delay: 2000)
```

#### ApiTestHelpers

Standardized test patterns and utilities:

```elixir
# Environment-aware test execution
with_real_api(:deribit_test, [], fn config ->
  {:ok, client} = Client.connect(config.endpoint)
  assert_connection_lifecycle(client)
end)

# Performance measurement
{result, time_us} = measure_performance(fn ->
  Client.send_message(client, message)
end)

# Resource leak detection
assert_no_resource_leaks()

# Stress testing
stress_test_client(client, message_count: 1000, concurrent: true)
```

#### TestData Module

Structured test data generation:

```elixir
# Authentication messages
auth_msgs = TestData.auth_messages()
# %{valid: "...", invalid: "...", malformed: "..."}

# Subscription patterns
subs = TestData.subscription_messages()

# Large message generation
large_msg = TestData.generate_large_message(100)  # 100KB message

# Protocol-specific data
wamp_msgs = TestData.protocol_specific_data(:wamp)
json_rpc_msgs = TestData.protocol_specific_data(:json_rpc)

# Error scenarios
error_msgs = TestData.error_messages()
malformed_msgs = TestData.malformed_messages()
```

## Test Environment Configuration

### Environment Variables

For **Deribit** integration tests:
```bash
export DERIBIT_CLIENT_ID="your_test_client_id"
export DERIBIT_CLIENT_SECRET="your_test_client_secret"
```

For **Binance** integration tests:
```bash
export BINANCE_API_KEY="your_test_api_key"
export BINANCE_SECRET_KEY="your_test_secret_key"
```

### Environment Health Checking

The framework automatically checks environment health:

```bash
mix test.env.health
```

Output:
```
✅ deribit_test: healthy
❌ binance_test: unhealthy
❓ custom_mock: unknown
```

Environment health checks verify:
- Endpoint connectivity
- Basic WebSocket handshake
- Authentication capability (if required)
- Response to test messages

## Writing Real API Tests

### Basic Test Pattern

```elixir
defmodule MyApp.RealApiTest do
  use ExUnit.Case, async: false
  import WebsockexNew.ApiTestHelpers
  
  @moduletag :integration
  
  test "basic connection lifecycle" do
    with_real_api(:deribit_test, [], fn config ->
      {:ok, client} = Client.connect(config.endpoint)
      assert_connection_lifecycle(client)
    end)
  end
end
```

### Advanced Test Scenarios

```elixir
test "network resilience under packet loss" do
  with_real_api(:local_server, [], fn config ->
    {:ok, client} = Client.connect(config.endpoint)
    
    # Simulate packet loss
    {:ok, _sim} = NetworkSimulator.simulate_condition(
      client, :packet_loss, duration: 10_000)
    
    # Test continued operation
    messages = TestData.heartbeat_messages()
    Enum.each(messages, fn msg ->
      :ok = Client.send_message(client, msg)
    end)
    
    assert Client.get_state(client) == :connected
    :ok = Client.close(client)
  end)
end
```

### Performance Testing Pattern

```elixir
test "message throughput performance" do
  with_real_api(:local_server, [], fn config ->
    {:ok, client} = Client.connect(config.endpoint)
    
    message_count = 1000
    messages = TestData.stress_test_messages(message_count)
    
    {_result, total_time} = measure_performance(fn ->
      Enum.each(messages, &Client.send_message(client, &1))
    end)
    
    throughput = (message_count * 1_000_000) / total_time
    assert throughput > 100.0  # 100 messages/second minimum
    
    :ok = Client.close(client)
  end)
end
```

### Error Handling Tests

```elixir
test "graceful handling of server errors" do
  server_opts = [behavior: %{error_rate: 0.3}]
  
  with_real_api(:local_server, [server_opts: server_opts], fn config ->
    {:ok, client} = Client.connect(config.endpoint)
    
    # Send messages that will trigger errors
    Enum.each(1..50, fn _i ->
      message = TestData.heartbeat_messages() |> hd()
      :ok = Client.send_message(client, message)
    end)
    
    # Client should remain stable despite errors
    assert Client.get_state(client) == :connected
    :ok = Client.close(client)
  end)
end
```

## Advanced Testing Scenarios

### Multi-Environment Consistency Testing

```elixir
test "behavior consistency across environments" do
  environments = [:custom_mock, :local_server]
  
  Enum.each(environments, fn env ->
    with_real_api(env, [], fn config ->
      {:ok, client} = Client.connect(config.endpoint)
      
      # Test same operations across environments
      message = TestData.heartbeat_messages() |> hd()
      :ok = Client.send_message(client, message)
      
      assert Client.get_state(client) == :connected
      :ok = Client.close(client)
    end)
  end)
end
```

### Stress Testing with Concurrent Connections

```elixir
test "concurrent connection stress test" do
  with_real_api(:local_server, [], fn config ->
    client_count = 10
    
    # Create multiple concurrent connections
    clients = Enum.map(1..client_count, fn _i ->
      {:ok, client} = Client.connect(config.endpoint)
      client
    end)
    
    # Send messages from all clients concurrently
    tasks = Enum.map(clients, fn client ->
      Task.async(fn ->
        stress_test_client(client, message_count: 100)
      end)
    end)
    
    # Wait for all tasks
    Enum.each(tasks, &Task.await(&1, 30_000))
    
    # Clean up
    Enum.each(clients, &Client.close/1)
  end)
end
```

### Network Condition Simulation

```elixir
test "operation under various network conditions" do
  conditions = [:slow_connection, :packet_loss, :high_latency, :intermittent]
  
  Enum.each(conditions, fn condition ->
    with_real_api(:local_server, [], fn config ->
      {:ok, client} = Client.connect(config.endpoint)
      
      # Apply network condition
      {:ok, _sim} = NetworkSimulator.simulate_condition(
        client, condition, duration: 5_000)
      
      # Test basic operations under condition
      message = TestData.heartbeat_messages() |> hd()
      :ok = Client.send_message(client, message)
      
      # Restore normal conditions
      NetworkSimulator.restore_normal_conditions(client)
      
      :ok = Client.close(client)
    end)
  end)
end
```

## Best Practices

### 1. Environment-Specific Testing
- Use `with_real_api/3` for consistent environment handling
- Test against multiple environments when possible
- Handle missing credentials gracefully with skipped tests

### 2. Resource Management
- Always use `assert_no_resource_leaks/0` in test cleanup
- Ensure proper connection closure
- Monitor memory usage in long-running tests

### 3. Network Resilience
- Test various network conditions using NetworkSimulator
- Verify graceful degradation under adverse conditions
- Test recovery scenarios after network issues

### 4. Performance Considerations
- Use `measure_performance/1` for timing-sensitive tests
- Set reasonable performance expectations
- Test both sequential and concurrent scenarios

### 5. Error Handling
- Test with malformed messages and protocol violations
- Verify client stability under server error conditions
- Test authentication failures and recovery

## Debugging and Troubleshooting

### Common Issues

1. **Test Environment Unavailable**
   ```
   ExUnit.Case.skip("Missing environment variable: DERIBIT_CLIENT_ID")
   ```
   - Solution: Set required environment variables

2. **Health Check Failures**
   ```
   ExUnit.Case.skip("Environment health check failed: :timeout")
   ```
   - Solution: Check network connectivity and endpoint availability

3. **Resource Leaks**
   ```
   Found 15 WebsockexNew processes, possible leak
   ```
   - Solution: Ensure proper cleanup in test teardown

### Debug Logging

Enable debug logging in test environment:

```elixir
# test/test_helper.exs
Logger.configure(level: :debug)

# Enable network simulation logging
System.put_env("DEBUG_NETWORK_SIM", "true")
```

### Test Infrastructure Monitoring

Check test server statistics:

```elixir
{:ok, stats} = ConfigurableTestServer.get_stats(port)
# %{connections: 5, message_count: 150, behavior: %{...}}

{:ok, status} = NetworkSimulator.get_simulation_status(client_pid)
# %{active: true, config: %{...}}
```

## Integration with CI/CD

### Environment Detection

The test framework automatically detects CI environments and adjusts behavior:

```bash
# In CI, skip real API tests if credentials unavailable
export CI=true

# Force real API tests (fail if credentials missing)
export FORCE_REAL_API_TESTS=true
```

### Performance Regression Detection

Set up performance baselines:

```bash
# Run performance tests and save baselines
mix test.performance --output json > performance_baseline.json

# Compare against baseline in CI
mix test.performance --baseline performance_baseline.json
```

This comprehensive testing infrastructure ensures that WebsockexNew works reliably across different environments, handles various network conditions gracefully, and maintains consistent performance characteristics.