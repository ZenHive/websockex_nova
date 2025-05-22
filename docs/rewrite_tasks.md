# WebsockexNova Complete Rewrite Tasks

## Current Progress Status
**Last Updated**: 2025-05-22  
**Phase**: 4 of 4 (Migration and Cleanup) - **IN PROGRESS**  
**Next**: WNX0022 (System Migration and Rename) → **PRIORITY CHANGE**

### ✅ Completed Tasks (WNX0010-WNX0017)
- **WNX0010**: Minimal WebSocket Client - Full Gun-based client with connect/send/close
- **WNX0011**: Basic Configuration System - Config struct with validation and defaults  
- **WNX0012**: Frame Handling Utilities - WebSocket frame encoding/decoding with Gun format support
- **WNX0013**: Connection Registry - ETS-based connection tracking with monitor cleanup
- **WNX0014**: Reconnection Logic - Exponential backoff with subscription state preservation
- **WNX0015**: Message Handler - WebSocket upgrade support and automatic ping/pong handling
- **WNX0016**: Deribit Adapter - Complete platform integration with auth, subscriptions, and heartbeat handling
- **WNX0017**: Error Handling System - Comprehensive error categorization and recovery with raw error passing

### 📊 Current Architecture Status
- **Modules created**: 8/8 target modules (100% complete)
- **Lines of code**: ~900/1000 target (90% utilization)
- **Test coverage**: 106 tests, 0 failures - all real API tested
- **Public API**: 5 core functions implemented in WebsockexNew.Client
- **Platform Integration**: Deribit adapter fully functional with real API testing
- **Error Handling**: Complete error categorization system with recovery patterns

### 🎯 Priority Changed: Migration First
**WNX0022**: System Migration and Rename - **NOW PRIORITY #1**
- Eliminates confusion between websockex_new (7 modules) and WebsockexNova (56 modules)
- Cleaner development environment for implementing remaining features
- Safer implementation of WNX0018-WNX0021 on clean foundation
- websockex_new foundation is proven with 93 passing tests

---

## Project Goal
Completely rewrite WebsockexNova as a simple, maintainable WebSocket client that delivers core functionality with minimal complexity. Build from scratch in `lib/websockex_new/` using Gun as the transport layer, following strict simplicity principles from day one.

## Why Rewrite Instead of Refactor
- **Current state**: 56 modules, 9 behaviors, 1,737-line connection wrapper
- **Refactor effort**: 5-7 weeks of complex surgery with backward compatibility constraints
- **Rewrite effort**: 2-3 weeks building only what's needed
- **Clean slate**: No legacy complexity, over-abstractions, or technical debt
- **Simplicity first**: Implement minimal viable solution, add complexity only when proven necessary

## Development Strategy
- **New namespace**: Build in `lib/websockex_new/` to avoid conflicts
- **Parallel development**: Keep existing system running while rewriting
- **Final migration**: Rename `websockex_new` → `websockex_nova` when complete
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

## Phase 1: Core WebSocket Client (Week 1)

### WNX0010: Minimal WebSocket Client Module
**Priority**: Critical  
**Effort**: Medium  
**Dependencies**: None

#### Target Implementation
Single `WebsockexNew.Client` module with 5 essential functions:
- `connect(url, opts \\ [])` - Establish WebSocket connection
- `send(client, message)` - Send text/binary message  
- `close(client)` - Close connection gracefully
- `subscribe(client, channels)` - Subscribe to channels/topics
- `get_state(client)` - Get current connection state

#### File Structure
```
lib/websockex_new/
└── client.ex              # Main client interface
```

#### Subtasks
- [x] **WNX0010a**: Create `lib/websockex_new/` directory structure
- [x] **WNX0010b**: Implement Gun-based connection establishment in `client.ex`
- [x] **WNX0010c**: Add message sending with basic frame encoding
- [x] **WNX0010d**: Implement graceful connection closing
- [x] **WNX0010e**: Add connection state tracking (connected/disconnected/connecting)
- [x] **WNX0010f**: Test against test.deribit.com WebSocket endpoint

**Status**: ✅ COMPLETED - Full WebSocket client with Gun transport layer

### WNX0011: Basic Configuration System
**Priority**: High  
**Effort**: Small  
**Dependencies**: WNX0010

#### Target Implementation
Simple configuration struct with 6 essential fields:
```elixir
%WebsockexNew.Config{
  url: "wss://...",
  headers: [],
  timeout: 5000,
  retry_count: 3,
  retry_delay: 1000,
  heartbeat_interval: 30000
}
```

#### File Structure
```
lib/websockex_new/
├── client.ex
└── config.ex              # Configuration struct and validation
```

#### Subtasks
- [x] **WNX0011a**: Define configuration struct in `config.ex`
- [x] **WNX0011b**: Add basic validation for required fields
- [x] **WNX0011c**: Implement configuration merging (opts override defaults)
- [x] **WNX0011d**: Test configuration validation with real endpoints

**Status**: ✅ COMPLETED - Configuration system with validation and defaults

### WNX0012: Frame Handling Utilities
**Priority**: High  
**Effort**: Small  
**Dependencies**: WNX0010

#### Target Implementation
Single `WebsockexNew.Frame` module with 5 functions:
- `encode_text(data)` - Encode text frame
- `encode_binary(data)` - Encode binary frame
- `decode_frame(frame)` - Decode incoming frame
- `ping()` - Create ping frame
- `pong(payload)` - Create pong frame

#### File Structure
```
lib/websockex_new/
├── client.ex
├── config.ex
└── frame.ex               # WebSocket frame encoding/decoding
```

#### Subtasks
- [x] **WNX0012a**: Implement basic text/binary frame encoding in `frame.ex`
- [x] **WNX0012b**: Add frame decoding for incoming messages
- [x] **WNX0012c**: Implement ping/pong frame handling
- [x] **WNX0012d**: Test frame encoding/decoding with real WebSocket data
- [x] **WNX0012e**: Handle frame parsing errors gracefully

**Status**: ✅ COMPLETED - Frame handling with Gun WebSocket format support

---

## Phase 2: Connection Management (Week 2)

### WNX0013: Connection Registry
**Priority**: High  
**Effort**: Small  
**Dependencies**: WNX0010

#### Target Implementation
Simple ETS-based connection tracking without GenServer:
- Store connection_id → {gun_pid, monitor_ref} mapping
- Basic cleanup on connection death
- Maximum 50 lines of code

#### File Structure
```
lib/websockex_new/
├── client.ex
├── config.ex
├── frame.ex
└── connection_registry.ex  # ETS-based connection tracking
```

#### Subtasks
- [x] **WNX0013a**: Create ETS table for connection registry in `connection_registry.ex`
- [x] **WNX0013b**: Implement connection registration/deregistration
- [x] **WNX0013c**: Add monitor-based cleanup on Gun process death
- [x] **WNX0013d**: Test connection tracking with multiple connections
- [x] **WNX0013e**: Handle ETS table cleanup on application shutdown

**Status**: ✅ COMPLETED - ETS-based connection tracking with monitor cleanup

### WNX0014: Reconnection Logic
**Priority**: High  
**Effort**: Medium  
**Dependencies**: WNX0013

#### Target Implementation
Simple exponential backoff without complex state management:
- Basic retry with exponential delay
- Maximum retry attempts
- Connection state preservation
- No GenServer - use simple recursive function

#### File Structure
```
lib/websockex_new/
├── client.ex
├── config.ex
├── frame.ex
├── connection_registry.ex
└── reconnection.ex         # Simple retry logic
```

#### Subtasks
- [x] **WNX0014a**: Implement exponential backoff calculation in `reconnection.ex`
- [x] **WNX0014b**: Add retry logic with maximum attempt limits
- [x] **WNX0014c**: Preserve subscription state across reconnections
- [x] **WNX0014d**: Test reconnection with real API connection drops
- [x] **WNX0014e**: Handle permanent failures (max retries exceeded)

**Status**: ✅ COMPLETED - Exponential backoff reconnection with state preservation

### WNX0015: Message Handler
**Priority**: High  
**Effort**: Medium  
**Dependencies**: WNX0012

#### Target Implementation
Single message handling module with callback interface:
- Parse incoming WebSocket frames
- Route messages to user-provided handler function
- Handle control frames (ping/pong) automatically
- Maximum 80 lines of code

#### File Structure
```
lib/websockex_new/
├── client.ex
├── config.ex
├── frame.ex
├── connection_registry.ex
├── reconnection.ex
└── message_handler.ex      # Message parsing and routing
```

#### Subtasks
- [x] **WNX0015a**: Implement message parsing and routing in `message_handler.ex`
- [x] **WNX0015b**: Add automatic ping/pong handling
- [x] **WNX0015c**: Create simple callback interface for user handlers
- [x] **WNX0015d**: Test message handling with real Deribit messages
- [x] **WNX0015e**: Handle malformed messages gracefully

**Status**: ✅ COMPLETED - Message handler with WebSocket upgrade support and automatic ping/pong

---

## Phase 3: Platform Integration (Week 3)

### WNX0016: Deribit Adapter
**Priority**: Medium  
**Effort**: Medium  
**Dependencies**: WNX0015

#### Target Implementation
Simple Deribit-specific adapter in new examples structure:
- Authentication flow
- Subscription management
- Message format handling
- Heartbeat responses
- Maximum 120 lines of code

#### File Structure
```
lib/websockex_new/
├── client.ex
├── config.ex
├── frame.ex
├── connection_registry.ex
├── reconnection.ex
├── message_handler.ex
└── examples/
    └── deribit_adapter.ex  # Platform-specific integration
```

#### Subtasks
- [x] **WNX0016a**: Create `examples/` directory under `websockex_new/`
- [x] **WNX0016b**: Implement Deribit authentication sequence in `deribit_adapter.ex`
- [x] **WNX0016c**: Add subscription/unsubscription message formatting
- [x] **WNX0016d**: Handle Deribit-specific message formats
- [x] **WNX0016e**: Implement heartbeat/test_request responses
- [x] **WNX0016f**: Test full integration with test.deribit.com

**Status**: ✅ COMPLETED - Full Deribit adapter with authentication, subscriptions, and real API testing

### WNX0017: Error Handling System
**Priority**: High  
**Effort**: Small  
**Dependencies**: WNX0014, WNX0015

#### Target Implementation
Simple error handling with raw error passing:
- Connection errors (network failures)
- Protocol errors (malformed frames)
- Authentication errors
- No custom error wrapping - pass raw errors from Gun/system

#### File Structure
```
lib/websockex_new/
├── client.ex
├── config.ex
├── frame.ex
├── connection_registry.ex
├── reconnection.ex
├── message_handler.ex
├── error_handler.ex        # Error recovery patterns
└── examples/
    └── deribit_adapter.ex
```

#### Subtasks
- [x] **WNX0017a**: Define error types and handling patterns in `error_handler.ex`
- [x] **WNX0017b**: Implement connection error recovery
- [x] **WNX0017c**: Add protocol error handling (malformed frames)
- [x] **WNX0017d**: Handle authentication failures appropriately
- [x] **WNX0017e**: Test error scenarios with real API failures
- [x] **WNX0017f**: Document error handling patterns for users

**Status**: ✅ COMPLETED - Comprehensive error handling system with categorization, recovery logic, and real API testing

### WNX0018: Real API Testing Infrastructure
**Priority**: Critical  
**Effort**: Medium  
**Dependencies**: None

#### Target Implementation
Comprehensive test suite for `websockex_new` module using real APIs and existing infrastructure:
- **IMPORTANT**: Tests must be in `test/websockex_new/` directory, completely separate from WebsockexNova tests
- Leverage existing `MockWebSockServer` in `test/support/` for controlled testing
- test.deribit.com integration tests for real API validation
- Connection lifecycle testing with proper test isolation
- Error scenario testing (network drops, auth failures)
- Zero new mock implementations - reuse existing infrastructure

#### File Structure
```
test/websockex_new/
├── integration/
│   ├── deribit_real_api_test.exs          # Real API tests only
│   └── mock_server_test.exs               # Uses existing MockWebSockServer
├── support/
│   └── websockex_new_helpers.ex           # Helpers specific to websockex_new
└── websockex_new_client_test.exs          # Core client functionality
```

#### Implementation Notes
**MOVED AFTER WNX0022**: This task will be much easier after migration cleanup eliminates the confusion between websockex_new and WebsockexNova systems. The existing `test/support/` infrastructure (MockWebSockServer, etc.) that we currently use for WebsockexNova tests will be reused for the migrated system.

#### Test Strategy (Post-Migration)
- Real API testing with test.deribit.com as primary validation
- Leverage existing MockWebSockServer for controlled scenarios
- Focus on connection lifecycle and error handling patterns

#### Subtasks (Deferred until after WNX0022)
- **WNX0018a**: Enhance existing test infrastructure for migrated system
- **WNX0018b**: Add comprehensive real API test coverage 
- **WNX0018c**: Test connection lifecycle scenarios
- **WNX0018d**: Validate error handling with real endpoints

### WNX0019: Deribit Bootstrap Sequence Implementation
**Priority**: High (Deferred until after WNX0022)  
**Effort**: Medium  
**Dependencies**: WNX0022 (Migration), then enhanced from current WNX0016

#### Target Implementation
Implement proper Deribit connection bootstrap sequence following their required flow:
- Connection with proper configuration
- Authentication
- Client introduction via hello
- Heartbeat setup 
- Cancel-on-disconnect protection
- Time synchronization

#### Technical Requirements
Heartbeats can be used to detect stale connections. When heartbeats have been set up, the API server will send heartbeat messages and test_request messages. Your software should respond to test_request messages by sending a /api/v2/public/test request. If your software fails to do so, the API server will immediately close the connection. If your account is configured to cancel on disconnect, any orders opened over the connection will be cancelled.

#### File Structure
```
lib/websockex_new/examples/
├── deribit_adapter.ex      # Enhanced with bootstrap sequence
└── deribit_bootstrap.ex    # Bootstrap sequence utilities
```

#### Subtasks
- [ ] **WNX0019a**: Implement connection configuration for bootstrap sequence
- [ ] **WNX0019b**: Add authentication step in bootstrap flow
- [ ] **WNX0019c**: Implement client hello message exchange
- [ ] **WNX0019d**: Set up heartbeat configuration and handling
- [ ] **WNX0019e**: Add cancel-on-disconnect protection setup
- [ ] **WNX0019f**: Implement time synchronization with Deribit servers
- [ ] **WNX0019g**: Add test_request message handling with /api/v2/public/test response
- [ ] **WNX0019h**: Test complete bootstrap sequence with test.deribit.com

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
**Priority**: Medium (Deferred until after WNX0022)  
**Effort**: Small  
**Dependencies**: WNX0022 (Migration), then enhanced from existing docs

#### Target Implementation
Concise documentation for the new system:
- Module documentation with real usage examples
- Deribit adapter usage guide
- Error handling patterns
- Migration guide from old system

#### Subtasks
- [ ] **WNX0021a**: Add comprehensive module documentation
- [ ] **WNX0021b**: Create Deribit integration examples
- [ ] **WNX0021c**: Document error handling patterns
- [ ] **WNX0021d**: Write migration guide from WebsockexNova to WebsockexNew

### WNX0022: System Migration and Cleanup
**Priority**: Critical - **MOVED TO PRIORITY #1**  
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

**Files to DELETE (old WebsockexNova system):**
```
lib/websockex_nova/             → DELETE ENTIRE DIRECTORY
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

test/websockex_nova/            → DELETE ENTIRE DIRECTORY
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
- [ ] **WNX0022a**: Create backup branch with current state
- [ ] **WNX0022b**: Delete entire `lib/websockex_nova/` directory (56 modules) 
- [ ] **WNX0022c**: Delete entire `test/websockex_nova/` directory
- [ ] **WNX0022d**: Install and run `rename` tool to update project metadata (mix.exs, README.md)
- [ ] **WNX0022e**: Update mix.exs dependencies (remove unused behavior deps)
- [ ] **WNX0022f**: Verify all tests pass with cleaned structure
- [ ] **WNX0022g**: Update README with simplified architecture (7 modules vs 56)

#### Rename Tool Usage
```bash
# Install rename tool
mix archive.install hex rename

# Rename project from websockex_nova to websockex_new
mix rename websockex_nova websockex_new
```

**Result**: Clean codebase with `WebsockexNew` namespace as the permanent, modern implementation.

---

## Target Architecture

### Final Module Structure (7 modules maximum)
```
lib/websockex_new/
├── client.ex              # Main client interface (5 functions)
├── config.ex              # Configuration struct and validation
├── frame.ex               # WebSocket frame encoding/decoding  
├── connection_registry.ex # ETS-based connection tracking
├── reconnection.ex        # Simple retry logic
├── message_handler.ex     # Message parsing and routing
├── error_handler.ex       # Error recovery patterns
└── examples/
    └── deribit_adapter.ex # Platform-specific integration
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
3. **Phase 4**: Clean cutover - remove old system, keep `WebsockexNew` namespace
4. **Project rename**: Use rename tool for project metadata only

## Success Metrics

### Quantitative Goals
- **Total modules**: Maximum 7 (vs current 56)
- **Lines of code**: Under 1,000 total (vs current ~10,000+)
- **Public API functions**: 5 (vs current dozens)
- **Configuration options**: 6 essential (vs current 20+)
- **Behaviors**: 0 (vs current 9)
- **GenServers**: 0-1 maximum (vs current multiple)
- **Test coverage**: 100% real API testing

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
5. **Clean migration** - Remove old system, keep new namespace permanent

### Quality Gates
- **Each module**: Maximum 5 functions, 15 lines per function
- **Each function**: Single responsibility, clear purpose
- **Each test**: Uses real API endpoints only
- **Each commit**: Maintains working system end-to-end

### Timeline
- **Week 1**: Core client (WNX0010-0012) - Basic connect/send/close ✅ COMPLETED
- **Week 2**: Connection management (WNX0013-0015) - Reconnection and messaging ✅ COMPLETED
- **Week 3**: Integration (WNX0016-0017) - Deribit adapter and error handling ✅ COMPLETED
- **Current phase**: Migration cleanup (WNX0022) then remaining features (WNX0018-0021)

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