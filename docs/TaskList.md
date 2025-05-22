# WebsockexNew Complete Rewrite Tasks

## Current Progress Status
**Last Updated**: 2025-05-23  
**Phase**: Critical Financial Infrastructure (WNX0019-WNX0021)  
**Foundation**: Complete ✅ (All Phase 1-4 tasks archived)

### 📊 Current Architecture Status
- **Foundation Complete**: All 8 core modules implemented and tested ✅
- **Public API**: 5 core functions fully functional ✅
- **Test Coverage**: 93 tests, 100% real API testing ✅
- **Platform Integration**: Deribit adapter with real API testing ✅

### ✅ Completed Tasks Archive
**All completed foundation and migration tasks have been moved to:**
📁 `docs/archive/completed_tasks.md` - Foundation tasks (WNX0010-WNX0018)
📁 `docs/archive/completed_migration.md` - Migration process and tasks (WNX0023-WNX0024)

**Foundation Summary**:
- 8 core modules: Client, Config, Frame, ConnectionRegistry, Reconnection, MessageHandler, ErrorHandler, DeribitAdapter
- 5 public API functions: connect, send, close, subscribe, get_state
- 93 tests passing with 100% real API testing
- Complete Deribit integration with authentication and subscriptions

---

## Project Goal
WebsockexNew is a simple, maintainable WebSocket client that delivers core functionality with minimal complexity. Built using Gun as the transport layer, following strict simplicity principles.

## Core Architecture Principles
- **Maximum 8 modules** in main library
- **Maximum 5 functions per module**
- **Maximum 15 lines per function**
- **No behaviors** unless ≥3 concrete implementations exist
- **Direct Gun API usage** - no wrapper layers
- **Functions over processes** - GenServers only when essential
- **Real API testing only** - zero mocks

---

## Active Critical Financial Infrastructure Tasks

### WNX0019: HeartbeatManager Implementation
**Priority**: Critical  
**Effort**: Medium  
**Dependencies**: None

**Status**: Planning complete ✅ - See `docs/HeartbeatManager_Architecture.md` for comprehensive design
**Priority**: High (Deferred until after WNX0022)  
**Effort**: Medium  
**Dependencies**: None

#### Target Implementation
**PRODUCTION-READY APPROACH**: Implement automatic heartbeat processing during the entire connection lifecycle, not just bootstrap. Financial trading connections require continuous, automatic heartbeat handling to prevent order cancellation due to connection monitoring failures.

#### Technical Requirements (CRITICAL - FINANCIAL TRADING)
**Heartbeat Sequence**: When heartbeats have been set up, the API server will send heartbeat messages and test_request messages. Your software should respond to test_request messages by sending a `/api/v2/public/test` request. If your software fails to do so, the API server will immediately close the connection. If your account is configured to cancel on disconnect, any orders opened over the connection will be cancelled.

**Production Risk**: A simple loop is insufficient for production financial trading. Heartbeat failures can cause immediate order cancellation, resulting in financial losses.

#### Current Issue
The DeribitAdapter.handle_message/1 correctly detects test_request and returns `{:response, json_response}`, but this response is not automatically sent back. The system requires a separate process or continuous message handling to ensure heartbeats are processed reliably throughout the connection lifecycle.

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

#### Revised File Structure
```
lib/websockex_new/
├── client.ex               # Enhanced with HeartbeatManager integration
├── heartbeat_manager.ex    # General-purpose heartbeat/ping-pong infrastructure
└── examples/
    └── deribit_adapter.ex  # Configures HeartbeatManager with Deribit-specific patterns
```

#### Core Library Justification
- **WebSocket Standard**: Ping/pong and heartbeat are fundamental WebSocket protocol features
- **Multi-Platform Need**: Binance, FTX, Kraken, and other exchanges require similar heartbeat handling
- **Platform Differences**: Each exchange uses different heartbeat patterns (Deribit: test_request, Binance: ping/pong, etc.)
- **Abstraction Value**: General HeartbeatManager can handle any platform's heartbeat pattern via configuration

#### Implementation Strategy
1. **HeartbeatManager**: Core library module handling continuous message processing
2. **Configurable Handlers**: Platform adapters configure heartbeat detection and response patterns
3. **DeribitAdapter Integration**: Configure HeartbeatManager with Deribit-specific test_request/public_test pattern
4. **Future Platform Support**: Other exchanges can easily configure their heartbeat patterns

#### Subtasks (Revised for Core Library Approach)
- [ ] **WNX0019a**: Create general-purpose HeartbeatManager in core library for continuous message processing
- [ ] **WNX0019b**: Integrate HeartbeatManager with Client.connect for automatic startup
- [ ] **WNX0019c**: Add configurable heartbeat detection and response pattern system
- [ ] **WNX0019d**: Configure DeribitAdapter to use HeartbeatManager with test_request/public_test pattern
- [ ] **WNX0019e**: Add heartbeat response time monitoring and failure detection
- [ ] **WNX0019f**: Implement graceful connection termination on heartbeat failure
- [ ] **WNX0019g**: Add supervision strategy for HeartbeatManager process recovery
- [ ] **WNX0019h**: Test continuous heartbeat processing with test.deribit.com (24-hour stability test)

#### ExUnit and Integration Test Requirements
- Real API test against test.deribit.com verifying continuous heartbeat response
- Long-running test (minimum 10 minutes) to verify heartbeat stability
- Test heartbeat handler recovery after process failure
- Test connection termination when heartbeat responses fail
- Performance test: verify heartbeat response time under load

#### Error Handling Patterns
- **HeartbeatHandler crash**: Restart handler, maintain connection if possible
- **test_request timeout**: Close connection immediately to prevent order issues
- **Connection loss during heartbeat**: Trigger reconnection with new heartbeat handler
- **Response send failure**: Log error, attempt retry once, then close connection

#### Implementation Notes
- Create `HeartbeatHandler` GenServer that continuously processes Gun messages
- Link HeartbeatHandler to Client process for coordinated lifecycle management
- Use `Process.monitor/1` to detect heartbeat handler failures
- Implement heartbeat response caching to handle high-frequency test_requests
- Add telemetry events for heartbeat monitoring and alerting

#### Complexity Assessment
- **Current**: DeribitAdapter detects heartbeats but requires manual processing
- **Target**: Dedicated process for continuous, automatic heartbeat handling
- **Added Complexity**: ~150 lines (HeartbeatHandler GenServer + Client integration)
- **Justification**: Financial trading reliability requirements override simplicity preference
- **Maintains**: All existing DeribitAdapter functionality + production-grade reliability

### WNX0020: Request/Response Correlation Manager
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
- [ ] **WNX0020a**: Create request_tracker.ex with ETS-based correlation table
- [ ] **WNX0020b**: Add track_request/3 and match_response/2 functions
- [ ] **WNX0020c**: Implement timeout detection with Process.send_after
- [ ] **WNX0020d**: Integrate with Client.send_message for automatic tracking
- [ ] **WNX0020e**: Test with real Deribit order placement/cancellation

#### Implementation Notes
- ~50 lines total implementation
- Use ETS for O(1) lookup performance
- Leverage existing JSON-RPC ID field
- No complex abstractions, just simple mapping

### WNX0021: Basic Rate Limiter
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
- [ ] **WNX0021a**: Create rate_limiter.ex with token bucket logic
- [ ] **WNX0021b**: Add consume_token/2 and refill logic
- [ ] **WNX0021c**: Integrate with Client.send_message
- [ ] **WNX0021d**: Add configurable limits to Config struct
- [ ] **WNX0021e**: Test against Deribit rate limits with burst traffic

#### Implementation Notes
- ~30 lines total implementation
- Use Process.send_after for token refill
- Queue requests when tokens exhausted
- Return {:error, :rate_limited} when queue full

### WNX0022: Deribit JSON-RPC 2.0 Macro System
**Priority**: Medium (Nice to have)  
**Effort**: Medium  
**Dependencies**: WNX0019, WNX0020, WNX0021

#### Target Implementation
Auto-generate JSON-RPC 2.0 requests for market making and options trading operations:
- Macro for defining Deribit API methods with automatic JSON-RPC structure
- Request ID management and correlation
- Support for public and private API endpoints
- Market data, trading, and risk management method coverage

#### Use Case Context
This library targets market makers and option sellers on Deribit requiring high-frequency API calls:
- **Market Data**: `get_instruments`, `subscribe`, `get_order_book`, `get_last_trades_by_instrument`
- **Trading**: `buy`, `sell`, `edit`, `cancel`, `get_open_orders`, `get_positions` 
- **Risk Management**: `get_portfolio_margins`, `get_user_trades_by_instrument`, `get_settlements_by_instrument`
- **Infrastructure**: `auth`, `set_heartbeat`, `enable_cancel_on_disconnect`

#### File Structure
```
lib/websockex_new/examples/
├── deribit_adapter.ex      # Enhanced with JSON-RPC macro usage
├── deribit_bootstrap.ex    # Bootstrap sequence utilities
└── deribit_rpc_macro.ex    # JSON-RPC 2.0 method generation macro
```

#### Subtasks
- [ ] **WNX0020a**: Create `deribit_rpc_macro.ex` with `defrpc` macro definition
- [ ] **WNX0020b**: Implement automatic JSON-RPC 2.0 structure generation (`jsonrpc`, `id`, `method`, `params`)
- [ ] **WNX0020c**: Add request ID management and correlation tracking
- [ ] **WNX0020d**: Define market data methods (`get_instruments`, `subscribe`, `get_order_book`)
- [ ] **WNX0020e**: Define trading methods (`buy`, `sell`, `edit`, `cancel`, `get_open_orders`)
- [ ] **WNX0020f**: Define risk management methods (`get_portfolio_margins`, `get_positions`)
- [ ] **WNX0020g**: Add infrastructure methods (`set_heartbeat`, `enable_cancel_on_disconnect`)
- [ ] **WNX0020h**: Test macro-generated methods with test.deribit.com API
- [ ] **WNX0020i**: Document macro usage patterns for market making workflows

---

---

## Target Architecture

### Module Structure (8 modules - COMPLETED ✅)
```
lib/websockex_new/
├── client.ex              # Main client interface (5 functions) ✅
├── config.ex              # Configuration struct and validation ✅
├── frame.ex               # WebSocket frame encoding/decoding ✅
├── connection_registry.ex # ETS-based connection tracking ✅
├── reconnection.ex        # Simple retry logic ✅
├── message_handler.ex     # Message parsing and routing ✅
├── error_handler.ex       # Error recovery patterns ✅
└── examples/
    └── deribit_adapter.ex # Platform-specific integration ✅
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

### Quantitative Goals - ACHIEVED ✅
- **Total modules**: 8 modules ✅
- **Lines of code**: ~900 lines ✅
- **Public API functions**: 5 functions ✅
- **Configuration options**: 6 essential options ✅
- **Behaviors**: 0 behaviors ✅
- **GenServers**: 0 GenServers ✅
- **Test coverage**: 93 tests, 100% real API testing ✅

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
- **Foundation Complete**: Core modules, connection management, and Deribit integration ✅
- **Current phase**: Critical financial infrastructure (WNX0019-0021) - HeartbeatManager, Request Correlation, Rate Limiting
- **Next phase**: Nice-to-have enhancements (WNX0022) - JSON-RPC macro system

## Notes

**Key philosophy**: Build the minimum system that solves real problems. Start simple, add complexity only when necessary based on real data.