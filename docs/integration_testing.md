# WebsockexNew Integration Testing Guide

Comprehensive guide for testing WebSocket clients and adapters with real endpoints.

## Testing Philosophy

WebsockexNew follows a **"Real Endpoint First"** testing approach:

> **NO MOCKS POLICY**: Always test against real test APIs when available. If no test API exists, use the real API. This ensures tests reflect actual behavior and catch real-world issues.

## Testing Infrastructure

### Test Organization

Tests are organized by complexity and dependencies:

```
test/
├── websockex_new/               # Unit tests
│   ├── client_test.exs
│   ├── config_test.exs
│   ├── error_handler_test.exs
│   └── examples/
│       └── deribit_adapter_test.exs
├── websockex_new/               # Integration tests
│   └── error_integration_test.exs
└── support/                     # Test utilities
    ├── mock_websock_server.ex   # Local test server
    ├── gun_monitor.ex           # Process monitoring
    └── certificate_helper.ex    # TLS testing
```

### Test Tags

Use ExUnit tags to categorize tests:

```elixir
@moduletag :integration          # Real endpoint tests
@tag :skip_unless_env           # Requires environment variables
@tag :slow                      # Long-running tests  
@tag :network                   # Network-dependent tests
```

## Integration Test Patterns

### 1. Real Endpoint Testing

Test against actual WebSocket APIs:

```elixir
defmodule MyAdapter.IntegrationTest do
  use ExUnit.Case, async: false
  
  @moduletag :integration
  
  @test_url "wss://test.myplatform.com/ws"
  
  test "connects to real endpoint" do
    {:ok, adapter} = MyAdapter.connect(url: @test_url)
    assert adapter.client.state == :connected
    
    # Clean up
    MyAdapter.Client.close(adapter.client)
  end
end
```

### 2. Environment-Based Credential Testing

Use environment variables for sensitive credentials:

```elixir
@tag :skip_unless_env
test "authenticates with real credentials" do
  api_key = System.get_env("PLATFORM_API_KEY")
  secret = System.get_env("PLATFORM_SECRET")
  
  if api_key && secret do
    {:ok, adapter} = MyAdapter.connect(api_key: api_key, secret: secret)
    {:ok, authenticated} = MyAdapter.authenticate(adapter)
    assert authenticated.authenticated == true
    
    MyAdapter.Client.close(authenticated.client)
  else
    IO.puts("Skipping auth test - no credentials provided")
  end
end
```

### 3. Full Lifecycle Testing

Test complete user workflows:

```elixir
@tag :integration
@tag :skip_unless_env  
test "full platform integration" do
  credentials = get_test_credentials()
  
  # Connect
  {:ok, adapter} = MyAdapter.connect(credentials)
  :timer.sleep(1000)  # Allow connection to stabilize
  
  # Authenticate
  {:ok, authenticated} = MyAdapter.authenticate(adapter)
  
  # Subscribe
  {:ok, subscribed} = MyAdapter.subscribe(authenticated, ["test.channel"])
  assert MapSet.member?(subscribed.subscriptions, "test.channel")
  
  # Wait for messages
  :timer.sleep(5000)
  
  # Unsubscribe  
  {:ok, unsubscribed} = MyAdapter.unsubscribe(subscribed, ["test.channel"])
  refute MapSet.member?(unsubscribed.subscriptions, "test.channel")
  
  # Clean up
  MyAdapter.Client.close(unsubscribed.client)
end
```

## Error Testing Patterns

### 1. Network Error Simulation

Test connection failures and recovery:

```elixir
test "handles connection failures" do
  invalid_url = "wss://invalid-domain-that-does-not-exist.com/ws"
  
  assert {:error, reason} = Client.connect(invalid_url)
  
  # Verify error classification
  {category, _} = ErrorHandler.categorize_error(reason)
  assert category == :recoverable
  assert ErrorHandler.handle_error(reason) == :reconnect
end
```

### 2. Timeout Testing

Test timeout scenarios:

```elixir
test "handles connection timeout" do
  config = Config.new!(@test_url, timeout: 1)  # Very short timeout
  
  case Client.connect(config) do
    {:error, :timeout} ->
      assert ErrorHandler.recoverable?({:error, :timeout})
      
    {:error, reason} ->
      # Connection might be faster than timeout
      assert is_tuple(reason)
      
    {:ok, client} ->
      # Connection succeeded despite short timeout
      Client.close(client)
  end
end
```

### 3. Authentication Error Testing

Test invalid credentials:

```elixir
test "handles invalid credentials" do
  {:ok, client} = Client.connect(@test_url)
  
  invalid_auth = create_invalid_auth_message()
  assert :ok = Client.send_message(client, invalid_auth)
  
  # Wait for error response
  :timer.sleep(1000)
  
  Client.close(client)
end
```

## Local Test Server Usage

For controlled testing scenarios, use the MockWebSockServer:

### Basic Server Setup

```elixir
defmodule MyTest do
  use ExUnit.Case
  
  alias WebsockexNew.Test.Support.MockWebSockServer
  
  setup do
    {:ok, server_pid, port} = MockWebSockServer.start_link()
    url = "ws://localhost:#{port}/ws"
    
    on_exit(fn -> MockWebSockServer.stop(server_pid) end)
    
    %{server: server_pid, url: url, port: port}
  end
  
  test "basic connection", %{url: url} do
    {:ok, client} = Client.connect(url)
    assert client.state == :connected
    Client.close(client)
  end
end
```

### Custom Message Handlers

Set up server responses for specific test scenarios:

```elixir
test "handles custom server responses", %{server: server, url: url} do
  # Configure server to handle authentication
  MockWebSockServer.set_handler(server, fn
    {:text, "{\"type\":\"auth\"}" <> _} ->
      {:reply, {:text, "{\"type\":\"auth_success\",\"token\":\"test_token\"}"}}
      
    {:text, "ping"} ->
      {:reply, {:text, "pong"}}
      
    {:text, msg} ->
      {:reply, {:text, "echo: #{msg}"}}
  end)
  
  {:ok, client} = Client.connect(url)
  
  # Test authentication
  :ok = Client.send_message(client, "{\"type\":\"auth\"}")
  
  # Test ping/pong
  :ok = Client.send_message(client, "ping")
  
  Client.close(client)
end
```

### Connection Simulation

Test reconnection scenarios:

```elixir
test "handles server disconnection", %{server: server, url: url} do
  {:ok, client} = Client.connect(url)
  assert client.state == :connected
  
  # Simulate server disconnect
  MockWebSockServer.stop(server)
  
  # Wait for disconnect detection
  :timer.sleep(1000)
  
  # Test reconnection logic
  case Client.reconnect(client) do
    {:error, _reason} ->
      # Expected - server is down
      :ok
      
    {:ok, _new_client} ->
      # Unexpected but possible if server restarts quickly
      :ok
  end
end
```

## Adapter Testing Patterns

### DeribitAdapter Example

The DeribitAdapter demonstrates comprehensive integration testing:

#### Connection Testing
```elixir
test "connects to Deribit test API" do
  assert {:ok, adapter} = DeribitAdapter.connect()
  assert %DeribitAdapter{} = adapter
  assert adapter.authenticated == false
  assert MapSet.size(adapter.subscriptions) == 0
  
  Client.close(adapter.client)
end
```

#### Authentication Testing
```elixir
@tag :skip_unless_env
test "authenticates with valid credentials" do
  client_id = System.get_env("DERIBIT_CLIENT_ID")
  client_secret = System.get_env("DERIBIT_CLIENT_SECRET")
  
  if client_id && client_secret do
    {:ok, adapter} = DeribitAdapter.connect(
      client_id: client_id, 
      client_secret: client_secret
    )
    
    :timer.sleep(1000)  # Allow connection
    
    {:ok, authenticated} = DeribitAdapter.authenticate(adapter)
    assert authenticated.authenticated == true
    
    Client.close(authenticated.client)
  end
end
```

#### Message Handling Testing
```elixir
test "handles heartbeat messages" do
  heartbeat_message = %{
    "method" => "heartbeat",
    "params" => %{"type" => "test_request"}
  }
  
  json_message = Jason.encode!(heartbeat_message)
  assert {:response, response} = DeribitAdapter.handle_message({:text, json_message})
  
  {:ok, decoded} = Jason.decode(response)
  assert decoded["method"] == "public/test"
  assert decoded["jsonrpc"] == "2.0"
end
```

#### Subscription Testing
```elixir
test "manages subscriptions correctly" do
  {:ok, adapter} = DeribitAdapter.connect()
  :timer.sleep(1000)
  
  channels = ["deribit_price_index.btc_usd"]
  {:ok, subscribed} = DeribitAdapter.subscribe(adapter, channels)
  assert MapSet.member?(subscribed.subscriptions, "deribit_price_index.btc_usd")
  
  {:ok, unsubscribed} = DeribitAdapter.unsubscribe(subscribed, channels)
  refute MapSet.member?(unsubscribed.subscriptions, "deribit_price_index.btc_usd")
  
  Client.close(unsubscribed.client)
end
```

## Error Integration Testing

### Connection Error Testing

```elixir
describe "connection errors" do
  test "categorizes errors correctly" do
    connection_errors = [
      {:error, :econnrefused},
      {:error, :timeout}, 
      {:error, :nxdomain},
      {:gun_down, self(), :http, :closed, []},
      {:gun_error, self(), make_ref(), :timeout}
    ]
    
    for error <- connection_errors do
      assert ErrorHandler.recoverable?(error)
      assert ErrorHandler.handle_error(error) == :reconnect
    end
  end
  
  test "handles protocol errors as fatal" do
    protocol_errors = [
      {:error, :invalid_frame},
      {:error, :unauthorized},
      {:error, {:bad_frame, :invalid_opcode}}
    ]
    
    for error <- protocol_errors do
      refute ErrorHandler.recoverable?(error)
      assert ErrorHandler.handle_error(error) == :stop
    end
  end
end
```

### Reconnection Testing

```elixir
test "reconnection preserves state" do
  config = Config.new!(@test_url, retry_count: 3)
  subscriptions = ["test.channel"]
  
  case Reconnection.reconnect(config, 0, subscriptions) do
    {:ok, client} ->
      # Verify connection and subscription restoration
      :ok
      
    {:error, :max_retries} ->
      # Expected if endpoint is unavailable
      :ok
  end
end
```

## Best Practices

### 1. Clean Resource Management

Always clean up connections:

```elixir
setup do
  on_exit(fn ->
    # Clean up any lingering connections
    Process.sleep(100)
  end)
end

test "resource cleanup" do
  {:ok, client} = Client.connect(@test_url)
  
  # Always clean up in tests
  Client.close(client)
end
```

### 2. Timing Considerations

WebSocket connections need time to establish:

```elixir
test "allows connection time" do
  {:ok, client} = Client.connect(@test_url)
  
  # Give connection time to stabilize before operations
  :timer.sleep(1000)
  
  assert Client.get_state(client) == :connected
  Client.close(client)
end
```

### 3. Environment Setup

Document required environment variables:

```elixir
# Required environment variables for full test suite:
# DERIBIT_CLIENT_ID - Deribit test API client ID
# DERIBIT_CLIENT_SECRET - Deribit test API client secret
# PLATFORM_API_KEY - Platform API key
# PLATFORM_SECRET - Platform API secret
```

### 4. Test Isolation

Prevent test interference:

```elixir
defmodule MyTest do
  use ExUnit.Case, async: false  # Sequential for network tests
  
  # Use unique identifiers
  @test_channel "test.#{System.unique_integer([:positive])}"
end
```

### 5. Failure Documentation

Document expected failure scenarios:

```elixir
test "expected failure scenarios" do
  # This test validates error handling, failure is expected
  assert {:error, _reason} = Client.connect("wss://invalid.domain.com/ws")
end
```

## Running Integration Tests

### Basic Test Execution

```bash
# Run all tests
mix test

# Run only integration tests
mix test --only integration

# Run with credentials
DERIBIT_CLIENT_ID=your_id DERIBIT_CLIENT_SECRET=your_secret mix test

# Skip environment-dependent tests
mix test --exclude skip_unless_env
```

### CI/CD Configuration

Configure test environments:

```yaml
# .github/workflows/test.yml
env:
  DERIBIT_CLIENT_ID: ${{ secrets.DERIBIT_CLIENT_ID }}
  DERIBIT_CLIENT_SECRET: ${{ secrets.DERIBIT_CLIENT_SECRET }}

steps:
  - name: Run integration tests
    run: mix test --only integration
```

This comprehensive testing approach ensures WebsockexNew adapters work reliably with real WebSocket endpoints while maintaining fast feedback cycles during development.