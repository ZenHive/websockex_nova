# WebsockexNova Simplification Refactor Tasks

## Project Goal
Transform WebsockexNova from an over-engineered WebSocket client into a simple, maintainable library that delivers core functionality with minimal complexity. Focus on eliminating unnecessary abstractions, reducing moving parts, and optimizing for developer experience.

## Guiding Principles
- **Simplicity over flexibility**: Remove abstractions without ≥3 concrete implementations
- **Functions over processes**: Replace GenServers with simple functions where possible  
- **Direct over delegated**: Flatten deep call chains to maximum 2 levels
- **Essential over comprehensive**: Keep only features that deliver maximum value
- **Explicit over magical**: Remove macro systems in favor of clear module definitions
- **Real testing only**: NO MOCKS - Always test against real APIs (test.deribit.com or production)

---

## Phase 1: Core Architecture Simplification

### WNX0001: Behavior System Consolidation (Critical)
**Priority**: High  
**Effort**: Large  
**Dependencies**: None

#### Current State
- 9 separate behaviors with full interface definitions
- 8 default implementations duplicating patterns
- 24 modules implementing @behaviour annotations
- Over-engineered plugin system for basic WebSocket operations

#### Target State
- Maximum 3 essential behaviors: `ConnectionHandler`, `MessageHandler`, `ErrorHandler`
- Remove authentication, metrics, rate limiting, subscription behaviors
- Inline simple functionality instead of creating behavior abstractions

#### Subtasks
- [ ] **WNX0001a**: Audit all current behavior usage and identify consolidation opportunities
- [ ] **WNX0001b**: Merge subscription logic into `MessageHandler`
- [ ] **WNX0001c**: Move authentication to simple module functions
- [ ] **WNX0001d**: Remove metrics, logging, rate limiting behaviors
- [ ] **WNX0001e**: Update all adapters to use consolidated behaviors
- [ ] **WNX0001f**: Remove unused default behavior implementations

### WNX0002: Connection Wrapper Simplification (Critical)
**Priority**: High  
**Effort**: Large  
**Dependencies**: WNX0001

#### Current State
- `connection_wrapper.ex`: 1,737 lines, 49 functions
- Complex delegation chains through 4+ layers
- Multiple helper modules for similar state management
- Violates 15-line function limit and 5-function module limit

#### Target State
- Single focused module under 300 lines, maximum 8 essential functions
- Direct Gun API usage without excessive wrapper layers
- Simple state management without complex synchronization

#### Subtasks
- [ ] **WNX0002a**: Extract essential functions (connect, send, close, handle_message)
- [ ] **WNX0002b**: Remove delegation layers and call Gun API directly
- [ ] **WNX0002c**: Simplify state management to basic connection tracking
- [ ] **WNX0002d**: Eliminate behavior bridge and state sync complexity
- [ ] **WNX0002e**: Merge related functionality into single cohesive module
- [ ] **WNX0002f**: Update tests to work with simplified interface

### WNX0003: Helper Module Consolidation (Medium)
**Priority**: Medium  
**Effort**: Medium  
**Dependencies**: WNX0002

#### Current State
- 3 separate state helper modules with overlapping functionality
- Duplicated utility functions across different helper namespaces
- `behavior_helpers.ex` (564 lines) providing unnecessary abstraction

#### Target State
- Single `utils.ex` module with essential helper functions
- Remove duplicate functionality and unused utilities
- Maximum 10 utility functions total

#### Subtasks
- [ ] **WNX0003a**: Audit all helper functions and identify duplicates
- [ ] **WNX0003b**: Merge essential functions into single `lib/websockex_nova/utils.ex`
- [ ] **WNX0003c**: Remove `behavior_helpers.ex` and inline necessary logic
- [ ] **WNX0003d**: Delete redundant state helper modules
- [ ] **WNX0003e**: Update all references to use consolidated utilities

---

## Phase 2: Feature Elimination

### WNX0004: Remove Mock Systems and Unused Features (Medium)
**Priority**: Medium  
**Effort**: Medium  
**Dependencies**: WNX0001, WNX0003

#### Current State
- `StateTracer` module (261 lines) only referenced in its own file
- Mock transport implementations in production code (UNRELIABLE)
- `AdapterWithSubscriptionPreservation` example in main library
- Complex ownership transfer protocol for edge cases

#### Target State
- Clean codebase with only actively used features
- NO MOCK SYSTEMS - All testing against real APIs only
- Move examples to separate directory or remove entirely
- Remove debugging/tracing features from production code

#### Subtasks
- [ ] **WNX0004a**: Remove `StateTracer` module and all references
- [ ] **WNX0004b**: **DELETE all mock transport implementations** (unreliable, causes false confidence)
- [ ] **WNX0004c**: Delete example adapters from main library
- [ ] **WNX0004d**: Remove ownership transfer protocol
- [ ] **WNX0004e**: Audit and remove other unused modules
- [ ] **WNX0004f**: Clean up unused configuration options

### WNX0005: Frame Handler Simplification (Medium)
**Priority**: Medium  
**Effort**: Small  
**Dependencies**: None

#### Current State
- 4 separate frame handler modules for basic WebSocket operations
- `frame_codec.ex`: 364 lines, 37 functions
- Over-engineered for standard WebSocket frame handling

#### Target State
- Single simple frame handling module with essential encode/decode functions
- Direct implementation without unnecessary abstraction layers
- Maximum 5 functions: encode_text, encode_binary, decode_frame, ping, pong

#### Subtasks
- [ ] **WNX0005a**: Merge all frame handlers into single `frame_utils.ex`
- [ ] **WNX0005b**: Reduce to 5 essential frame functions
- [ ] **WNX0005c**: Remove control frame handler complexity
- [ ] **WNX0005d**: Update connection wrapper to use simple frame utils
- [ ] **WNX0005e**: Remove frame handler behavior abstractions

### WNX0006: Client Interface Consolidation (Small)
**Priority**: Low  
**Effort**: Small  
**Dependencies**: WNX0001, WNX0002

#### Current State
- Multiple client modules with overlapping functionality
- ClientMacro system adding unnecessary metaprogramming
- Deribit-specific clients mixed with generic client code

#### Target State
- Single `WebsockexNova.Client` module with clear, simple API
- Remove macro system in favor of explicit implementations
- Move platform-specific code to separate adapter modules

#### Subtasks
- [ ] **WNX0006a**: Consolidate all client interfaces into single module
- [ ] **WNX0006b**: Remove ClientMacro and AdapterMacro systems
- [ ] **WNX0006c**: Move Deribit adapter to examples directory
- [ ] **WNX0006d**: Simplify client API to 5 essential functions
- [ ] **WNX0006e**: Update documentation for simplified client interface

---

## Phase 3: Process Simplification

### WNX0007: Replace GenServers with Functions (Medium)
**Priority**: Medium  
**Effort**: Medium  
**Dependencies**: WNX0001

#### Current State
- Rate limiting GenServer for simple token bucket algorithm
- Connection registry GenServer for basic PID mapping
- Unnecessary process overhead for stateless operations

#### Target State
- Simple module functions for rate limiting using ETS or process dictionary
- Basic connection registry using ETS table
- Processes only where truly necessary for state management

#### Subtasks
- [ ] **WNX0007a**: Replace rate limiting GenServer with simple function + ETS
- [ ] **WNX0007b**: Simplify connection registry to ETS-based lookup
- [ ] **WNX0007c**: Audit other GenServers for simplification opportunities
- [ ] **WNX0007d**: Update supervision tree to remove unnecessary processes
- [ ] **WNX0007e**: Test simplified implementations maintain functionality

### WNX0008: Configuration Simplification (Small)
**Priority**: Low  
**Effort**: Small  
**Dependencies**: WNX0004

#### Current State
- Massive configuration objects with 20+ options
- Multiple configuration precedence layers
- Profile-based configuration system not fully utilized
- Complex validation and transformation logic

#### Target State
- Essential configuration options only (url, headers, timeout, retry_count)
- Single configuration struct with sensible defaults
- Remove profile system complexity

#### Subtasks
- [ ] **WNX0008a**: Audit configuration usage and remove unused options
- [ ] **WNX0008b**: Simplify to 6 essential configuration fields
- [ ] **WNX0008c**: Remove profile-based configuration system
- [ ] **WNX0008d**: Simplify configuration validation
- [ ] **WNX0008e**: Update adapters to use simplified configuration

---

## Phase 4: Real API Testing Infrastructure

### WNX0009: Real API Testing Implementation (Critical)
**Priority**: High  
**Effort**: Medium  
**Dependencies**: All previous phases

#### Current State
- Complex test helpers with unreliable mock implementations
- Mock systems providing false confidence in test results
- Integration tests requiring excessive setup ceremony

#### Target State
- **ALL tests run against real WebSocket APIs**
- Primary: test.deribit.com (sandbox environment)
- Fallback: Production APIs with rate limiting considerations
- Simple test helpers focused on real API interactions
- Streamlined setup for real endpoint testing

#### Subtasks
- [ ] **WNX0009a**: **Remove ALL mock implementations completely**
- [ ] **WNX0009b**: Configure test suite to use test.deribit.com by default
- [ ] **WNX0009c**: Add real API endpoints for different test scenarios
- [ ] **WNX0009d**: Implement rate limiting for production API tests
- [ ] **WNX0009e**: Create test helpers for real API authentication
- [ ] **WNX0009f**: Document real API testing setup and credentials
- [ ] **WNX0009g**: Add fallback to production APIs when test APIs unavailable

---

## Success Metrics

### Quantitative Goals
- **Module count**: Reduce from 56 to under 20 modules
- **Total lines of code**: Reduce by 40-50%
- **Average function length**: Under 10 lines
- **Functions per module**: Maximum 5 for new modules
- **Behavior count**: Reduce from 9 to 3
- **Configuration options**: Reduce from 20+ to 6 essential options
- **Mock code**: 0 lines (complete elimination)

### Qualitative Goals
- **Developer onboarding**: New developers can understand core functionality in under 2 hours
- **Debugging**: Issue resolution requires examining maximum 3 modules
- **Feature addition**: Adding new functionality requires touching maximum 2 modules
- **Maintenance burden**: Routine updates affect under 5 modules
- **Code comprehension**: Any module can be fully understood in under 15 minutes
- **Test reliability**: 100% real API testing provides true confidence in functionality

## Testing Philosophy: NO MOCKS POLICY

### Why No Mocks
- **False confidence**: Mocks pass when real systems fail
- **Integration gaps**: Mock behavior diverges from real API behavior
- **Maintenance burden**: Mocks require updates when APIs change
- **Debugging difficulty**: Mock-based failures don't reflect production issues

### Real API Testing Strategy
1. **Primary**: Use test/sandbox APIs (test.deribit.com)
2. **Secondary**: Use production APIs with careful rate limiting
3. **Test data**: Use dedicated test accounts and cleanup procedures
4. **CI/CD**: Environment variables for real API credentials
5. **Error scenarios**: Test real network failures, not simulated ones

## Implementation Strategy

### Phase Sequencing
1. **Phase 1** (Critical foundation): Must be completed first as other phases depend on it
2. **Phase 2** (Feature cleanup): Can proceed in parallel after Phase 1 completion
3. **Phase 3** (Process optimization): Builds on simplified architecture from Phases 1-2
4. **Phase 4** (Real API testing): **CRITICAL** - Must eliminate all mocks and establish real testing

### Risk Mitigation
- **Incremental approach**: Complete each subtask individually with tests
- **Backward compatibility**: Maintain public API compatibility during Phase 1-2
- **Performance validation**: Benchmark before/after to ensure no performance regression
- **Real integration testing**: Continuous integration tests with real WebSocket endpoints
- **API rate limiting**: Implement proper rate limiting for production API tests

### Timeline Estimate
- **Phase 1**: 2-3 weeks (critical path)
- **Phase 2**: 1-2 weeks (parallel after Phase 1)
- **Phase 3**: 1 week (depends on Phases 1-2)
- **Phase 4**: 1 week (critical for real testing infrastructure)
- **Total**: 5-7 weeks for complete simplification

## Notes
This refactoring prioritizes maintainability and developer experience over architectural purity. The goal is a WebSocket client that "just works" with minimal cognitive overhead, following the principle that the best code is no code, and the second best code is simple code.

**CRITICAL**: The elimination of all mock systems is non-negotiable. Real API testing is the only reliable way to ensure the WebSocket client works in production environments.