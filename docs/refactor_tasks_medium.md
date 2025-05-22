# Medium Refactoring Tasks - Preserving the Best of WebsockexNova

This document outlines a **moderate refactoring approach** that preserves the proven architectural elements of WebsockexNova while achieving significant simplification. This strikes a balance between the current complexity and a complete rewrite.

## Refactoring Philosophy

**Preserve the Sweet Spots, Eliminate the Bloat**
- Keep proven patterns that provide real value
- Remove unnecessary abstraction layers and complexity
- Maintain backward compatibility for core APIs
- Target 25-30 modules (down from 56) while preserving flexibility

## What We're Preserving (The "Sweet Spots")

### ✅ Core Behavior System
**Keep:** ConnectionHandler, MessageHandler, ErrorHandler, SubscriptionHandler
**Why:** Proven separation of concerns with real-world validation via Deribit adapter

### ✅ Adapter Pattern with Macro
**Keep:** `use WebsockexNova.Adapter` macro system
**Why:** Minimal boilerplate, excellent developer experience, clear override points

### ✅ ClientConn State Structure
**Keep:** Canonical state management with Access behavior
**Why:** Single source of truth without excessive complexity

### ✅ Connection Registry
**Keep:** ETS-based connection ID mapping
**Why:** Solves real reconnection identity problem with minimal overhead

### ✅ Frame Handling System
**Keep:** Pluggable frame codec architecture
**Why:** Right level of abstraction for WebSocket protocol handling

### ✅ Client API Design
**Keep:** High-level, user-friendly public API
**Why:** Excellent developer experience with consistent patterns

## What We're Eliminating

### ❌ Excessive Process Architecture
**Remove:** Unnecessary GenServers and process hierarchies
**Replace:** Direct function calls where state doesn't need to persist

### ❌ Over-Abstracted Delegation Chains
**Remove:** 4+ layer delegation patterns
**Replace:** Direct behavior callback invocation

### ❌ Mock-Based Testing
**Remove:** All mock systems and fake transports
**Replace:** Real API testing with test.deribit.com and local test servers

### ❌ Unused Behaviors and Features
**Remove:** AuthHandler (merge into ConnectionHandler), RateLimitHandler
**Replace:** Simple, focused implementations within existing behaviors

### ❌ Complex Configuration Systems
**Remove:** Multiple configuration layers and validation systems
**Replace:** Single, clear configuration struct with validation

## Refactoring Tasks

### Phase 1: Process Architecture Simplification (Week 1)
**Goal:** Reduce process complexity while preserving core behavior system

#### WNX0020: Simplify Connection Management
- **Current:** Complex process hierarchy with ConnectionManager, ConnectionWrapper
- **Target:** Direct Gun process management with behavior callbacks
- **Files:** `lib/websockex_nova/connection_manager.ex`, `lib/websockex_nova/gun/connection_wrapper.ex`
- **Action:** 
  - Keep behavior callback structure
  - Remove intermediate GenServer layers
  - Direct Gun process monitoring and control
  - Preserve ConnectionHandler behavior interface
- **Preserved API:**
  ```elixir
  # Keep these callback patterns
  @callback handle_connect(conn_info, state) :: {:ok, state} | {:reply, frame_type, data, state}
  @callback handle_disconnect(reason, state) :: {:ok, state} | {:stop, reason, state}
  ```

#### WNX0021: Streamline Message Flow
- **Current:** Message routing through multiple process layers
- **Target:** Direct message handler invocation with behavior callbacks
- **Files:** All message routing in `lib/websockex_nova/gun/`
- **Action:**
  - Keep MessageHandler behavior interface
  - Remove intermediate message queuing
  - Direct callback invocation
  - Preserve JSON/binary message handling flexibility

#### WNX0022: Simplify Error Handling
- **Current:** Complex error delegation and recovery systems
- **Target:** Centralized ErrorHandler with simple retry logic
- **Files:** `lib/websockex_nova/defaults/default_error_handler.ex`
- **Action:**
  - Keep ErrorHandler behavior interface
  - Simplify reconnection logic to exponential backoff
  - Remove complex error classification
  - Preserve should_reconnect? callback pattern

### Phase 2: Behavior System Optimization (Week 2)
**Goal:** Consolidate behaviors while preserving extensibility

#### WNX0023: Merge AuthHandler into ConnectionHandler
- **Current:** Separate AuthHandler behavior
- **Target:** Authentication callbacks within ConnectionHandler
- **Rationale:** Authentication is part of connection lifecycle
- **Action:**
  - Add auth callbacks to ConnectionHandler behavior
  - Update Adapter macro to include auth defaults
  - Preserve current authentication patterns in Deribit adapter
  - Maintain backward compatibility

#### WNX0024: Eliminate RateLimitHandler
- **Current:** Separate RateLimitHandler behavior
- **Target:** Simple rate limiting within MessageHandler
- **Action:**
  - Move rate limiting logic into default message handler
  - Remove behavior interface
  - Preserve rate limiting functionality for adapters that need it

#### WNX0025: Optimize Behavior Helpers
- **Current:** Complex delegation system in behavior_helpers.ex
- **Target:** Simplified callback invocation helpers
- **Files:** `lib/websockex_nova/gun/helpers/behavior_helpers.ex`
- **Action:**
  - Keep the helper pattern (it's excellent)
  - Simplify callback resolution
  - Remove unnecessary error wrapping
  - Preserve consistent state management

### Phase 3: Configuration and State Simplification (Week 3)
**Goal:** Streamline configuration while preserving flexibility

#### WNX0026: Consolidate Configuration
- **Current:** Multiple configuration structs and validation layers
- **Target:** Single Configuration struct with clear validation
- **Files:** All config-related modules
- **Action:**
  - Create unified Configuration struct
  - Keep adapter-specific configuration patterns
  - Preserve current configuration flexibility
  - Simplify validation logic

#### WNX0027: Optimize ClientConn Structure
- **Current:** ClientConn with complex state management
- **Target:** Simplified state structure preserving Access behavior
- **Files:** `lib/websockex_nova/client_conn.ex`
- **Action:**
  - Keep the core ClientConn design (it works well)
  - Remove unused fields
  - Simplify state transitions
  - Preserve adapter state separation

### Phase 4: Testing Infrastructure Overhaul (Week 4)
**Goal:** Replace all mocks with real API testing

#### WNX0028: Eliminate Mock Systems
- **Current:** Mock transport and fake connection systems
- **Target:** Real WebSocket testing with test servers
- **Action:**
  - Remove all mock-related code
  - Create local test server using Plug.Cowboy
  - Integrate test.deribit.com for integration tests
  - Preserve current test coverage levels

#### WNX0029: Real API Integration Testing
- **Current:** Limited integration testing
- **Target:** Comprehensive real API testing
- **Action:**
  - Set up test.deribit.com integration tests
  - Create local WebSocket test server
  - Test full adapter lifecycle with real connections
  - Preserve existing test helper patterns

### Phase 5: Documentation and Examples (Week 5)
**Goal:** Update documentation to reflect simplified architecture

#### WNX0030: Update Adapter Documentation
- **Files:** `docs/behaviors.md`, `docs/client_macro.md`
- **Action:**
  - Update behavior documentation
  - Preserve adapter development patterns
  - Document simplified architecture
  - Maintain example quality

#### WNX0031: Refresh Integration Examples
- **Files:** `lib/websockex_nova/examples/`
- **Action:**
  - Update Deribit adapter to use simplified architecture
  - Preserve functionality while reducing complexity
  - Create additional platform examples
  - Maintain backward compatibility

## Target Architecture

### Final Module Count: ~25-30 modules (down from 56)
### Preserved Behaviors: 4 core behaviors (down from 9)
- ConnectionHandler (includes authentication)
- MessageHandler (includes rate limiting)
- ErrorHandler (simplified)
- SubscriptionHandler (unchanged)

### Key Preserved Patterns

#### Adapter Macro (Unchanged)
```elixir
defmodule MyAdapter do
  use WebsockexNova.Adapter
  
  @impl ConnectionHandler
  def connection_info(opts) do
    {:ok, %{host: "api.example.com", port: 443, path: "/ws"}}
  end
  
  @impl MessageHandler
  def handle_message(message, state) do
    # Custom message processing
    {:ok, updated_state}
  end
end
```

#### Client API (Enhanced but Compatible)
```elixir
# Preserve current API while adding improvements
{:ok, conn} = WebsockexNova.Client.connect(MyAdapter, options)
{:ok, response} = WebsockexNova.Client.send_json(conn, %{type: "subscribe"})
{:ok, subscription} = WebsockexNova.Client.subscribe(conn, "ticker", %{symbol: "BTC"})
```

#### Behavior Interface (Streamlined)
```elixir
# ConnectionHandler - now includes auth
@callback handle_connect(conn_info, state) :: {:ok, state} | {:reply, frame_type, data, state}
@callback handle_authenticate(credentials, state) :: {:ok, state} | {:error, reason, state}
@callback handle_disconnect(reason, state) :: {:ok, state} | {:stop, reason, state}

# MessageHandler - now includes rate limiting
@callback handle_message(message, state) :: {:ok, state} | {:reply, message_type, state}
@callback encode_message(message_type, state) :: {:ok, frame_type, binary} | {:error, reason}
@callback check_rate_limit(message_type, state) :: :ok | {:error, :rate_limited}
```

## Success Metrics

### Complexity Reduction
- **Module count:** 56 → 25-30 (45% reduction)
- **Behavior count:** 9 → 4 (55% reduction)
- **Process hierarchy:** Simplified to direct Gun management
- **Testing:** 100% real API testing (no mocks)

### Preserved Value
- **Adapter pattern:** Fully preserved with macro system
- **Behavior extensibility:** Maintained with streamlined interfaces
- **Client API:** Enhanced while maintaining compatibility
- **Connection reliability:** Preserved with simplified architecture
- **Developer experience:** Improved through reduced complexity

### Timeline
- **Total effort:** 5 weeks (vs 7 weeks for extreme refactoring)
- **Risk level:** Medium (vs High for complete rewrite)
- **Compatibility:** High (preserved APIs and patterns)
- **Maintainability:** Significantly improved

## Migration Strategy

### Phase-by-Phase Approach
1. Each phase can be tested independently
2. Backward compatibility maintained throughout
3. Gradual migration of existing adapters
4. Comprehensive test coverage before each merge

### Rollback Safety
- Each phase creates working, testable code
- Existing adapters continue to work
- Clear rollback points at each phase boundary
- Preserved configuration compatibility

This moderate refactoring approach achieves significant simplification while preserving the architectural innovations that make WebsockexNova valuable. The result is a cleaner, more maintainable codebase that retains the flexibility and extensibility that users depend on.