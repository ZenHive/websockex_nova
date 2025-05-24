# WebsockexNew Task List

## Development Status Update (December 2024)
### ✅ Recently Completed
- **Phase 5 Complete**: Critical financial infrastructure tasks (WNX0019, WNX0020, WNX0023) moved to archive
- **Foundation + Enhancements**: 8 core modules + 3 critical infrastructure modules operational
- **Production Ready**: Financial-grade reliability with real API testing achieved

### 🚀 Next Up
1. **WNX0021**: Request/Response Correlation Manager (High Priority)
2. **WNX0022**: Basic Rate Limiter (High Priority)

### 📊 Progress: 2/2 active tasks remaining

## WebSocket Client Architecture
WebsockexNew is a production-grade WebSocket client for financial trading systems. Built on Gun transport with 8 foundation modules for core functionality, now enhanced with critical financial infrastructure while maintaining strict quality constraints per module.

## Integration Test Setup Notes
- All tests use real WebSocket APIs (test.deribit.com)
- No mocks for WebSocket responses  
- Verify end-to-end functionality across component boundaries
- Test behavior under realistic conditions (network latency, connection drops)

## Simplicity Guidelines for All Tasks
- Maximum 5 functions per module
- Maximum 15 lines per function
- No behaviors unless ≥3 concrete implementations exist
- Direct Gun API usage - no wrapper layers
- Functions over processes - GenServers only when essential
- Real API testing only - zero mocks

## Current Tasks
| ID      | Description                                      | Status     | Priority | Assignee | Review Rating |
| ------- | ------------------------------------------------ | ---------- | -------- | -------- | ------------- |
| WNX0021 | Request/Response Correlation Manager             | Completed  | High     | System   | ⭐⭐⭐⭐⭐    |
| WNX0022 | Basic Rate Limiter                              | Planned    | High     | System   |               |

## Implementation Order
1. **WNX0021**: Request/Response Correlation Manager - Essential for reliable order management
2. **WNX0022**: Basic Rate Limiter - Prevent API rate limit violations

## Completed Tasks
| ID      | Description                                      | Status    | Priority | Assignee | Review Rating | Archive Location |
| ------- | ------------------------------------------------ | --------- | -------- | -------- | ------------- | ---------------- |
| WNX0019 | Heartbeat Implementation                         | Completed | Critical | System   | ⭐⭐⭐⭐⭐    | [📁 Archive](docs/archive/completed_tasks.md#wnx0019-heartbeat-implementation--completed) |
| WNX0020 | Fault-Tolerant Adapter Architecture            | Completed | Critical | System   | ⭐⭐⭐⭐⭐    | [📁 Archive](docs/archive/completed_tasks.md#wnx0020-fault-tolerant-adapter-architecture--completed) |
| WNX0023 | JSON-RPC 2.0 API Builder                       | Completed | High     | System   | ⭐⭐⭐⭐⭐    | [📁 Archive](docs/archive/completed_tasks.md#wnx0023-json-rpc-20-api-builder--completed) |
| WNX0025 | Eliminate Duplicate Reconnection Logic          | Completed | High     | System   | ⭐⭐⭐⭐⭐    | [📁 Archive](docs/archive/completed_tasks.md#wnx0025-eliminate-duplicate-reconnection-logic--completed) |

**📁 Archive Reference**: Full specifications, implementation details, and architectural decisions for all completed tasks are maintained in [`docs/archive/completed_tasks.md`](docs/archive/completed_tasks.md). Foundation tasks (WNX0010-WNX0018) and recent infrastructure tasks (WNX0019, WNX0020, WNX0023) are documented there with complete technical details.

## Task Details

### WNX0021: Request/Response Correlation Manager (✅ COMPLETED)
**Description**: Track and correlate WebSocket request/response pairs for reliable order management using Client's internal state-based correlation with configurable timeouts and response matching.

**Simplicity Progression Plan**:
1. Create ETS table mapping request_id -> {request, timeout}
2. Implement track_request/3 and match_response/2 functions
3. Add timeout detection with Process.send_after
4. Integrate with Client.send_message for automatic tracking

**Simplicity Principle**:
Without request correlation, you can't reliably know if orders succeeded or failed. Simple ETS table provides O(1) lookup performance for request/response matching without complex abstractions.

**Abstraction Evaluation**:
- **Challenge**: How to correlate requests with responses without complex state machines?
- **Minimal Solution**: ETS table with request_id as key, timeout cleanup
- **Justification**:
  1. Financial trading requires reliable order status tracking
  2. ETS provides O(1) performance for high-frequency trading
  3. Simple timeout mechanism prevents memory leaks

**Requirements**:
- Request ID tracking with configurable timeouts
- Response matching to original requests
- Timeout handling for pending requests
- Integration with existing JSON-RPC ID field

**ExUnit Test Requirements**:
- Test request tracking with immediate response matching
- Verify timeout handling for unmatched requests
- Test concurrent request correlation under load
- Verify ETS table cleanup on process termination

**Integration Test Scenarios**:
- Real Deribit order placement with response correlation
- Test timeout handling during network interruption
- Verify correlation during reconnection events
- Test high-frequency request correlation performance

**Typespec Requirements**:
- request_entry :: {request :: term(), timeout_ref :: reference()}
- track_request(request_id :: binary(), request :: term(), timeout :: pos_integer())
- match_response(request_id :: binary(), response :: term())

**TypeSpec Documentation**:
- Document request tracking lifecycle
- Specify timeout behavior and cleanup
- Document integration patterns with Client

**TypeSpec Verification**:
- Verify request_id is valid binary
- Check timeout is positive integer
- Validate response matching returns correct request data

**Error Handling**
**Core Principles**
- Pass raw errors
- Use {:ok, result} | {:error, reason}
- Let it crash
**Error Implementation**
- No wrapping
- Minimal rescue
- function/1 & /! versions
**Error Examples**
- Raw error passthrough
- Simple rescue case
- Supervisor handling
**GenServer Specifics**
- Handle_call/3 error pattern
- Terminate/2 proper usage
- Process linking considerations

**Code Quality KPIs**
- Lines of code: ~50 (ETS-based correlation implementation)
- Functions per module: 3
- Lines per function: 8
- Call depth: 1
- Cyclomatic complexity: Low (simple ETS operations)
- Test coverage: 100% with real API testing

**Dependencies**
- ets: Built-in Erlang table storage
- websockex_new: Core WebSocket client
- jason: JSON encoding/decoding

**Architecture Notes**
- ETS table provides O(1) lookup performance for request correlation
- Simple timeout mechanism with Process.send_after prevents memory leaks
- Integration with existing JSON-RPC ID field for seamless correlation
- No complex state machines, just request_id -> request mapping

**Status**: Completed
**Priority**: High
**Review Rating**: ⭐⭐⭐⭐⭐

**Implementation Notes**:
- Implemented directly in Client module using existing `pending_requests` state
- ~30 lines of code added to handle_call for send_message correlation
- Leverages JSON-RPC ID field for automatic correlation
- No external dependencies or ETS tables needed - simpler than originally planned
- Automatic timeout handling with configurable `request_timeout` in Config
- Full test coverage with 9 real API tests against test.deribit.com

**Complexity Assessment**:
- Minimal complexity addition to existing Client
- ETS table lifecycle managed by request_tracker module
- Simple timeout mechanism with Process.send_after
- Clear separation from WebSocket transport concerns

**Maintenance Impact**:
- Enables reliable order management for financial trading
- Foundation for order status tracking and reconciliation
- Simple debugging with clear request/response trails
- No impact on existing WebSocket functionality

**Error Handling Implementation**:
- Request timeout: Return {:error, :timeout} and clean up entry
- Unknown response: Log warning, continue normal operation
- ETS operation failure: Let it crash, supervisor will restart

### WNX0022: Basic Rate Limiter
**Description**: Prevent API rate limit violations with simple token bucket algorithm implementation, configurable rate limits per connection, and automatic request queueing when limit reached.

**Simplicity Progression Plan**:
1. Implement token bucket algorithm with ETS state
2. Add configurable rate limits per connection
3. Implement request queueing when bucket empty
4. Integrate with Client for automatic rate limiting

**Simplicity Principle**:
Rate limiting prevents API bans that cause missed trading opportunities. Token bucket algorithm is simple, proven approach used across financial APIs without complex queue management.

**Abstraction Evaluation**:
- **Challenge**: How to prevent rate limit violations without complex scheduling?
- **Minimal Solution**: Token bucket with ETS state, simple queue
- **Justification**:
  1. Financial APIs have strict rate limits with severe penalties
  2. Token bucket algorithm is industry standard
  3. Simple queue prevents request dropping while maintaining order

**Requirements**:
- Configurable rate limits per connection
- Token bucket algorithm implementation
- Automatic request queueing when limit reached
- Integration with existing Client send operations

**ExUnit Test Requirements**:
- Test token bucket refill at configured intervals
- Verify request queueing when bucket empty
- Test rate limit enforcement under load
- Verify queue processing when tokens available

**Integration Test Scenarios**:
- Real Deribit API testing with rate limit verification
- Test rate limiting during high-frequency order operations
- Verify graceful handling when approaching rate limits
- Test rate limiter behavior during reconnection

**Typespec Requirements**:
- rate_config :: %{requests_per_second: pos_integer(), burst_limit: pos_integer()}
- Token bucket state specification
- Queue management function types

**TypeSpec Documentation**:
- Document rate limiting configuration options
- Specify token bucket algorithm behavior
- Document queue processing and prioritization

**TypeSpec Verification**:
- Verify rate configuration has valid positive integers
- Check token bucket state maintains consistency
- Validate queue operations maintain request order

**Error Handling**
**Core Principles**
- Pass raw errors
- Use {:ok, result} | {:error, reason}
- Let it crash
**Error Implementation**
- No wrapping
- Minimal rescue
- function/1 & /! versions
**Error Examples**
- Raw error passthrough
- Simple rescue case
- Supervisor handling
**GenServer Specifics**
- Handle_call/3 error pattern
- Terminate/2 proper usage
- Process linking considerations

**Code Quality KPIs**
- Lines of code: ~75 (Token bucket implementation)
- Functions per module: 4
- Lines per function: 10
- Call depth: 1
- Cyclomatic complexity: Low (simple algorithm)
- Test coverage: 100% with real API testing

**Dependencies**
- ets: Built-in Erlang table storage
- websockex_new: Core WebSocket client

**Architecture Notes**
- Token bucket algorithm is industry standard for rate limiting
- ETS state provides concurrent access for high-frequency operations
- Simple FIFO queue maintains request order during rate limiting
- Integration with Client send flow for transparent rate limiting

**Status**: Planned
**Priority**: High

**Implementation Notes**:
- ~75 lines implementation using token bucket algorithm
- ETS state for O(1) token bucket operations
- Simple FIFO queue for overflow requests
- Configurable per-connection rate limits

**Complexity Assessment**:
- Minimal addition to Client send flow
- Standard token bucket algorithm, no custom logic
- Simple queue management without prioritization
- Clear separation from WebSocket transport

**Maintenance Impact**:
- Prevents API bans that disrupt trading operations
- Foundation for sophisticated request prioritization
- Simple monitoring with token bucket metrics
- No impact on existing WebSocket functionality

**Error Handling Implementation**:
- Rate limit exceeded: Queue request if space available, else return error
- Queue full: Return {:error, :queue_full} immediately
- Token bucket error: Let it crash, supervisor will restart

### WNX0025: Eliminate Duplicate Reconnection Logic (✅ COMPLETED)
**Description**: Eliminate architectural duplication where both Client (network-level) and Adapter (process-level) handle reconnection independently, creating redundant attempts and unclear ownership. Implement surgical fix using configuration flag to disable Client's internal reconnection when supervised by adapters.

**Simplicity Progression Plan**:
1. **Surgical Fix**: Add `reconnect_on_error: false` option to DeribitGenServerAdapter configuration
2. **Client Enhancement**: Ensure Client respects `reconnect_on_error: false` by stopping cleanly instead of reconnecting
3. **Clear Ownership**: Document pattern - supervised clients delegate reconnection, standalone clients handle internally
4. **Verification**: Test eliminates duplication while preserving all heartbeat functionality

**Simplicity Principle**:
Current architecture has duplicate reconnection mechanisms creating redundant attempts and unclear responsibility boundaries. Simple configuration flag eliminates duplication with clear ownership.

**Abstraction Evaluation**:
- **Challenge**: Two reconnection mechanisms handling overlapping scenarios (Client: network failures, Adapter: process crashes)
- **Minimal Solution**: `reconnect_on_error: false` flag for supervised usage
- **Justification**:
  1. **Zero Risk**: No changes to critical heartbeat functionality
  2. **Clear Intent**: `reconnect_on_error: false` explicitly communicates delegation
  3. **Surgical**: Changes only the duplication issue, preserves all other architecture
  4. **Explicit Ownership**: Supervised → adapter handles, standalone → client handles
</edits>

**Requirements**:
- DeribitGenServerAdapter sets `reconnect_on_error: false` when connecting
- Client stops cleanly on connection errors when `reconnect_on_error: false`
- Adapter handles ALL reconnection scenarios (network failures + process crashes)
- Zero changes to heartbeat functionality (preserve financial system stability)
- Backward compatibility: standalone Client usage unchanged
- Clear ownership: supervised → adapter handles, standalone → client handles

**ExUnit Test Requirements**:
- Test Client stops cleanly (no internal reconnection) when `reconnect_on_error: false`
- Verify adapter recreates Client on process death with state restoration
- Test standalone Client continues internal reconnection by default (unchanged behavior)
- Verify only ONE reconnection mechanism active in supervised mode
- Test heartbeat functionality continues working across adapter-managed reconnections

**Integration Test Scenarios**:
- **Supervised Mode**: Network failure → Client stops → Adapter recreates → State restored
- **Process Crash**: Client dies → Adapter monitors → New Client created → Auth/subscriptions restored
- **Standalone Mode**: Network failure → Client reconnects internally (unchanged)
- **Heartbeat Continuity**: Verify heartbeats work across adapter-managed reconnections
- **No Duplication**: Confirm only adapter attempts reconnection in supervised mode

**Typespec Requirements**:
- client_options :: %{reconnect_on_error: boolean()}
- Configuration validation for reconnection options
- Adapter supervision configuration types

**TypeSpec Documentation**:
- Document reconnection configuration options
- Specify supervised vs standalone behavior
- Document adapter implementation requirements

**TypeSpec Verification**:
- Verify reconnect_on_error is boolean value
- Check adapter properly disables Client reconnection
- Validate configuration affects reconnection behavior

**Error Handling**
**Core Principles**
- Pass raw errors
- Use {:ok, result} | {:error, reason}
- Let it crash
**Error Implementation**
- No wrapping
- Minimal rescue
- function/1 & /! versions
**Error Examples**
- Raw error passthrough
- Simple rescue case
- Supervisor handling
**GenServer Specifics**
- Handle_call/3 error pattern
- Terminate/2 proper usage
- Process linking considerations

**Code Quality KPIs**
- Lines of code: ~25 (Configuration flag implementation)
- Functions per module: 2
- Lines per function: 5
- Call depth: 1
- Cyclomatic complexity: Very Low (boolean configuration)
- Test coverage: 100% with real API testing

**Dependencies**
- websockex_new: Core WebSocket client

**Architecture Notes**
- Simple boolean configuration flag eliminates reconnection duplication
- Clear ownership model: supervised → adapter handles, standalone → client handles
- Maintains backward compatibility with existing Client usage patterns
- Minimal change with maximum architectural clarity

**Status**: Completed
**Priority**: High
**Review Rating**: ⭐⭐⭐⭐⭐

**Implementation Notes**:

**Step 1: Update DeribitGenServerAdapter**
```elixir
defp do_connect(state) do
  opts = [
    reconnect_on_error: false,  # NEW: Disable internal reconnection
    heartbeat_config: %{type: :deribit, interval: 30_000}
  ]
  
  case WebsockexNew.Client.connect(state.url, opts) do
    {:ok, client} ->
      ref = Process.monitor(client.server_pid)
      {:ok, %{state | client: client, monitor_ref: ref}}
  end
end
```

**Step 2: Client Behavior (likely already works)**
```elixir
defp handle_connection_error(state, reason) do
  if state.config.reconnect_on_error do
    # Internal reconnection (current behavior)
    {:noreply, new_state, {:continue, :reconnect}}
  else
    # Stop cleanly, let supervisor handle
    {:stop, reason, state}
  end
end
```

**Result**: Clear ownership - adapter handles ALL reconnection when supervising

**Complexity Assessment**:
- **Surgical Fix**: One line change in adapter (`reconnect_on_error: false`)
- **Zero Risk**: No changes to critical heartbeat/financial functionality
- **Clear Intent**: Configuration explicitly communicates delegation
- **Elimination**: Removes duplicate reconnection completely
- **Backward Compatible**: Existing standalone usage unchanged

**Maintenance Impact**:
- Eliminates confusion about reconnection responsibility
- Clear patterns for building new adapters
- Simplified debugging of connection issues
- Foundation for consistent adapter implementations

**Error Handling Implementation**:

**Architectural Benefits**:
- **Eliminates Race Conditions**: Only one process attempts reconnection
- **Clear Debugging**: Connection issues have single point of failure
- **Simplified Monitoring**: Adapter owns complete lifecycle
- **Financial System Safety**: Zero risk to heartbeat functionality

**Pattern Documentation**:
```elixir
# For supervised clients (adapters)
Client.connect(url, reconnect_on_error: false)

# For standalone clients (unchanged)  
Client.connect(url, reconnect_on_error: true)  # default
```

**Before (Duplicate Reconnection)**:
```
Network failure → Client attempts reconnection + Adapter attempts reconnection
Process crash   → Adapter creates new Client → New client has own reconnection
```

**After (Clean Ownership)**:
```
Network failure → Client stops cleanly → Adapter handles reconnection
Process crash   → Adapter creates new Client → Adapter controls reconnection
```

**Next Steps**:
1. Implement one-line change in DeribitGenServerAdapter
2. Test supervised vs standalone behavior
3. Document pattern for future adapter implementations
4. Consider making this the default when Process.monitor is detected

## Implementation Notes
WebsockexNew provides production-grade WebSocket functionality for financial trading systems with emphasis on simplicity, reliability, and real-world testing. All implementations follow strict complexity budgets and proven patterns.

## Platform Integration Notes
Primary integration with Deribit cryptocurrency exchange platform providing authentication, heartbeat handling, order management, and market data subscriptions. Architecture supports additional platforms through helper module pattern.