# WebsockexNew Complete Rewrite Tasks

## Current Progress Status
**Last Updated**: 2025-05-23  
**Phase**: Critical Financial Infrastructure (WNX0019-WNX0021)  
**Foundation**: Complete ✅ (All Phase 1-4 tasks archived)

### 📊 Current Architecture Status
- **Foundation Complete**: All 8 core modules implemented and tested ✅
- **Enhancement Phase**: Adding critical financial infrastructure modules 🚧
- **Public API**: 5 core functions fully functional ✅
- **Test Coverage**: 121 tests, 100% real API testing ✅
- **Platform Integration**: Deribit adapter with 29 API methods ✅

### ✅ Completed Tasks Archive
**All completed foundation and migration tasks have been moved to:**
📁 `docs/archive/completed_tasks.md` - Foundation tasks (WNX0010-WNX0018)
📁 `docs/archive/completed_migration.md` - Migration process and tasks (WNX0023-WNX0024)
📁 `docs/WNX0019_learnings.md` - Heartbeat integration architecture learnings

**Foundation Summary**:
- 8 core modules: Client (now GenServer), Config, Frame, ConnectionRegistry, Reconnection, MessageHandler, ErrorHandler, JsonRpc
- 5 public API functions: connect, send, close, subscribe, get_state  
- 121 tests passing with 100% real API testing
- Complete Deribit integration with authentication, subscriptions, and heartbeat handling
- JSON-RPC 2.0 support for any compatible WebSocket API

---

## Project Goal
WebsockexNew is a production-grade WebSocket client for financial trading systems. Starting with 8 foundation modules for core functionality, we're now enhancing it with critical financial infrastructure while maintaining strict quality constraints per module. Built on Gun transport with proven simplicity principles.

## Core Architecture Principles (Enhancement Phase)
- **Foundation Phase Complete** - 8 core modules established ✅
- **Enhancement Phase Active** - Adding critical financial infrastructure
- **Maximum 5 functions per module** for all modules
- **Maximum 15 lines per function**
- **No behaviors** unless ≥3 concrete implementations exist
- **Direct Gun API usage** - no wrapper layers
- **Functions over processes** - GenServers only when essential
- **Real API testing only** - zero mocks

---

## Active Critical Financial Infrastructure Tasks

### WNX0019: Heartbeat Implementation ✅
**Status**: COMPLETED - Integrated directly into Client GenServer
**Priority**: Critical  
**Effort**: Large (required Client refactor)  
**Dependencies**: None

**Implementation Summary**: Following architectural analysis, heartbeat functionality was integrated directly into the Client GenServer rather than creating a separate process. This simpler approach provides better performance and maintains all benefits while reducing complexity and eliminating message routing overhead.

### WNX0020: Fault-Tolerant Adapter Architecture ✅
**Status**: COMPLETED - GenServer-based adapters with Client monitoring  
**Priority**: Critical  
**Effort**: Medium  
**Dependencies**: Client as GenServer (WNX0019)

**Implementation Summary**: Created GenServer-based adapter architecture that monitors Client processes and handles automatic reconnection with state restoration. This solves the critical issue of stale PID references when Client GenServers restart after crashes.

**Platform-Specific Handling**: Created helper modules architecture for clean separation:
- `lib/websockex_new/helpers/deribit.ex` - Deribit-specific heartbeat handling
- Future: `helpers/binance.ex` for Binance ping/pong frames
- Client dispatches to helpers based on platform configuration

#### Target Implementation
**PRODUCTION-READY APPROACH**: Implement automatic heartbeat processing during the entire connection lifecycle, not just bootstrap. Financial trading connections require continuous, automatic heartbeat handling to prevent order cancellation due to connection monitoring failures.

#### Technical Requirements (CRITICAL - FINANCIAL TRADING)
**Heartbeat Sequence**: When heartbeats have been set up, the API server will send heartbeat messages and test_request messages. Your software should respond to test_request messages by sending a `/api/v2/public/test` request. If your software fails to do so, the API server will immediately close the connection. If your account is configured to cancel on disconnect, any orders opened over the connection will be cancelled.

**Production Risk**: A simple loop is insufficient for production financial trading. Heartbeat failures can cause immediate order cancellation, resulting in financial losses.

#### Architecture Issue Discovered
**Architectural Learning**: Separate heartbeat processes cannot receive WebSocket messages because:
1. Gun sends messages to the process that opened the connection
2. WebSocket connections are owned by Client process
3. Message routing adds complexity and performance overhead

**Solution**: Integrating heartbeat functionality directly into the Client GenServer eliminates these issues and provides optimal performance.

**See**: [Gun Integration Guide](gun_integration.md) for detailed explanation of Gun's process ownership model and how it affects our architecture.

#### Recommended Solution: Client as GenServer
Convert Client from a struct-returning module to a GenServer that:
- Owns the Gun connection and receives all WebSocket messages
- Routes messages to appropriate handlers (integrated heartbeat, user callbacks)
- Maintains backward API compatibility
- Enables future message processing features
- **Coordinates reconnection** and re-establishes message routing after connection drops

#### Critical Coordination Requirement
The Client GenServer is essential for reconnection flow:
1. Client GenServer owns and monitors the Gun connection
2. On connection drop, Client triggers Reconnection module
3. Client receives new Gun process from reconnection
4. Client resumes integrated heartbeat handling seamlessly

The integrated approach eliminates coordination complexity while ensuring reliable heartbeat processing during reconnection scenarios.

#### File Structure
```
lib/websockex_new/
├── client.ex               # Enhanced with automatic message processing
├── heartbeat_handler.ex    # Dedicated heartbeat management process
└── examples/
    └── deribit_adapter.ex  # Enhanced integration with automatic heartbeat
```

#### Simplicity Progression Plan
1. **Start Simple**: Add dedicated heartbeat handler process
2. **Proven Pattern**: Use GenServer for reliable message processing (exception to no-GenServer rule for critical financial infrastructure)
3. **Add Complexity When Necessary**: This is a case where complexity is proven necessary by financial risk requirements

#### Abstraction Evaluation
**Concrete Use Cases** (≥3 required for abstraction):
1. Deribit test_request continuous processing
2. Deribit heartbeat during active trading sessions
3. Future platform heartbeat requirements (Binance, FTX, etc.)
4. Connection monitoring and automatic recovery

**Decision**: Create HeartbeatHandler abstraction - financial trading reliability requirements justify the complexity.

#### Production Requirements
- **Continuous Processing**: Heartbeats must be handled 24/7 during active connections
- **Sub-second Response**: test_request must be answered within API timeout (typically 1-5 seconds)
- **Fault Tolerance**: Heartbeat handler must restart on failure without losing connection
- **Monitoring**: Track heartbeat response times and failures for operational visibility
- **Graceful Degradation**: If heartbeat fails, connection should close cleanly to prevent phantom orders

#### Updated Architecture Decision (May 2025)
**CORE LIBRARY APPROACH**: After architectural review, heartbeat/ping-pong functionality will be implemented as a general-purpose feature in the core library with customizable handlers, rather than being Deribit-specific. This follows the WebSocket standard where ping/pong is fundamental protocol functionality used across many APIs.

#### Final Implementation Structure
```
lib/websockex_new/
├── client.ex               # Client GenServer with integrated heartbeat handling
├── client_supervisor.ex    # Optional supervisor for production deployments  
├── helpers/
│   └── deribit.ex          # Platform-specific heartbeat logic
└── examples/
    └── deribit_adapter.ex  # Configures heartbeat for Deribit platform
```

#### Core Library Justification
- **WebSocket Standard**: Ping/pong and heartbeat are fundamental WebSocket protocol features
- **Multi-Platform Need**: Binance, FTX, Kraken, and other exchanges require similar heartbeat handling
- **Platform Differences**: Each exchange uses different heartbeat patterns (Deribit: test_request, Binance: ping/pong, etc.)
- **Abstraction Value**: Integrated heartbeat handling can support any platform's heartbeat pattern via configuration

#### Implementation Strategy
1. **Client Integration**: Core heartbeat functionality built into Client GenServer for optimal performance
2. **Configurable Handlers**: Platform adapters configure heartbeat detection and response patterns
3. **DeribitAdapter Integration**: Configure Client with Deribit-specific test_request/public_test pattern
4. **Future Platform Support**: Other exchanges can easily configure their heartbeat patterns

#### Implementation Phases

**Phase 1: Client GenServer Refactor** ✅
- [x] **WNX0019a**: Convert Client module to GenServer while maintaining public API
- [x] **WNX0019b**: Move Gun connection ownership to Client process
- [x] **WNX0019c**: Implement message routing logic for different message types
- [x] **WNX0019d**: Ensure all existing tests pass with new architecture

**Phase 2: Heartbeat Integration** ✅
- [x] **WNX0019e**: Integrated heartbeat handling directly in Client GenServer
- [x] **WNX0019f**: Implemented Deribit test_request response and platform-specific patterns
- [x] **WNX0019g**: Added heartbeat tracking with MapSet and failure monitoring
- [x] **WNX0019h**: Created comprehensive tests with real Deribit API

**Phase 3: Production Hardening**
- [x] **WNX0019i**: Add supervision strategies for Client GenServer ✅
  - Created optional ClientSupervisor for dynamic supervision
  - Added child_spec to Client for direct supervision
  - Removed automatic application startup (library pattern)
  - Created comprehensive supervision documentation
  - Added usage examples showing three supervision patterns
- [x] **WNX0019j**: Implement graceful degradation on heartbeat failures ❌ REVERTED
  - Attempted implementation but it interfered with Deribit heartbeats
  - False positives due to timeout mechanism conflicting with actual responses
  - Decision: Keep heartbeat simple - let it fail on real issues only
- [x] **WNX0019k**: Conduct 24-hour stability test with continuous heartbeats ✅
  - Created comprehensive stability test suite for DeribitGenServerAdapter
  - 24-hour test with heartbeat monitoring, reconnection tracking, error counting
  - 1-hour development test for quick validation
  - Mix task for easy execution: `mix stability_test [--full]`
  - Generates detailed reports with success metrics
- [ ] **WNX0019l**: Document production deployment guidelines

#### WNX0020 Implementation Details
**Created Files**:
- `lib/websockex_new/examples/deribit_genserver_adapter.ex` - GenServer adapter with monitoring
- `lib/websockex_new/examples/adapter_supervisor.ex` - Supervisor for adapter GenServers
- `test/websockex_new/examples/deribit_genserver_adapter_test.exs` - Fault tolerance tests

**Key Features**:
1. **Process Monitoring**: Adapters monitor their Client GenServers
2. **Automatic Reconnection**: Detects Client death and reconnects
3. **State Restoration**: Preserves authentication status and subscriptions
4. **Supervision Tree**: AdapterSupervisor manages multiple adapters
5. **Fault Tolerance**: Handles Client crashes seamlessly

**Architecture Benefits**:
- Solves stale PID reference problem completely
- True OTP-compliant fault tolerance
- Seamless recovery from Client GenServer crashes
- Production-ready for financial trading systems

#### ExUnit and Integration Test Requirements
- Real API test against test.deribit.com verifying continuous heartbeat response
- Long-running test (minimum 10 minutes) to verify heartbeat stability
- Test heartbeat handler recovery after process failure
- Test connection termination when heartbeat responses fail
- Performance test: verify heartbeat response time under load

#### Error Handling Patterns
- **Client GenServer crash**: Supervisor restarts Client, re-establishes connection
- **test_request timeout**: Close connection immediately to prevent order issues
- **Connection loss during heartbeat**: Client triggers reconnection automatically
- **Response send failure**: Log error, attempt retry once, then close connection

#### Implementation Notes
- Heartbeat handling integrated directly into Client GenServer for simplicity
- Platform-specific logic delegated to helper modules (e.g., helpers/deribit.ex)
- Use `Process.monitor/1` to detect Gun connection failures
- Heartbeat timer managed within Client state
- Add telemetry events for heartbeat monitoring and alerting

#### Complexity Assessment
- **Previous**: Client was a simple struct, no message processing capability
- **Current**: Client as GenServer with integrated heartbeat handling
- **Added Complexity**: ~200 lines (Client GenServer conversion + heartbeat integration)
- **Justification**: Fundamental architecture requirement - Gun needs a process to send messages to
- **Benefits**: Enables all async message processing features, not just heartbeats
- **Maintains**: All existing public API compatibility + adds critical infrastructure

### WNX0021: Request/Response Correlation Manager
**Priority**: High  
**Effort**: Small  
**Dependencies**: None

#### Target Implementation
Track and correlate WebSocket request/response pairs for reliable order management:
- Request ID tracking with configurable timeouts
- Response matching to original requests
- Timeout handling for pending requests
- Simple correlation table using ETS

#### Real Trading Risk
Without request correlation, you can't reliably know if orders succeeded or failed. This leads to:
- Duplicate orders from retries
- Ghost positions from unknown order status
- Inability to reconcile exchange state

#### File Structure
```
lib/websockex_new/
├── request_tracker.ex      # Simple request/response correlation
└── client.ex               # Enhanced with correlation support
```

#### Simplicity Progression Plan
1. **Start Simple**: ETS table mapping request_id -> {request, timeout}
2. **Proven Pattern**: Return {:error, :timeout} after configurable delay
3. **Add When Needed**: Only add features based on real trading issues

#### Subtasks
- [ ] **WNX0021a**: Create request_tracker.ex with ETS-based correlation table
- [ ] **WNX0021b**: Add track_request/3 and match_response/2 functions
- [ ] **WNX0021c**: Implement timeout detection with Process.send_after
- [ ] **WNX0021d**: Integrate with Client.send_message for automatic tracking
- [ ] **WNX0021e**: Test with real Deribit order placement/cancellation

#### Implementation Notes
- ~50 lines total implementation
- Use ETS for O(1) lookup performance
- Leverage existing JSON-RPC ID field
- No complex abstractions, just simple mapping

### WNX0022: Basic Rate Limiter
**Priority**: High  
**Effort**: Small  
**Dependencies**: None

#### Target Implementation
Prevent API rate limit violations with simple token bucket:
- Configurable rate limits per connection
- Token bucket algorithm implementation
- Automatic request queueing when limit reached
- Simple, proven approach used across financial APIs

#### Real Trading Risk
Hitting rate limits causes:
- Temporary API bans (missed trading opportunities)
- Order rejections during critical moments
- Complete system lockout in worst case

#### File Structure
```
lib/websockex_new/
├── rate_limiter.ex         # Token bucket rate limiting
└── client.ex               # Enhanced with rate limit checks
```

#### Simplicity Progression Plan
1. **Start Simple**: Basic token bucket with fixed refill rate
2. **Proven Pattern**: Standard algorithm used by exchanges
3. **Add When Needed**: Burst handling only if actually hitting limits

#### Subtasks
- [ ] **WNX0022a**: Create rate_limiter.ex with token bucket logic
- [ ] **WNX0022b**: Add consume_token/2 and refill logic
- [ ] **WNX0022c**: Integrate with Client.send_message
- [ ] **WNX0022d**: Add configurable limits to Config struct
- [ ] **WNX0022e**: Test against Deribit rate limits with burst traffic

#### Implementation Notes
- ~30 lines total implementation
- Use Process.send_after for token refill
- Queue requests when tokens exhausted
- Return {:error, :rate_limited} when queue full

### WNX0023: JSON-RPC 2.0 API Builder ✅
**Status**: COMPLETED  
**Priority**: Medium (Nice to have)  
**Effort**: Medium  
**Dependencies**: None (made general-purpose)

#### Completed Implementation
Created a general-purpose JSON-RPC 2.0 API builder as a core module in WebsockexNew:
- ✅ Created `lib/websockex_new/json_rpc.ex` as 8th core module
- ✅ Implements `build_request/2` for JSON-RPC request generation
- ✅ Implements `match_response/1` for response parsing
- ✅ Created `defrpc` macro for API method generation
- ✅ Updated Deribit adapter with 29 API methods using the macro
- ✅ Added comprehensive test coverage
- ✅ Configured `.formatter.exs` for parentheses-free macro syntax
- ✅ Tested macro-generated methods with test.deribit.com API
- ✅ Documented macro usage patterns for market making workflows

#### Design Philosophy
Originally planned as Deribit-specific, this was implemented as a general-purpose module following the principle of building reusable components. Any WebSocket API using JSON-RPC 2.0 can now leverage this functionality.

#### Core Features
```elixir
# Simple API method definition
use WebsockexNew.JsonRpc
defrpc :get_order_book, "public/get_order_book", doc: "Get order book"

# Generates a function that returns:
{:ok, %{
  "jsonrpc" => "2.0",
  "id" => <unique_id>,
  "method" => "public/get_order_book",
  "params" => params
}}
```

#### Deribit Integration
The Deribit adapter now includes 29 commonly used methods:
- **Authentication & Session**: auth, test, set_heartbeat, disable_heartbeat
- **Market Data**: get_instruments, get_order_book, ticker, etc.
- **Trading**: buy, sell, cancel, edit, get_open_orders, etc.
- **Account & Wallet**: get_account_summary, get_positions, etc.
- **Session Management**: enable/disable_cancel_on_disconnect

#### Files Modified/Created
- `lib/websockex_new/json_rpc.ex` - Core JSON-RPC functionality
- `lib/websockex_new/examples/deribit_adapter.ex` - Updated to use macros
- `test/websockex_new/json_rpc_test.exs` - Comprehensive tests
- `test/websockex_new/examples/deribit_json_rpc_test.exs` - Integration tests
- `docs/deribit/json_rpc_usage.md` - Usage patterns and workflows
- `.formatter.exs` - Updated for parentheses-free macro syntax

#### Completion Notes
- Implemented as 8th module (at project limit)
- Follows simplicity principles: 5 functions, each under 15 lines
- All 101 tests passing
- Ready for use by any JSON-RPC 2.0 WebSocket API

---

---

## Target Architecture

### Module Structure Evolution

#### Foundation Modules (8 core - COMPLETED ✅)
```
lib/websockex_new/
├── client.ex              # Main client interface (5 functions) ✅
├── config.ex              # Configuration struct and validation ✅
├── frame.ex               # WebSocket frame encoding/decoding ✅
├── connection_registry.ex # ETS-based connection tracking ✅
├── reconnection.ex        # Simple retry logic ✅
├── message_handler.ex     # Message parsing and routing ✅
├── error_handler.ex       # Error recovery patterns ✅
├── json_rpc.ex            # JSON-RPC 2.0 API builder ✅
```

#### Enhancement Modules (financial infrastructure - IN PROGRESS)
```
├── client.ex              # Enhanced with integrated heartbeat handling ✅
├── client_supervisor.ex   # Optional dynamic supervisor for clients ✅
├── helpers/               # Platform-specific helper modules ✅
│   ├── deribit.ex         # Deribit heartbeat handling ✅
│   └── binance.ex         # Future: Binance ping/pong handling
├── correlation_manager.ex # Request/response correlation 🚧
├── rate_limiter.ex        # API rate limit management 🚧
└── examples/
    ├── deribit_adapter.ex # Platform-specific integration ✅
    ├── supervised_client.ex # Supervision usage examples ✅
    └── usage_patterns.ex  # Three supervision patterns ✅
```

### Public API (5 functions only)
```elixir
# Core client interface - everything users need
WebsockexNew.Client.connect(url, opts)
WebsockexNew.Client.send(client, message)
WebsockexNew.Client.close(client)
WebsockexNew.Client.subscribe(client, channels)
WebsockexNew.Client.get_state(client)
```


## Success Metrics

### Foundation Goals - ACHIEVED ✅
- **Foundation modules**: 8 core modules ✅
- **Lines of code**: ~900 lines (foundation) ✅
- **Public API functions**: 5 functions ✅
- **Configuration options**: 6 essential options ✅
- **Behaviors**: 0 behaviors ✅
- **GenServers**: 0 GenServers in foundation ✅
- **Test coverage**: 121 tests, 100% real API testing ✅

### Enhancement Phase Goals
- **Total modules**: Foundation (8) + Critical Infrastructure (3-4)
- **Module quality**: Each new module maintains strict constraints
- **Real-world validation**: Each module added only when proven necessary
- **Production readiness**: Financial-grade reliability for trading systems

### Qualitative Goals
- **Learning curve**: New developer productive in under 1 hour
- **Debugging**: Any issue traceable through maximum 2 modules
- **Feature addition**: New functionality requires touching 1 module
- **Code comprehension**: Entire codebase understandable in 30 minutes
- **Production confidence**: All tests run against real WebSocket endpoints

## Implementation Strategy

### Development Approach
1. **Build incrementally** - Each task produces working, tested code
2. **Real API first** - Every feature tested against test.deribit.com
3. **Document as you go** - Write docs with each module

### Quality Gates
- **Each module**: Maximum 5 functions, 15 lines per function
- **Each function**: Single responsibility, clear purpose
- **Each test**: Uses real API endpoints only
- **Each commit**: Maintains working system end-to-end

### Timeline
- **Foundation Complete**: 8 core modules with connection management, Deribit integration, and JSON-RPC support ✅
- **Current phase**: Enhancement with critical financial infrastructure (WNX0019-0021)
  - Integrated Heartbeat: Automatic heartbeat processing built into Client for optimal performance
  - Request Correlation: Track request/response pairs for reliable order management  
  - Rate Limiting: Prevent API violations with token bucket algorithm
- **Architecture Evolution**: Expanding beyond 8 modules for production-grade financial systems

## Notes

**Key philosophy**: Build the minimum system that solves real problems. Start simple, add complexity only when necessary based on real data.