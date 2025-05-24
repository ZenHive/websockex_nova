# WebsockexNew Task List

## Development Status Update (December 2024)
### ✅ Recently Completed
- **WNX0019**: Heartbeat Implementation - Integrated directly into Client GenServer
- **WNX0020**: Fault-Tolerant Adapter Architecture - GenServer-based adapters with monitoring
- **WNX0023**: JSON-RPC 2.0 API Builder - Complete JSON-RPC support with Deribit integration

### 🚀 Next Up
1. **WNX0021**: Request/Response Correlation Manager (High Priority)
2. **WNX0022**: Basic Rate Limiter (High Priority)
3. **WNX0025**: Eliminate Duplicate Reconnection Logic (High Priority)

### 📊 Progress: 3/6 tasks completed (50%)

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
| WNX0021 | Request/Response Correlation Manager             | Planned    | High     | System   |               |
| WNX0022 | Basic Rate Limiter                              | Planned    | High     | System   |               |
| WNX0025 | Eliminate Duplicate Reconnection Logic          | Planned    | High     | System   |               |

## Implementation Order
1. **WNX0021**: Request/Response Correlation Manager - Essential for reliable order management
2. **WNX0022**: Basic Rate Limiter - Prevent API rate limit violations
3. **WNX0025**: Eliminate Duplicate Reconnection Logic - Clean up architecture

## Completed Tasks
| ID      | Description                                      | Status    | Priority | Assignee | Review Rating |
| ------- | ------------------------------------------------ | --------- | -------- | -------- | ------------- |
| WNX0019 | Heartbeat Implementation                         | Completed | Critical | System   | ⭐⭐⭐⭐⭐    |
| WNX0020 | Fault-Tolerant Adapter Architecture            | Completed | Critical | System   | ⭐⭐⭐⭐⭐    |
| WNX0023 | JSON-RPC 2.0 API Builder                       | Completed | High     | System   | ⭐⭐⭐⭐⭐    |

## Task Details

### WNX0019: Heartbeat Implementation (✅ COMPLETED)
**Description**: Implement automatic heartbeat processing during the entire connection lifecycle for financial trading connections. Integrated directly into Client GenServer to handle WebSocket message routing and prevent order cancellation due to connection monitoring failures.

**Simplicity Progression Plan**:
1. Convert Client from struct to GenServer for message handling
2. Integrate heartbeat timer within Client state
3. Add platform-specific heartbeat handling via helper modules
4. Implement automatic test_request response handling

**Simplicity Principle**:
Gun sends messages to the process that opened the connection. Separate heartbeat processes cannot receive WebSocket messages, requiring message routing complexity. Integrating heartbeat directly into Client GenServer eliminates this architectural constraint.

**Abstraction Evaluation**:
- **Challenge**: How to handle platform-specific heartbeat requirements without complex abstractions?
- **Minimal Solution**: Client dispatches to helper modules based on platform configuration
- **Justification**:
  1. Deribit requires `/api/v2/public/test` JSON-RPC calls
  2. Binance requires ping/pong frame responses  
  3. Platform detection through configuration, not runtime discovery

**Requirements**:
- Automatic heartbeat response to prevent connection termination
- Platform-specific handling (Deribit test_request, Binance ping/pong)
- Integration with existing Client API without breaking changes
- Production-ready fault tolerance for financial trading

**ExUnit Test Requirements**:
- Real API test against test.deribit.com verifying continuous heartbeat response
- Test heartbeat handler recovery after process failure
- Test connection termination when heartbeat responses fail
- Verify no duplicate heartbeat responses under load

**Integration Test Scenarios**:
- Long-running test (minimum 10 minutes) to verify heartbeat stability
- Test heartbeat during active market data subscription
- Verify heartbeat continues after reconnection events
- Test platform detection and appropriate heartbeat mechanism selection

**Typespec Requirements**:
- heartbeat_config :: %{type: :deribit | :binance, interval: pos_integer()}
- Platform-specific heartbeat handler function specs
- Client state with integrated heartbeat timer references

**TypeSpec Documentation**:
- Document heartbeat configuration options
- Specify platform-specific heartbeat behavior expectations
- Document integration with Client GenServer lifecycle

**TypeSpec Verification**:
- Verify heartbeat config validation at connect time
- Check platform handler module exists and exports required functions
- Validate heartbeat timer cleanup on Client termination

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
- Lines of code: ~200 (Client GenServer conversion + heartbeat integration)
- Functions per module: 5
- Lines per function: 12
- Call depth: 2
- Cyclomatic complexity: Low (simple message routing)
- Test coverage: 100% with real API testing

**Dependencies**
- gun: WebSocket transport layer
- jason: JSON encoding/decoding
- telemetry: Monitoring and observability

**Architecture Notes**
- Client converted from struct to GenServer for Gun message handling
- Heartbeat functionality integrated directly to avoid message routing overhead
- Platform-specific handlers via helper modules (helpers/deribit.ex)
- Maintains backward API compatibility through GenServer wrapper

**Status**: Completed
**Priority**: Critical

**Implementation Notes**:
- Heartbeat handling integrated directly into Client GenServer for simplicity
- Platform-specific logic delegated to helper modules (helpers/deribit.ex)
- Use Process.monitor/1 to detect Gun connection failures
- Backward API compatibility maintained with GenServer wrapper

**Complexity Assessment**:
- Previous: Client was simple struct, no message processing capability
- Current: Client as GenServer with integrated heartbeat handling
- Added Complexity: ~200 lines (Client GenServer conversion + heartbeat integration)
- Justification: Fundamental architecture requirement - Gun needs process to send messages to

**Maintenance Impact**:
- Enables all async message processing features, not just heartbeats
- Central point for WebSocket message routing and handling
- Foundation for request correlation and other financial infrastructure

**Error Handling Implementation**:
- Client GenServer crash: Supervisor restarts Client, re-establishes connection
- test_request timeout: Close connection immediately to prevent order issues
- Connection loss during heartbeat: Client triggers reconnection automatically

### WNX0020: Fault-Tolerant Adapter Architecture (✅ COMPLETED)
**Description**: GenServer-based adapter architecture that monitors Client processes and handles automatic reconnection with state restoration. Solves the critical issue of stale PID references when Client GenServers restart after crashes.

**Simplicity Progression Plan**:
1. Create GenServer adapter that monitors Client process
2. Implement automatic Client recreation on crash detection
3. Add state restoration (authentication, subscriptions)
4. Create AdapterSupervisor for multiple adapter management

**Simplicity Principle**:
Client GenServers can crash and restart, leaving adapters with stale PID references. GenServer adapters monitor Client processes and handle recreation automatically, providing true OTP fault tolerance.

**Abstraction Evaluation**:
- **Challenge**: How to handle Client crashes without losing trading state?
- **Minimal Solution**: GenServer adapter monitors Client, recreates on crash
- **Justification**:
  1. Financial trading requires automatic state restoration
  2. Manual reconnection risks missing market opportunities
  3. Supervisor pattern is proven OTP approach for fault tolerance

**Requirements**:
- Automatic detection of Client GenServer crashes
- Seamless Client recreation with state restoration
- Preservation of authentication status and subscriptions
- Production-ready supervision tree for multiple adapters

**ExUnit Test Requirements**:
- Test adapter detects Client crash via Process.monitor
- Verify automatic Client recreation after crash
- Test state restoration preserves authentication
- Verify subscription restoration after reconnection

**Integration Test Scenarios**:
- Force Client crash during active market data subscription
- Verify adapter recreates Client and restores subscriptions
- Test multiple adapters under AdapterSupervisor
- Long-running test with periodic forced crashes

**Typespec Requirements**:
- adapter_state :: %{client_pid: pid(), auth_state: term(), subscriptions: list()}
- State restoration function specifications
- AdapterSupervisor child specification types

**TypeSpec Documentation**:
- Document adapter state management requirements
- Specify state restoration callback patterns
- Document supervision tree structure and restart strategies

**TypeSpec Verification**:
- Verify adapter state includes all necessary restoration data
- Check state restoration functions handle nil/missing data
- Validate AdapterSupervisor properly manages multiple adapters

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
- Lines of code: ~300 (adapter + supervisor + state restoration)
- Functions per module: 4
- Lines per function: 15
- Call depth: 2
- Cyclomatic complexity: Medium (state restoration logic)
- Test coverage: 100% with real API testing

**Dependencies**
- websockex_new: Core WebSocket client
- gun: WebSocket transport layer
- jason: JSON encoding/decoding

**Architecture Notes**
- GenServer adapters monitor Client processes via Process.monitor
- Automatic state restoration preserves authentication and subscriptions
- AdapterSupervisor provides fault tolerance for multiple adapters
- Solves stale PID reference problem through process recreation

**Status**: Completed
**Priority**: Critical

**Implementation Notes**:
- Created GenServer-based adapter architecture monitoring Client processes
- Automatic reconnection with state restoration for authentication and subscriptions
- AdapterSupervisor manages multiple adapters with fault tolerance
- Platform-specific helper modules for clean separation (helpers/deribit.ex)

**Complexity Assessment**:
- Previous: No adapter pattern, manual Client management
- Current: GenServer adapters with automatic state restoration
- Added Complexity: ~300 lines (adapter + supervisor + state restoration)
- Benefits: True OTP-compliant fault tolerance for financial trading

**Maintenance Impact**:
- Solves stale PID reference problem completely
- Production-ready for financial trading systems
- Foundation for multiple exchange integrations
- Seamless recovery from Client GenServer crashes

**Error Handling Implementation**:
- Client GenServer crash: Adapter detects via monitor, recreates Client
- State restoration failure: Log error, attempt clean reconnection
- Adapter crash: AdapterSupervisor restarts adapter with clean state

### WNX0021: Request/Response Correlation Manager
**Description**: Track and correlate WebSocket request/response pairs for reliable order management using ETS-based correlation table with configurable timeouts and response matching.

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

**Status**: Planned
**Priority**: High

**Implementation Notes**:
- ~50 lines total implementation using ETS for O(1) performance
- Leverage existing JSON-RPC ID field for correlation
- No complex abstractions, just simple request_id -> request mapping
- Automatic integration with Client.send_message

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

### WNX0023: JSON-RPC 2.0 API Builder (✅ COMPLETED)
**Description**: Complete JSON-RPC 2.0 support with automatic request building, response parsing, and Deribit integration for all 29 API methods.

**Simplicity Progression Plan**:
1. Implement core JSON-RPC 2.0 request/response structures
2. Add automatic ID generation and correlation
3. Create Deribit-specific API method builders
4. Integrate with existing WebSocket transport

**Simplicity Principle**:
JSON-RPC 2.0 is standard protocol for WebSocket APIs. Direct implementation without abstraction layers provides optimal performance and debugging clarity for financial trading.

**Abstraction Evaluation**:
- **Challenge**: How to support multiple JSON-RPC APIs without complex abstractions?
- **Minimal Solution**: Standard JSON-RPC implementation with platform-specific builders
- **Justification**:
  1. JSON-RPC 2.0 is well-defined standard
  2. Platform-specific methods require custom parameter handling
  3. Direct implementation easier to debug than abstraction layers

**Requirements**:
- Complete JSON-RPC 2.0 specification compliance
- Automatic request ID generation and correlation
- Deribit API method support (authentication, orders, subscriptions)
- Integration with existing WebSocket Client

**ExUnit Test Requirements**:
- Test JSON-RPC request format compliance
- Verify response parsing for all message types
- Test error response handling
- Verify ID correlation between requests and responses

**Integration Test Scenarios**:
- Real Deribit authentication flow
- Test all 29 Deribit API methods
- Verify subscription management
- Test error handling with malformed responses

**Typespec Requirements**:
- jsonrpc_request :: %{jsonrpc: "2.0", method: binary(), params: term(), id: term()}
- jsonrpc_response :: %{jsonrpc: "2.0", result: term(), id: term()}
- Deribit-specific method parameter types

**TypeSpec Documentation**:
- Document JSON-RPC 2.0 message format requirements
- Specify Deribit API method parameters
- Document error response handling patterns

**TypeSpec Verification**:
- Verify JSON-RPC messages conform to specification
- Check Deribit method parameters match API documentation
- Validate error response parsing

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
- Lines of code: ~150 (JSON-RPC implementation + Deribit methods)
- Functions per module: 5
- Lines per function: 10
- Call depth: 1
- Cyclomatic complexity: Low (simple protocol handling)
- Test coverage: 100% with real API testing

**Dependencies**
- jason: JSON encoding/decoding
- websockex_new: Core WebSocket client

**Architecture Notes**
- General-purpose JSON-RPC 2.0 implementation for any WebSocket API
- Platform-specific method builders via macro system
- Direct integration with WebSocket transport layer
- Supports standard request/response correlation patterns

**Status**: Completed
**Priority**: High

**Implementation Notes**:
- Complete JSON-RPC 2.0 implementation with Deribit integration
- 29 Deribit API methods fully supported
- Automatic request building and response parsing
- Integration with existing WebSocket transport layer

**Complexity Assessment**:
- Standard JSON-RPC implementation, no custom protocol
- Platform-specific builders isolated in separate modules
- Clear separation between protocol and transport
- Minimal abstraction for maximum debugging clarity

**Maintenance Impact**:
- Foundation for any JSON-RPC WebSocket API
- Easy addition of new platforms (Binance, FTX, etc.)
- Clear request/response debugging capabilities
- No impact on core WebSocket functionality

**Error Handling Implementation**:
- JSON-RPC error responses: Parse and return as {:error, jsonrpc_error}
- JSON parsing failure: Return {:error, :invalid_json}
- Method parameter error: Return {:error, :invalid_params}

### WNX0025: Eliminate Duplicate Reconnection Logic
**Description**: Resolve duplicate reconnection mechanisms between Client internal handling and Adapter monitoring by configuring Client to disable internal reconnection when supervised.

**Simplicity Progression Plan**:
1. Add reconnect_on_error configuration flag to Client
2. Update DeribitGenServerAdapter to set reconnect_on_error: false
3. Test adapter handles all reconnection when flag is false
4. Document reconnection patterns in architecture guide

**Simplicity Principle**:
Current architecture has duplicate reconnection mechanisms creating redundant attempts and unclear responsibility boundaries. Simple configuration flag eliminates duplication with clear ownership.

**Abstraction Evaluation**:
- **Challenge**: How to eliminate duplicate reconnection without breaking existing functionality?
- **Minimal Solution**: Configuration flag to disable Client reconnection when supervised
- **Justification**:
  1. Adapters need full control over reconnection for state restoration
  2. Configuration provides backward compatibility
  3. Clear ownership prevents race conditions

**Requirements**:
- Configuration flag to disable Client internal reconnection
- Adapter explicitly manages all reconnection when Client supervised
- Backward compatibility with existing standalone Client usage
- Clear documentation of reconnection patterns

**ExUnit Test Requirements**:
- Test Client stops cleanly on connection errors when supervised
- Verify adapter handles all reconnection when flag is false
- Test standalone Client continues internal reconnection by default
- Verify no duplicate reconnection attempts in supervised mode

**Integration Test Scenarios**:
- Test supervised Client with network interruption
- Verify adapter recreates Client on crash
- Test standalone Client with automatic reconnection
- Verify state restoration works correctly

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

**Status**: Planned
**Priority**: High

**Implementation Notes**:
- One configuration flag eliminates duplication
- Backward compatible with existing code
- Clear ownership: supervised → adapter handles, standalone → client handles
- Minimal code changes, maximum clarity

**Complexity Assessment**:
- Minimal change to existing Client configuration
- Clear separation of concerns maintained
- No changes to critical heartbeat functionality
- Simple boolean flag controls behavior

**Maintenance Impact**:
- Eliminates confusion about reconnection responsibility
- Clear patterns for building new adapters
- Simplified debugging of connection issues
- Foundation for consistent adapter implementations

**Error Handling Implementation**:
- Configuration error: Return {:error, :invalid_reconnection_config}
- Client supervised shutdown: Clean exit, let adapter handle
- Adapter recreation failure: Log error, attempt retry with backoff

## Implementation Notes
WebsockexNew provides production-grade WebSocket functionality for financial trading systems with emphasis on simplicity, reliability, and real-world testing. All implementations follow strict complexity budgets and proven patterns.

## Platform Integration Notes
Primary integration with Deribit cryptocurrency exchange platform providing authentication, heartbeat handling, order management, and market data subscriptions. Architecture supports additional platforms through helper module pattern.