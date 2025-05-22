# Wrapper Functions Analysis

## WNX0018a: Module Analysis for Wrapper Functions vs Direct Usage

This document analyzes which test support modules need wrapper functions versus those that can be used directly.

## Analysis Categories

### ✅ DIRECT USAGE (No Wrappers Needed)

These modules have simple, stable APIs that can be used directly:

#### 1. CertificateHelper
**Rationale**: Single-purpose, simple API
```elixir
# Direct usage is clean and straightforward
{cert_path, key_path} = CertificateHelper.generate_self_signed_certificate()
{cert_path, key_path} = CertificateHelper.generate_self_signed_certificate(common_name: "test.local")
```

**API Stability**: ✅ High - Single function with optional parameters
**Complexity**: ✅ Low - Returns simple tuple
**Error Handling**: ✅ Simple - Uses X509 library directly

#### 2. GunMonitor  
**Rationale**: Debug tool with minimal interface
```elixir
# Direct usage for debugging
{:ok, monitor} = GunMonitor.start_link(target_pid)
GunMonitor.monitor_gun(gun_pid, monitor)
messages = GunMonitor.get_messages(monitor)
```

**API Stability**: ✅ High - Simple GenServer interface
**Complexity**: ✅ Low - Three main functions
**Error Handling**: ✅ Standard GenServer patterns

#### 3. Gun Core APIs
**Rationale**: Erlang library with established patterns
```elixir
# Well-established Gun patterns
{:ok, gun_pid} = :gun.open(host, port, opts)
stream_ref = :gun.ws_upgrade(gun_pid, path, headers)
:gun.ws_send(gun_pid, stream_ref, frame)
```

**API Stability**: ✅ High - Mature Erlang library
**Complexity**: ✅ Medium - But well-documented patterns
**Error Handling**: ✅ Consistent Erlang conventions

### ⚠️ WRAPPER FUNCTIONS RECOMMENDED

These modules would benefit from simplified wrapper functions:

#### 1. MockWebSockServer
**Rationale**: Complex initialization with multiple protocols

**Current Issues**:
```elixir
# Verbose setup for different protocols
{:ok, server, port} = MockWebSockServer.start_link(protocol: :tls)
{:ok, server, port} = MockWebSockServer.start_link(protocol: :http2)
{:ok, server, port} = MockWebSockServer.start_link(protocol: :https2)

# Handler setup requires understanding of frame formats
handler = fn
  {:text, "ping"} -> {:reply, {:text, "pong"}}
  {:text, msg} -> {:reply, {:text, "echo: " <> msg}}
end
MockWebSockServer.set_handler(server, handler)
```

**Recommended Wrappers**:
```elixir
defmodule WebsockexNew.Test.Support.ServerHelpers do
  @moduledoc "Simplified helpers for test server setup"
  
  def start_http_server(opts \\ []) do
    MockWebSockServer.start_link([protocol: :http] ++ opts)
  end
  
  def start_tls_server(opts \\ []) do
    MockWebSockServer.start_link([protocol: :tls] ++ opts)
  end
  
  def echo_server(opts \\ []) do
    {:ok, server, port} = start_http_server(opts)
    set_echo_handler(server)
    {:ok, server, port}
  end
  
  def ping_pong_server(opts \\ []) do
    {:ok, server, port} = start_http_server(opts)
    set_ping_pong_handler(server)
    {:ok, server, port}
  end
  
  defp set_echo_handler(server) do
    handler = fn
      {:text, msg} -> {:reply, {:text, msg}}
      {:binary, data} -> {:reply, {:binary, data}}
      _ -> :ok
    end
    MockWebSockServer.set_handler(server, handler)
  end
  
  defp set_ping_pong_handler(server) do
    handler = fn
      {:text, "ping"} -> {:reply, {:text, "pong"}}
      {:text, msg} -> {:reply, {:text, "echo: " <> msg}}
      _ -> :ok
    end
    MockWebSockServer.set_handler(server, handler)
  end
end
```

**Benefits**:
- Reduces test setup boilerplate
- Provides common server configurations
- Hides protocol complexity
- Standardizes handler patterns

#### 2. WebSock/WebSockAdapter Integration
**Rationale**: Protocol-specific complexity needs abstraction

**Current Issues**:
```elixir
# Complex frame format handling
def handle_in({:text, message, opts}, state) do
  # Handle standard format
end

def handle_in({text_message, [opcode: :text]}, state) when is_binary(text_message) do
  # Handle alternative format
end
```

**Recommended Wrapper**:
```elixir
defmodule WebsockexNew.Test.Support.FrameHelpers do
  @moduledoc "Standardized frame handling for tests"
  
  def normalize_frame({:text, message, _opts}), do: {:text, message}
  def normalize_frame({message, [opcode: :text]}) when is_binary(message), do: {:text, message}
  def normalize_frame({:binary, data, _opts}), do: {:binary, data}
  def normalize_frame({data, [opcode: :binary]}) when is_binary(data), do: {:binary, data}
  def normalize_frame({:ping, data, _opts}), do: {:ping, data}
  def normalize_frame({:pong, data, _opts}), do: {:pong, data}
  def normalize_frame({:close, code, reason, _opts}), do: {:close, code, reason}
  def normalize_frame(frame), do: frame
  
  def create_response(:text, message), do: {:push, {:text, message}, state}
  def create_response(:binary, data), do: {:push, {:binary, data}, state}
  def create_response(:ping, data), do: {:push, {:pong, data}, state}
  def create_response(:close, {code, reason}), do: {:stop, :normal, state}
end
```

#### 3. Cowboy Configuration
**Rationale**: Complex dispatch and routing setup

**Current Issues**:
```elixir
# Verbose Cowboy setup
dispatch = :cowboy_router.compile([
  {:_, [
    {"/ws", WebSocketHandler, %{parent: self()}},
    {"/api/:version", ApiHandler, []},
    {:_, NotFoundHandler, []}
  ]}
])

{:ok, _} = :cowboy.start_clear(:test_server, [{:port, 0}], %{env: %{dispatch: dispatch}})
```

**Recommended Wrapper**:
```elixir
defmodule WebsockexNew.Test.Support.CowboyHelpers do
  @moduledoc "Simplified Cowboy server helpers"
  
  def start_websocket_server(opts \\ []) do
    path = Keyword.get(opts, :path, "/ws")
    handler_opts = Keyword.get(opts, :handler_opts, %{parent: self()})
    
    dispatch = :cowboy_router.compile([
      {:_, [{path, MockWebSockHandler, handler_opts}]}
    ])
    
    server_name = :"test_server_#{System.unique_integer([:positive])}"
    
    {:ok, _} = :cowboy.start_clear(
      server_name,
      [{:port, 0}],
      %{env: %{dispatch: dispatch}}
    )
    
    {_, port} = :ranch.get_addr(server_name)
    {:ok, server_name, port}
  end
  
  def stop_server(server_name) do
    :cowboy.stop_listener(server_name)
  end
end
```

### 🔄 MIXED APPROACH (Selective Wrappers)

These modules need wrappers for complex scenarios but can be used directly for simple cases:

#### 1. ExUnit Test Setup
**Rationale**: Common patterns benefit from helpers, but simple tests can use direct setup

**Direct Usage** (Simple Tests):
```elixir
setup do
  {:ok, server, port} = MockWebSockServer.start_link()
  on_exit(fn -> MockWebSockServer.stop(server) end)
  %{server: server, port: port}
end
```

**Wrapper Usage** (Complex Tests):
```elixir
defmodule WebsockexNew.Test.Support.TestHelpers do
  def setup_websocket_test(opts \\ []) do
    protocols = Keyword.get(opts, :protocols, [:http])
    
    servers = Enum.map(protocols, fn protocol ->
      {:ok, server, port} = MockWebSockServer.start_link(protocol: protocol)
      {protocol, server, port}
    end)
    
    on_exit(fn ->
      Enum.each(servers, fn {_, server, _} ->
        MockWebSockServer.stop(server)
      end)
    end)
    
    servers
    |> Enum.into(%{}, fn {protocol, server, port} ->
      {protocol, %{server: server, port: port, url: build_url(protocol, port)}}
    end)
  end
  
  defp build_url(:http, port), do: "ws://localhost:#{port}/ws"
  defp build_url(:tls, port), do: "wss://localhost:#{port}/ws"
  defp build_url(:http2, port), do: "ws://localhost:#{port}/ws"
  defp build_url(:https2, port), do: "wss://localhost:#{port}/ws"
end
```

## Implementation Recommendations

### Phase 1: Essential Wrappers
Create wrapper functions for the most complex scenarios:

1. **ServerHelpers** - Simplify MockWebSockServer setup
2. **TestHelpers** - Standardize ExUnit setup patterns

### Phase 2: Protocol Abstraction
Add protocol-specific wrappers:

1. **FrameHelpers** - Normalize WebSocket frame handling
2. **CowboyHelpers** - Simplify Cowboy configuration

### Phase 3: Performance Helpers
Add helpers for performance testing:

1. **ConcurrencyHelpers** - Multi-connection testing
2. **ThroughputHelpers** - Message rate testing

## File Structure Recommendation

```
test/support/
├── certificate_helper.ex           # Keep as-is (direct usage)
├── gun_monitor.ex                  # Keep as-is (direct usage)  
├── mock_websock_server.ex          # Keep as-is (underlying implementation)
├── mock_websock_handler.ex         # Keep as-is (underlying implementation)
├── mock_websock_server/
│   └── router.ex                   # Keep as-is
└── helpers/                        # NEW: Wrapper functions
    ├── server_helpers.ex           # MockWebSockServer wrappers
    ├── test_helpers.ex             # ExUnit setup helpers
    ├── frame_helpers.ex            # WebSocket frame helpers
    ├── cowboy_helpers.ex           # Cowboy configuration helpers
    ├── concurrency_helpers.ex      # Multi-connection testing
    └── throughput_helpers.ex       # Performance testing
```

## Usage Guidelines

### When to Use Direct APIs
- Simple single-server tests
- Certificate generation
- Basic Gun operations
- Debug monitoring

### When to Use Wrapper Functions  
- Multi-protocol testing
- Complex handler setup
- Performance testing
- Integration test scenarios
- Standardized test patterns

### Migration Strategy
1. **No breaking changes** - Keep existing modules as-is
2. **Add helpers incrementally** - Start with most common patterns
3. **Update documentation** - Show both direct and wrapper usage
4. **Deprecate gradually** - Only if wrappers prove significantly better

This analysis provides a clear path forward for improving test ergonomics while maintaining API stability and following the simplicity principles outlined in CLAUDE.md.