# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**WebsockexNew** is a robust WebSocket client library for Elixir, specifically designed for financial APIs (particularly Deribit cryptocurrency trading). It uses Gun transport with a clean 8-module architecture prioritizing simplicity and real-world reliability.

**Financial Development Principle**: Start simple, add complexity only when necessary based on real data. This is a well-established principle in financial software development, especially for market making.

## Development Commands

### Core Development
- `mix compile` - Compile the project
- `mix test` - Run test suite (93 tests, all using real APIs)
- `mix test --cover` - Run tests with coverage reporting
- `mix coverage` - Alias for test with coverage

### Code Quality Tools
- `mix lint` - Run Credo static analysis in strict mode
- `mix typecheck` - Run Dialyzer type checking  
- `mix security` - Run Sobelow security analysis
- `mix check` - Run all quality checks (lint + typecheck + security + coverage)
- `mix rebuild` - Full rebuild (clean deps, recompile, run all checks)

### Documentation
- `mix docs` - Generate documentation

### Testing Commands
- `mix test.api` - Run real API integration tests (via lib/mix/tasks/test.ex)
- `mix test.api --deribit` - Deribit-specific API tests
- `mix test.performance` - Performance and stress testing

## Architecture

### Core Modules (8 total)
```
lib/websockex_new/
├── client.ex              # Main client interface (5 public functions)
├── config.ex              # Configuration struct and validation
├── frame.ex               # WebSocket frame encoding/decoding  
├── connection_registry.ex # ETS-based connection tracking
├── reconnection.ex        # Exponential backoff retry logic
├── message_handler.ex     # Message parsing and routing
├── error_handler.ex       # Error categorization and recovery
└── examples/
    └── deribit_adapter.ex # Deribit platform integration
```

### Public API (Only 5 Functions)
```elixir
# Everything users need for WebSocket operations
WebsockexNew.Client.connect(url, opts)
WebsockexNew.Client.send_message(client, message) 
WebsockexNew.Client.close(client)
WebsockexNew.Client.subscribe(client, channels)
WebsockexNew.Client.get_state(client)
```

### Design Principles (Strict Simplicity Constraints)
- **Maximum 8 modules** in main library
- **Maximum 5 functions per module**  
- **Maximum 15 lines per function**
- **No behaviors** (was 9 in legacy system)
- **No GenServers** (functional approach preferred)
- **Real API testing only** - zero mocks policy
- **Start simple** - implement minimal viable solution first
- **Add complexity incrementally** - only when proven necessary by real data

## Code Style Guidelines

### Documentation Optimization
Balance token optimization with readability:

**DO (Optimized Documentation):**
```elixir
@moduledoc """
WebSocket client for real-time cryptocurrency trading APIs.

- Uses Gun transport for WebSocket connections
- Handles automatic reconnection with exponential backoff
- Supports message routing and frame handling
"""

@doc """
Connects to WebSocket endpoint with configuration options.

Returns client struct for subsequent operations.
"""
```

**DON'T (Verbose Documentation):**
```elixir
@moduledoc """
This module provides a comprehensive WebSocket client implementation
specifically designed for cryptocurrency trading platforms. It offers
robust connection management, automatic reconnection capabilities,
and efficient message handling for real-time market data streaming.
"""
```

### Function Structure
**DO (Optimized Code Structure):**
```elixir
def connect(%Config{url: url} = config, opts \\ []) do
  timeout = config.timeout
  headers = config.headers

  with {:ok, gun_pid} <- open_connection(url, opts),
       {:ok, stream_ref} <- upgrade_to_websocket(gun_pid, headers),
       :ok <- await_websocket_upgrade(gun_pid, stream_ref, timeout) do
    {:ok, %Client{gun_pid: gun_pid, stream_ref: stream_ref, state: :connected}}
  else
    error -> {:error, error}
  end
end
```

**DON'T (Verbose, Complex Structure):**
```elixir
def establish_websocket_connection_with_configuration(configuration_parameters, additional_options \\ []) do
  # Complex, verbose implementation with unnecessary abstraction
end
```

## Configuration

### Environment Setup
Required environment variables for Deribit integration:
```bash
export DERIBIT_CLIENT_ID="your_client_id" 
export DERIBIT_CLIENT_SECRET="your_client_secret"
```

### Configuration Options
WebsockexNew.Config supports 6 essential options:
- `url` - WebSocket endpoint URL
- `headers` - Connection headers  
- `timeout` - Connection timeout (default: 5000ms)
- `retry_count` - Maximum retry attempts (default: 3)
- `retry_delay` - Initial retry delay (default: 1000ms) 
- `heartbeat_interval` - Ping interval (default: 30000ms)

## Testing Strategy

### Real API Testing Policy (CRITICAL)
**NO MOCKS ALLOWED** - This project uses ONLY real API testing:
- `test.deribit.com` for Deribit integration
- Local mock servers using existing `MockWebSockServer` infrastructure
- Real network conditions and error scenarios

**Testing Rationale**: Financial software requires testing against real conditions - network latency, connection drops, actual API behavior. Mocks hide real-world edge cases that can cause financial losses.

### Test Structure
```
test/websockex_new/           # Core module tests
test/integration/             # Real API integration tests  
test/support/                 # Shared test infrastructure
```

### Integration Test Requirements
- Tag integration tests with `@tag :integration`
- Test realistic scenarios including market conditions
- Verify end-to-end functionality across component boundaries
- Document test scenarios with clear descriptions

**Example Integration Test:**
```elixir
@tag :integration
test "maintains subscriptions across reconnection", %{deribit_config: config} do
  # Use real Deribit testnet connection (no mocks)
  {:ok, client} = WebsockexNew.Client.connect(config.url, config.opts)

  # Subscribe to real market data
  {:ok, _} = WebsockexNew.Client.subscribe(client, ["book.BTC-PERPETUAL.raw"])
  
  # Simulate connection drop
  Process.exit(client.gun_pid, :kill)
  
  # Verify reconnection and subscription restoration
  wait_for_reconnection(client)
  assert_subscription_active(client, "book.BTC-PERPETUAL.raw")
end
```

### Key Test Support Modules
- `MockWebSockServer` - Controlled WebSocket server for testing
- `CertificateHelper` - TLS certificate generation  
- `NetworkSimulator` - Network condition simulation
- `TestEnvironment` - Environment management

## Error Handling Architecture

### Core Principles
- **Pass raw errors** without wrapping in custom structs
- **Use consistent {:ok, result} | {:error, reason} pattern**
- **Apply "let it crash" philosophy** for unexpected errors
- **Add minimal context** information only when necessary

### Error Categories
- **Connection errors** - Network failures, timeouts
- **Protocol errors** - Malformed WebSocket frames  
- **Authentication errors** - Invalid credentials
- **Application errors** - Business logic failures

### Error Handling Pattern
**DO (Pattern Matching on Raw Errors):**
```elixir
def handle_connection_error({:error, error}) do
  case error do
    {:timeout, _duration} -> handle_timeout_error()
    {:connection_refused, _details} -> handle_connection_refused()
    {:protocol_error, frame_error} -> handle_frame_error(frame_error)
    _ -> {:error, :unknown_connection_error}
  end
end
```

**DON'T (Custom Error Transformation):**
```elixir
def handle_connection_error({:error, error}) do
  # Don't transform errors unnecessarily
  error_type = classify_websocket_error(error)
  # Complex transformation logic...
end
```

### Recovery Patterns
- Exponential backoff reconnection with state preservation
- Automatic subscription re-establishment  
- Comprehensive error categorization for appropriate handling

## Simplicity Guidelines

### Foundational Principles
- **Code simplicity is a primary feature**, not an afterthought
- **Implement minimal viable solution first**
- **Each component has a limited "complexity budget"**
- **Create abstractions only with proven value** (≥3 concrete examples)
- **Start simple and add complexity incrementally**
- **Prioritize execution and practical operational efficiency**

### Module Structure Limits
- **Maximum 8 modules total** in main library (already achieved)
- **Maximum 5 functions per module** initially
- **Maximum function length of 15 lines**
- **Maximum of 2 levels of function calls** for any operation
- **Prefer pure functions over processes** when possible

### Anti-Patterns to Avoid
- No premature optimization without performance data
- No "just-in-case" code for hypothetical requirements
- No abstractions without at least 3 concrete usage examples
- No complex macros unless absolutely necessary
- No overly clever solutions that prioritize elegance over maintainability

**Remember**: "The elegance comes from doing less, not more. Removing complexity, not adding it!"

## WebSocket Connection Architecture

### Connection Model
- WebSocket connections are Gun processes managed by WebsockexNew.Client
- Connection processes are monitored, not owned by complex supervisors
- Failures detected by `Process.monitor/1` and classified by exit reasons

### Reconnection Requirements
**DO (Follow Established Pattern):**
```elixir
{:ok, client} = WebsockexNew.Client.connect(url, [
  timeout: 5000,
  retry_count: 3,
  retry_delay: 1000,
  heartbeat_interval: 30000
])
```

**DON'T (Custom Reconnection Logic):**
```elixir
# Don't create custom reconnection loops outside the framework
```

## Platform Integration

### Deribit Adapter
Complete Deribit cryptocurrency exchange integration:
- Authentication flow
- Subscription management  
- Heartbeat/test_request handling
- JSON-RPC 2.0 message formatting
- Cancel-on-disconnect protection

Located in `lib/websockex_new/examples/deribit_adapter.ex`

## Key Dependencies

### Core Runtime
- `gun ~> 2.2` - HTTP/2 and WebSocket client
- `jason ~> 1.4` - JSON encoding/decoding
- `telemetry ~> 1.3` - Metrics and monitoring

### Development Tools  
- `credo ~> 1.7` - Static code analysis
- `dialyxir ~> 1.4` - Type checking
- `sobelow ~> 0.13` - Security scanning
- `ex_doc ~> 0.31` - Documentation generation

### Testing Infrastructure
- `cowboy ~> 2.10` - Test WebSocket server
- `websock ~> 0.5` - WebSocket protocol handling
- `stream_data ~> 1.0` - Property-based testing
- `x509 ~> 0.8` - Certificate generation for testing

## Working with the Codebase

### Adding New Features (TDD Approach)
1. **Write tests first** following TDD principles
2. **Implement in single module** with max 5 functions
3. **Add real API tests** (no mocks)
4. **Update configuration** if needed
5. **Run `mix check`** to validate all quality gates
6. **Update documentation**

### Code Quality Standards
- All public functions must have `@spec` annotations
- All modules must have `@moduledoc` documentation
- Follow functional, declarative style with pattern matching
- Use tagged tuples for consistent error handling
- Pass all static checks: `mix format`, `mix credo --strict`, `mix dialyzer`

### Debugging
- Maximum 2 modules to trace any issue
- All errors categorized in `error_handler.ex`
- Telemetry events for monitoring
- Comprehensive logging at appropriate levels

### Performance Considerations
- ETS-based connection registry for fast lookups
- Minimal process overhead (no GenServers in core path)
- Efficient frame encoding/decoding
- Connection pooling via Gun transport layer

## Integration Notes

### For Financial Trading
This library targets market makers and option sellers requiring:
- **High-frequency API calls**
- **Reliable reconnection with state preservation**  
- **Real-time market data subscriptions**
- **Risk management API integration**
- **Sub-millisecond latency requirements**

### Extending for Other Platforms
Follow the Deribit adapter pattern in `examples/` directory:
1. **Implement platform-specific authentication**
2. **Add subscription message formatting**
3. **Handle platform heartbeat requirements**  
4. **Create comprehensive real API tests**
5. **Document integration patterns**
6. **Follow simplicity principles** - start minimal, add complexity only when proven necessary

## Task Management

### Task ID Format
Use `WNX####` format for all WebSocket-related tasks:
- Core functionality: WNX0001-WNX0099
- Feature enhancements: WNX0100-WNX0199
- Documentation: WNX0200-WNX0299
- Testing: WNX0300-WNX0399

### Required Task Sections
Each task must include:
- Description and Simplicity Progression Plan
- Abstraction Evaluation with concrete use cases
- ExUnit and Integration Test Requirements
- Error Handling patterns specific to WebSocket/Gun errors
- Implementation Notes and Complexity Assessment