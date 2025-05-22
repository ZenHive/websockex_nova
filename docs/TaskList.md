# WebsockexNew Complete Rewrite Tasks

## Current Progress Status
**Last Updated**: 2025-05-23  
**Phase**: Enhancement Tasks (WNX0019-WNX0020)  
**Foundation**: Complete ✅ (All Phase 1-4 tasks archived)

### 📊 Current Architecture Status
- **Foundation Complete**: All 8 core modules implemented and tested ✅
- **Public API**: 5 core functions fully functional ✅
- **Test Coverage**: 93 tests, 100% real API testing ✅
- **Platform Integration**: Deribit adapter with real API testing ✅
- **Migration**: Clean codebase, 26,375 legacy lines removed ✅

### ✅ Completed Tasks Archive
**All Phase 1-4 foundation tasks (WNX0010-WNX0018, WNX0021-WNX0022) have been moved to:**
📁 `docs/archive/completed_tasks.md`

**Foundation Summary**:
- 8 core modules: Client, Config, Frame, ConnectionRegistry, Reconnection, MessageHandler, ErrorHandler, DeribitAdapter
- 5 public API functions: connect, send, close, subscribe, get_state
- 93 tests passing with 100% real API testing
- Complete Deribit integration with authentication and subscriptions
- 90% code reduction (56 → 8 modules, 10,000+ → 900 lines)

---

## Project Goal
Completely rewrite WebsockexNew as a simple, maintainable WebSocket client that delivers core functionality with minimal complexity. Build from scratch in `lib/websockex_new/` using Gun as the transport layer, following strict simplicity principles from day one.

## Why Rewrite Instead of Refactor
- **Current state**: 56 modules, 9 behaviors, 1,737-line connection wrapper
- **Refactor effort**: 5-7 weeks of complex surgery with backward compatibility constraints
- **Rewrite effort**: 2-3 weeks building only what's needed
- **Clean slate**: No legacy complexity, over-abstractions, or technical debt
- **Simplicity first**: Implement minimal viable solution, add complexity only when proven necessary

## Development Strategy
- **New namespace**: Build in `lib/websockex_new/` to avoid conflicts
- **Parallel development**: Keep existing system running while rewriting
- **Final migration**: Rename `websockex_new` → `websockex_new` when complete
- **Clean cutover**: Replace old system entirely, no hybrid approach

## Core Architecture Principles
- **Maximum 8 modules** in main library
- **Maximum 5 functions per module**
- **Maximum 15 lines per function**
- **No behaviors** unless ≥3 concrete implementations exist
- **Direct Gun API usage** - no wrapper layers
- **Functions over processes** - GenServers only when essential
- **Real API testing only** - zero mocks

---

## Active Enhancement Tasks

### WNX0019: HeartbeatManager Implementation (Critical Financial Infrastructure)
**Priority**: Critical  
**Effort**: Medium  
**Dependencies**: None

**Status**: Planning complete ✅ - See `docs/HeartbeatManager_Architecture.md` for comprehensive design
**Priority**: High (Deferred until after WNX0022)  
**Effort**: Medium  
**Dependencies**: WNX0022 (Migration), then enhanced from current WNX0016

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

### WNX0020: Deribit JSON-RPC 2.0 Macro System
**Priority**: High (Deferred until after WNX0022)  
**Effort**: Medium  
**Dependencies**: WNX0022 (Migration), then WNX0019

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

## Phase 4: Migration and Cleanup

### WNX0021: Documentation for New System
**Priority**: Medium - **COMPLETED** ✅  
**Effort**: Small  
**Dependencies**: WNX0022 (Migration), then enhanced from existing docs

#### Target Implementation
Comprehensive documentation for the WebsockexNew system:
- Complete architecture documentation reflecting 8-module simplified design
- Full API reference for all core modules with examples and usage patterns
- Step-by-step adapter development guide using DeribitAdapter as reference
- Integration testing patterns with real endpoint testing philosophy
- Updated README with accurate system overview

#### Subtasks
- [x] **WNX0021a**: Create accurate architecture documentation for WebsockexNew system
- [x] **WNX0021b**: Document all core modules and their APIs with complete function signatures
- [x] **WNX0021c**: Create comprehensive adapter development guide with real examples
- [x] **WNX0021d**: Document integration testing patterns and best practices
- [x] **WNX0021e**: Update README with accurate system overview removing outdated references
- [x] **WNX0021f**: Prepare API documentation structure for generation

**Status**: ✅ COMPLETED - Complete documentation suite with architecture overview, API reference, adapter guide, testing patterns, and updated README reflecting the actual WebsockexNew implementation

### WNX0022: System Migration and Cleanup
**Priority**: Critical - **COMPLETED** ✅  
**Effort**: Small (simplified approach)  
**Dependencies**: None (websockex_new system is complete and tested)

#### Target Implementation
**SIMPLIFIED APPROACH**: Keep `WebsockexNew` namespace and use project rename tool for metadata only

#### Strategy Benefits
- **Zero module renaming risk** - all working code stays exactly as-is
- **90% less complexity** - no mass find/replace operations across codebase
- **Safe project updates** - use proven `rename` tool for mix.exs/README/docs
- **"New" becomes permanent identity** - semantically appropriate for modern implementation

#### File Management Strategy

**Files to KEEP (no renaming needed):**
```
lib/websockex_new/              → Keep as-is (WebsockexNew namespace permanent)
test/websockex_new/             → Keep as-is (no module changes needed)
test/support/                   → Keep existing test infrastructure
docs/                           → Keep updated documentation
LICENSE, .formatter.exs, .gitignore → Keep unchanged
```

**Files to DELETE (old WebsockexNew system):**
```
lib/websockex_new/             → DELETE ENTIRE DIRECTORY
├── application.ex              → DELETE (56 modules total)
├── behaviors/                  → DELETE (9 behavior modules)
├── client.ex                   → DELETE (complex client)
├── defaults/                   → DELETE (7 default implementations)
├── examples/                   → DELETE (Deribit adapter)
├── gun/                        → DELETE (Gun transport layer - 15 modules)
├── helpers/                    → DELETE (state helpers)
├── message/                    → DELETE (message handling)
├── telemetry/                  → DELETE (telemetry system)
└── transport/                  → DELETE (transport abstraction)

test/websockex_new/            → DELETE ENTIRE DIRECTORY
├── auth/                       → DELETE
├── behaviors/                  → DELETE (behavior tests)
├── client_conn_*.exs          → DELETE
├── client_macro_test.exs      → DELETE
├── client_test.exs            → DELETE
├── connection_registry_test.exs → DELETE
├── defaults/                   → DELETE (default handler tests)
├── examples/                   → DELETE (adapter tests)
├── gun/                        → DELETE (Gun transport tests)
├── handler_invoker_test.exs   → DELETE
├── helpers/                    → DELETE
├── message/                    → DELETE
├── telemetry/                  → DELETE
├── transport/                  → DELETE
└── transport_test.exs         → DELETE
```

**Test Files to KEEP:**
```
test/integration/               → Keep real API integration tests  
test/support/mock_websock_*     → Keep existing mock infrastructure (used by websockex_new)
test/support/certificate_helper.ex → Keep certificate helpers
test/support/gun_monitor.ex     → Keep if used by new system
test/test_helper.exs           → Keep and update for new system
```

**Important**: WebsockexNew system already uses some of the `test/support/` infrastructure, so this cleanup preserves that working relationship.

#### Simplified Migration Steps
- [x] **WNX0022a**: Create backup branch with current state
- [x] **WNX0022b**: Delete entire `lib/websockex_nova/` directory (52 modules) 
- [x] **WNX0022c**: Delete entire `test/websockex_nova/` directory (41 test files)
- [x] **WNX0022d**: Install and run `rename` tool to update project metadata (mix.exs, README.md)
- [x] **WNX0022e**: Update mix.exs application configuration (remove WebsockexNova.Application)
- [x] **WNX0022f**: Clean up incompatible test support files
- [x] **WNX0022g**: Verify all tests pass with cleaned structure (93 tests passing)

#### Rename Tool Usage
```bash
# Install rename tool
mix archive.install hex rename

# Rename project from websockex_new to websockex_new
mix rename websockex_new websockex_new
```

**Result**: Clean codebase with `WebsockexNew` namespace as the permanent, modern implementation.

---

## Target Architecture

### Final Module Structure (8 modules - COMPLETED ✅)
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

### Development Workflow
1. **Phase 1-3**: Build complete new system in `lib/websockex_new/` ✅ COMPLETED
2. **Test extensively**: Validate against real APIs throughout development ✅ COMPLETED
3. **Phase 4**: Clean cutover - remove old system, keep `WebsockexNew` namespace ✅ COMPLETED
4. **Project rename**: Use rename tool for project metadata only ✅ COMPLETED

## Success Metrics

### Quantitative Goals - ACHIEVED ✅
- **Total modules**: 8 modules ✅ (was 56 in legacy system)
- **Lines of code**: ~900 lines ✅ (was ~10,000+ in legacy system)
- **Public API functions**: 5 functions ✅ (was dozens in legacy system)
- **Configuration options**: 6 essential options ✅ (was 20+ in legacy system)
- **Behaviors**: 0 behaviors ✅ (was 9 behaviors in legacy system)
- **GenServers**: 0 GenServers ✅ (was multiple in legacy system)
- **Test coverage**: 93 tests, 100% real API testing ✅

### Qualitative Goals
- **Learning curve**: New developer productive in under 1 hour
- **Debugging**: Any issue traceable through maximum 2 modules
- **Feature addition**: New functionality requires touching 1 module
- **Code comprehension**: Entire codebase understandable in 30 minutes
- **Production confidence**: All tests run against real WebSocket endpoints

## Implementation Strategy

### Development Approach
1. **Parallel development** - Build in `lib/websockex_new/` without disrupting current system ✅ COMPLETED
2. **Build incrementally** - Each task produces working, tested code ✅ COMPLETED
3. **Real API first** - Every feature tested against test.deribit.com ✅ COMPLETED
4. **Document as you go** - Write docs with each module ✅ COMPLETED
5. **Clean migration** - Remove old system, keep new namespace permanent ✅ COMPLETED

### Quality Gates
- **Each module**: Maximum 5 functions, 15 lines per function
- **Each function**: Single responsibility, clear purpose
- **Each test**: Uses real API endpoints only
- **Each commit**: Maintains working system end-to-end

### Timeline
- **Week 1**: Core client (WNX0010-0012) - Basic connect/send/close ✅ COMPLETED
- **Week 2**: Connection management (WNX0013-0015) - Reconnection and messaging ✅ COMPLETED
- **Week 3**: Integration (WNX0016-0017) - Deribit adapter and error handling ✅ COMPLETED
- **Migration**: System cleanup (WNX0022) - Remove legacy code, clean foundation ✅ COMPLETED
- **Next phase**: Enhancement features (WNX0018-0021) - Testing infrastructure, bootstrap sequence, JSON-RPC macros, documentation

## Migration Benefits

### Advantages of lib/websockex_new/ Approach
- **No disruption**: Existing system continues working
- **Easy comparison**: Can compare old vs new implementations
- **Safe rollback**: Simple to revert if rewrite fails
- **Incremental testing**: Can test new system alongside old
- **Clean history**: Clear commit history showing rewrite progress

### Risk Mitigation
- **Early real API testing** - Validate approach with actual Deribit integration
- **Incremental delivery** - Each week produces usable system
- **Simple rollback** - Keep old system available during development
- **Performance validation** - Ensure new system meets performance requirements

## Notes

This rewrite prioritizes **shipping a working system quickly** over architectural perfection. The development in `lib/websockex_new/` allowed for safe, parallel development while maintaining the existing system.

**Key philosophy**: Build the minimum system that solves real problems, then clean cutover. The namespace approach provided safety during development, and `WebsockexNew` becomes the permanent, modern identity.