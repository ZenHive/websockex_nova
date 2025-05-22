# Test Infrastructure Compatibility Guide

## ExUnit, Gun, and Test Infrastructure API Compatibility

This guide provides detailed compatibility information for all testing APIs used in WebsockexNew.

## ExUnit Integration Patterns

### Standard Test Setup

```elixir
defmodule WebsockexNew.SomeModuleTest do
  use ExUnit.Case, async: true
  
  alias WebsockexNew.Test.Support.{MockWebSockServer, CertificateHelper}
  
  # Standard setup for WebSocket testing
  setup do
    {:ok, server, port} = MockWebSockServer.start_link()
    
    on_exit(fn ->
      MockWebSockServer.stop(server)
    end)
    
    %{server: server, port: port, url: "ws://localhost:#{port}/ws"}
  end
  
  # TLS setup when needed
  setup %{tls: true} do
    {:ok, tls_server, tls_port} = MockWebSockServer.start_link(protocol: :tls)
    
    on_exit(fn ->
      MockWebSockServer.stop(tls_server)
    end)
    
    %{tls_server: tls_server, tls_port: tls_port, tls_url: "wss://localhost:#{tls_port}/ws"}
  end
end
```

### Integration Test Tags

```elixir
# Real API integration test
@tag :integration
test "connects to real Deribit testnet", %{} do
  # Use environment variables for real API credentials
  # NEVER use mocks for integration tests
end

# TLS-specific test
@tag :tls
test "handles TLS connection", %{tls_url: url} do
  # Test TLS-specific functionality
end

# Performance test
@tag :performance
test "handles high message throughput", %{url: url} do
  # Test performance characteristics
end
```

## Gun API Compatibility

### Connection Management

```elixir
# Gun connection lifecycle
{:ok, gun_pid} = :gun.open(host, port, %{
  protocols: [:http],
  transport: :tcp,  # or :tls
  connect_timeout: 5000,
  http_opts: %{
    keepalive: 30_000
  }
})

# WebSocket upgrade
stream_ref = :gun.ws_upgrade(gun_pid, "/ws", [
  {"sec-websocket-protocol", "chat"}
])

# Wait for upgrade confirmation
receive do
  {:gun_upgrade, ^gun_pid, ^stream_ref, ["websocket"], _headers} ->
    :ok
  {:gun_response, ^gun_pid, ^stream_ref, _, status, _headers} ->
    {:error, {:upgrade_failed, status}}
  {:gun_error, ^gun_pid, ^stream_ref, reason} ->
    {:error, reason}
after
  5000 -> {:error, :timeout}
end
```

### Message Handling

```elixir
# Send WebSocket frames
:ok = :gun.ws_send(gun_pid, stream_ref, {:text, "hello"})
:ok = :gun.ws_send(gun_pid, stream_ref, {:binary, <<1, 2, 3>>})
:ok = :gun.ws_send(gun_pid, stream_ref, {:ping, "ping_data"})

# Receive messages
receive do
  {:gun_ws, ^gun_pid, ^stream_ref, {:text, text}} ->
    # Handle text message
  {:gun_ws, ^gun_pid, ^stream_ref, {:binary, data}} ->
    # Handle binary message
  {:gun_ws, ^gun_pid, ^stream_ref, {:pong, data}} ->
    # Handle pong response
  {:gun_ws, ^gun_pid, ^stream_ref, {:close, code, reason}} ->
    # Handle close frame
end
```

### Error Handling

```elixir
# Gun error patterns
receive do
  {:gun_down, ^gun_pid, :ws, :closed, [], []} ->
    # Clean connection close
  {:gun_down, ^gun_pid, :ws, {:error, reason}, [], []} ->
    # Connection error
  {:gun_error, ^gun_pid, ^stream_ref, reason} ->
    # Stream-specific error
end
```

## MockWebSockServer API Compatibility

### Server Initialization Options

```elixir
# HTTP server (default)
{:ok, server, port} = MockWebSockServer.start_link()
{:ok, server, port} = MockWebSockServer.start_link(port: 0)
{:ok, server, port} = MockWebSockServer.start_link(protocol: :http)

# HTTPS server with auto-generated certificates
{:ok, server, port} = MockWebSockServer.start_link(protocol: :tls)

# HTTP/2 variants
{:ok, server, port} = MockWebSockServer.start_link(protocol: :http2)
{:ok, server, port} = MockWebSockServer.start_link(protocol: :https2)
```

### Custom Message Handlers

```elixir
# Set custom handler function
handler_fn = fn
  {:text, "ping"} -> {:reply, {:text, "pong"}}
  {:text, "subscribe:" <> channel} -> 
    {:reply, {:text, Jason.encode!(%{subscribed: channel})}}
  {:text, msg} -> 
    {:reply, {:text, "echo: #{msg}"}}
  {:binary, data} -> 
    {:reply, {:binary, data}}
  _ -> 
    :ok
end

MockWebSockServer.set_handler(server, handler_fn)
```

### Server Management

```elixir
# Get current port
port = MockWebSockServer.get_port(server)

# Get active connections
connections = MockWebSockServer.get_connections(server)
# Returns: %{ref1 => ws_pid1, ref2 => ws_pid2, ...}

# Stop server gracefully
:ok = MockWebSockServer.stop(server)
```

## CertificateHelper API Compatibility

### Certificate Generation

```elixir
# Default localhost certificate
{cert_path, key_path} = CertificateHelper.generate_self_signed_certificate()

# Custom options
{cert_path, key_path} = CertificateHelper.generate_self_signed_certificate([
  common_name: "test.example.com",
  days: 30
])
```

### TLS Configuration Integration

```elixir
# Use with Gun
{cert_path, key_path} = CertificateHelper.generate_self_signed_certificate()

gun_opts = %{
  transport: :tls,
  tls_opts: [
    # For client certificate authentication
    certfile: cert_path,
    keyfile: key_path,
    # For server certificate verification (disable in tests)
    verify: :verify_none
  ]
}

{:ok, gun_pid} = :gun.open(host, port, gun_opts)
```

## WebSock/WebSockAdapter Compatibility

### Frame Format Standardization

The WebSock protocol standardizes frame formats:

```elixir
# Incoming frames (from WebSockAdapter)
{:text, message, opts}           # Text frame with metadata
{:binary, data, opts}            # Binary frame with metadata
{:ping, data, opts}              # Ping frame
{:pong, data, opts}              # Pong frame
{:close, code, reason, opts}     # Close frame

# Alternative format (also supported)
{message, [opcode: :text]}       # Text message
{data, [opcode: :binary]}        # Binary message
```

### Response Patterns

```elixir
# WebSock handler responses
{:ok, state}                     # Continue without sending
{:push, frame, state}            # Send frame and continue
{:reply, frame, state}           # Same as :push
{:stop, reason, state}           # Terminate connection
```

## Test Environment Setup

### Required Environment Variables

```bash
# For Deribit integration tests
export DERIBIT_CLIENT_ID="your_test_client_id"
export DERIBIT_CLIENT_SECRET="your_test_client_secret"

# Optional: Set test environment
export MIX_ENV=test
export WEBSOCKEX_TEST_LOG_LEVEL=warning
```

### Mix Test Configuration

```elixir
# In mix.exs
def project do
  [
    elixirc_paths: elixirc_paths(Mix.env()),
    preferred_cli_env: [
      "test.api": :test,
      "test.performance": :test
    ]
  ]
end

defp elixirc_paths(:test), do: ["lib", "test/support"]
defp elixirc_paths(_), do: ["lib"]
```

## Cowboy Integration

### Router Setup

```elixir
# Cowboy dispatch configuration
dispatch = :cowboy_router.compile([
  {:_, [
    {"/ws", WebSocketHandler, %{parent: self()}},
    {"/health", HealthHandler, []},
    {:_, NotFoundHandler, []}
  ]}
])

# Start HTTP server
{:ok, _} = :cowboy.start_clear(
  :test_server,
  [{:port, 0}],
  %{env: %{dispatch: dispatch}}
)

# Get actual port
{_, port} = :ranch.get_addr(:test_server)
```

### TLS Configuration

```elixir
# TLS server with certificates
{cert_path, key_path} = CertificateHelper.generate_self_signed_certificate()

{:ok, _} = :cowboy.start_tls(
  :test_tls_server,
  [
    {:port, 0},
    {:certfile, cert_path},
    {:keyfile, key_path}
  ],
  %{env: %{dispatch: dispatch}}
)
```

## Performance Testing Compatibility

### Concurrent Connection Testing

```elixir
test "handles multiple concurrent connections", %{server: server, port: port} do
  # Start multiple Gun connections
  gun_pids = Enum.map(1..100, fn _ ->
    {:ok, gun_pid} = :gun.open('localhost', port)
    gun_pid
  end)
  
  # Upgrade all to WebSocket
  stream_refs = Enum.map(gun_pids, fn gun_pid ->
    :gun.ws_upgrade(gun_pid, "/ws")
  end)
  
  # Test concurrent message sending
  Enum.zip(gun_pids, stream_refs)
  |> Enum.each(fn {gun_pid, stream_ref} ->
    :gun.ws_send(gun_pid, stream_ref, {:text, "test"})
  end)
  
  # Cleanup
  Enum.each(gun_pids, &:gun.close/1)
end
```

### Message Throughput Testing

```elixir
test "handles high message throughput", %{url: url} do
  {:ok, client} = WebsockexNew.Client.connect(url)
  
  # Send messages rapidly
  messages = 1..1000
  start_time = System.monotonic_time()
  
  Enum.each(messages, fn i ->
    WebsockexNew.Client.send_message(client, "message_#{i}")
  end)
  
  end_time = System.monotonic_time()
  duration_ms = System.convert_time_unit(end_time - start_time, :native, :millisecond)
  
  # Assert performance requirements
  assert duration_ms < 1000, "Message sending took too long: #{duration_ms}ms"
end
```

## Common Compatibility Issues

### 1. Port Conflicts

```elixir
# Solution: Always use dynamic ports
{:ok, server, port} = MockWebSockServer.start_link(port: 0)
```

### 2. Certificate Path Issues

```elixir
# Solution: Use absolute paths from CertificateHelper
{cert_path, key_path} = CertificateHelper.generate_self_signed_certificate()
# cert_path and key_path are absolute temporary file paths
```

### 3. Async Test Conflicts

```elixir
# Solution: Use unique server names
defmodule MyTest do
  use ExUnit.Case, async: true  # Safe with unique servers
  
  setup do
    # Each test gets its own server instance
    {:ok, server, port} = MockWebSockServer.start_link()
    %{server: server, port: port}
  end
end
```

### 4. Gun Connection Cleanup

```elixir
# Solution: Always clean up Gun connections
setup do
  on_exit(fn ->
    # Clean up any Gun connections
    :gun.close(gun_pid)
  end)
end
```

## Best Practices Summary

1. **Always use dynamic ports** for test servers
2. **Clean up resources** in `on_exit` callbacks
3. **Use real APIs** for integration tests
4. **Tag tests appropriately** (`:integration`, `:tls`, `:performance`)
5. **Handle timeouts gracefully** in async operations
6. **Use absolute paths** for certificate files
7. **Monitor Gun processes** for debug information
8. **Follow the no-mocks policy** for financial API testing