# API Compatibility Audit and Documentation

## WNX0018a: Test Support Module API Documentation

This document provides a comprehensive audit of all test support modules and their API compatibility.

## Test Support Module Overview

### 1. MockWebSockServer (`test/support/mock_websock_server.ex`)

**Purpose**: Cowboy-based WebSocket server for testing client connections

**API Signatures**:
```elixir
@spec start_link(options :: list() | integer()) :: {:ok, pid(), port()}
@spec set_handler(server :: pid(), handler :: (any() -> any())) :: :ok
@spec get_port(server :: pid()) :: integer()
@spec get_connections(server :: pid()) :: map()
@spec stop(server :: pid()) :: :ok
```

**Return Values**:
- `start_link/1`: `{:ok, server_pid, actual_port}` - Returns server process and dynamic port
- `set_handler/2`: `:ok` - Sets custom message handler function
- `get_port/1`: `integer()` - Returns the actual listening port
- `get_connections/1`: `%{ref => pid}` - Map of connection references to WebSocket process PIDs
- `stop/1`: `:ok` - Gracefully stops the server

**Protocol Support**:
- `:http` - Plain HTTP with WebSocket upgrade
- `:tls` - HTTPS with TLS certificates 
- `:http2` - HTTP/2 over plain TCP
- `:https2` - HTTP/2 over TLS

**Built-in Message Handling**:
- `"ping"` → `"pong"`
- `"subscribe:" <> channel` → `"subscribed:#{channel}"`
- `"unsubscribe:" <> channel` → `"unsubscribed:#{channel}"`
- `"authenticate"` → `"authenticated"`
- Default: Echo messages back to client

### 2. CertificateHelper (`test/support/certificate_helper.ex`)

**Purpose**: Generates self-signed certificates for TLS testing

**API Signatures**:
```elixir
@spec generate_self_signed_certificate(opts :: keyword()) :: {String.t(), String.t()}
```

**Parameters**:
- `:common_name` - Certificate CN (default: "localhost")
- `:days` - Validity period in days (default: 365)

**Return Values**:
- `{cert_file_path, key_file_path}` - Temporary file paths for certificate and private key

**Dependencies**:
- `X509` library for certificate generation
- `Temp` library for temporary file creation

### 3. GunMonitor (`test/support/gun_monitor.ex`)

**Purpose**: Debug monitor for Gun process message flow

**API Signatures**:
```elixir
@spec start_link(target_pid :: pid()) :: {:ok, pid()}
@spec monitor_gun(gun_pid :: pid(), monitor_pid :: pid()) :: :ok
@spec get_messages(pid :: pid()) :: list()
```

**Return Values**:
- `start_link/1`: `{:ok, monitor_pid}` - Returns monitor process
- `monitor_gun/2`: `:ok` - Sets monitor as Gun process owner
- `get_messages/1`: `[gun_message]` - List of intercepted Gun messages

**Monitored Gun Messages**:
- `{:gun_up, gun_pid, protocol}`
- `{:gun_down, gun_pid, protocol, reason, killed_streams, unprocessed_streams}`
- `{:gun_upgrade, stream_ref, protocols, headers}`
- `{:gun_ws, stream_ref, frame}`
- `{:gun_error, stream_ref, reason}`
- `{:gun_response, stream_ref, is_fin, status, headers}`
- `{:gun_data, stream_ref, is_fin, data}`

### 4. MockWebSockHandler (`test/support/mock_websock_handler.ex`)

**Purpose**: WebSock behavior implementation for standardized WebSocket testing

**API Signatures** (WebSock callbacks):
```elixir
@impl WebSock
def init(options :: keyword()) :: {:ok, state()}
def handle_in(frame :: websocket_frame(), state()) :: websock_response()
def handle_info(message :: any(), state()) :: websock_response()
def terminate(reason :: any(), state()) :: :ok
```

**Frame Formats Handled**:
- `{:text, message, opts}` - Text frames with options
- `{text_message, [opcode: :text]}` - Alternative text format
- `{:binary, message, opts}` - Binary frames with options
- `{binary_message, [opcode: :binary]}` - Alternative binary format
- `{:ping, message, opts}` - Ping frames (auto-responds with pong)
- `{:pong, message, opts}` - Pong frames (ignored)
- `{:close, code, reason, opts}` - Close frames

**Info Messages**:
- `{:send_text, message}` - Send text to client
- `{:send_binary, message}` - Send binary to client
- `{:send_error, reason}` - Send error as JSON
- `{:disconnect, code, reason}` - Close connection

### 5. MockWebSockServer.Router (`test/support/mock_websock_server/router.ex`)

**Purpose**: Plug router for HTTP and WebSocket request handling

**API**:
- `GET /ws` - WebSocket upgrade endpoint
- All other paths return 404

**Dependencies**:
- `Plug.Router` for routing
- `WebSockAdapter` for WebSocket upgrades

## External API Dependencies

### Gun (HTTP/WebSocket Client)

**Core Functions Used**:
```elixir
:gun.open(host, port, opts) :: {:ok, pid()} | {:error, any()}
:gun.ws_upgrade(gun_pid, path, headers) :: stream_ref()
:gun.ws_send(gun_pid, stream_ref, frame) :: :ok
:gun.close(gun_pid) :: :ok
:gun.set_owner(gun_pid, new_owner_pid) :: :ok
```

### Cowboy (HTTP Server)

**Server Management**:
```elixir
:cowboy.start_clear(name, transport_opts, protocol_opts) :: {:ok, pid()}
:cowboy.start_tls(name, transport_opts, protocol_opts) :: {:ok, pid()}
:cowboy.stop_listener(name) :: :ok
```

### ExUnit Integration

**Test Support Pattern**:
```elixir
# Standard ExUnit setup with test support modules
setup do
  {:ok, server_pid, port} = MockWebSockServer.start_link()
  
  on_exit(fn ->
    MockWebSockServer.stop(server_pid)
  end)
  
  %{server: server_pid, port: port}
end
```

## Compatibility Assessment

### Direct Usage (No Wrappers Needed)

1. **CertificateHelper** - Simple, stable API
2. **GunMonitor** - Debug tool with minimal interface
3. **Gun APIs** - Erlang library with stable interface

### Wrapper Functions Recommended

1. **MockWebSockServer** - Complex initialization, benefits from helper functions
2. **WebSock/WebSockAdapter** - Protocol-specific, may need abstraction
3. **Cowboy routing** - Configuration-heavy, benefits from simplified interface

### Test Pattern Standardization

**Recommended Test Setup Pattern**:
```elixir
defmodule MyModuleTest do
  use ExUnit.Case
  
  alias WebsockexNew.Test.Support.{MockWebSockServer, CertificateHelper}
  
  setup do
    # For HTTP testing
    {:ok, server, port} = MockWebSockServer.start_link()
    
    # For HTTPS testing
    {:ok, tls_server, tls_port} = MockWebSockServer.start_link(protocol: :tls)
    
    on_exit(fn ->
      MockWebSockServer.stop(server)
      MockWebSockServer.stop(tls_server)
    end)
    
    %{
      http_server: server,
      http_port: port,
      tls_server: tls_server,
      tls_port: tls_port
    }
  end
end
```

## Integration Test Requirements

### Real API Testing Policy

As per CLAUDE.md requirements:
- **NO MOCKS ALLOWED** for integration tests
- Use `test.deribit.com` for real API testing
- Test realistic network conditions and error scenarios
- Required environment variables: `DERIBIT_CLIENT_ID`, `DERIBIT_CLIENT_SECRET`

### Mock Usage Guidelines

Mock servers should only be used for:
1. **Unit testing** individual components
2. **Network simulation** (connection drops, timeouts)
3. **Protocol testing** (frame handling, upgrade scenarios)
4. **Error condition simulation** (malformed responses)

### Test Infrastructure Dependencies

**Runtime Dependencies**:
- `gun ~> 2.2` - WebSocket/HTTP client
- `jason ~> 1.4` - JSON encoding/decoding

**Test-Only Dependencies**:
- `cowboy ~> 2.10` - Mock server framework
- `websock ~> 0.5` - WebSocket protocol handling
- `websock_adapter ~> 0.5` - WebSocket adapter
- `plug_cowboy ~> 2.6` - Plug integration
- `temp ~> 0.4` - Temporary file management
- `x509 ~> 0.8` - Certificate generation
- `mox ~> 1.0` - Mocking framework (limited use)
- `stream_data ~> 1.0` - Property-based testing

## Conclusion

The test support infrastructure is well-designed with clear separation between:
1. **Mock servers** for controlled testing environments
2. **Certificate helpers** for TLS testing
3. **Debug monitors** for message flow analysis
4. **Real API testing** for integration scenarios

All modules follow consistent patterns and provide stable APIs suitable for the financial trading domain requirements.