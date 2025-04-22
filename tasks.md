# WebsockexNova Implementation Tasks

This document outlines the prioritized tasks for implementing WebsockexNova with Gun as the transport layer, following Test-Driven Development principles.

## Format

Tasks follow this format:

- **ID**: Unique task identifier (e.g., T1.1)
- **Name**: Short description
- **Description**: Detailed explanation of the task
- **Acceptance Criteria**: Measurable conditions for completion
- **Priority**: P0 (critical), P1 (high), P2 (medium), P3 (nice to have), P4 (low)
- **Effort**: Estimated effort in days
- **Dependencies**: IDs of tasks that must be completed first
- **Status**: TODO, IN_PROGRESS, DONE

## Phase 1: Project Setup & Core Behaviors

### T1.1

- **Name**: Add Gun dependency to mix.exs
- **Description**: Add the Gun package as a dependency and configure it
- **Acceptance Criteria**:
  - Gun dependency added with appropriate version
  - Version matches our requirements (HTTP/2, WebSocket support)
  - Dependency successfully resolving in mix.lock
- **Priority**: P0
- **Effort**: 0.5
- **Dependencies**: None
- **Status**: DONE

### T1.2

- **Name**: Define ConnectionHandler behavior test cases
- **Description**: Create test cases for the ConnectionHandler behavior
- **Acceptance Criteria**:
  - Tests for required callbacks: init/1, handle_connect/2, handle_disconnect/2, handle_frame/3
  - Tests for optional callbacks
  - Tests for proper state handling
- **Priority**: P0
- **Effort**: 1
- **Dependencies**: None
- **Status**: DONE

### T1.3

- **Name**: Define ConnectionHandler behavior
- **Description**: Create behavior module that defines connection lifecycle callbacks
- **Acceptance Criteria**:
  - Required callbacks defined with proper specs
  - Optional callbacks have default implementations
  - Comprehensive moduledoc and callback documentation
- **Priority**: P0
- **Effort**: 1
- **Dependencies**: T1.2
- **Status**: DONE

### T1.4

- **Name**: Define MessageHandler behavior test cases
- **Description**: Create test cases for the MessageHandler behavior
- **Acceptance Criteria**:
  - Tests for handle_message/2, validate_message/1, message_type/1, encode_message/2
  - Tests for proper message processing and routing
- **Priority**: P0
- **Effort**: 1
- **Dependencies**: None
- **Status**: DONE

### T1.5

- **Name**: Define MessageHandler behavior
- **Description**: Create behavior module for message processing
- **Acceptance Criteria**:
  - Required callbacks defined with proper specs
  - Default implementations for optional callbacks
  - Comprehensive documentation
- **Priority**: P0
- **Effort**: 1
- **Dependencies**: T1.4
- **Status**: DONE

### T1.6

- **Name**: Define ErrorHandler behavior test cases
- **Description**: Create test cases for error handling behavior
- **Acceptance Criteria**:
  - Tests for handle_error/3, should_reconnect?/3, log_error/3
  - Tests covering various error scenarios
- **Priority**: P0
- **Effort**: 1
- **Dependencies**: None
- **Status**: DONE

### T1.7

- **Name**: Define ErrorHandler behavior
- **Description**: Create behavior module for standardized error handling
- **Acceptance Criteria**:
  - Required callbacks defined with proper specs
  - Default implementations with sensible behavior
  - Documentation with error handling patterns
- **Priority**: P0
- **Effort**: 1
- **Dependencies**: T1.6
- **Status**: DONE

### T1.8

- **Name**: Create default behavior implementation tests
- **Description**: Test the default implementations of all behaviors
- **Acceptance Criteria**:
  - Tests for DefaultConnectionHandler
  - Tests for DefaultMessageHandler
  - Tests for DefaultErrorHandler
- **Priority**: P1
- **Effort**: 1.5
- **Dependencies**: T1.3, T1.5, T1.7
- **Status**: DONE

### T1.9

- **Name**: Implement default behavior implementations
- **Description**: Create default modules that implement each behavior
- **Acceptance Criteria**:
  - DefaultConnectionHandler module
  - DefaultMessageHandler module
  - DefaultErrorHandler module
  - All tests passing
- **Priority**: P1
- **Effort**: 2
- **Dependencies**: T1.8
- **Status**: DONE

## Phase 2: Gun Integration

### T2.1

- **Name**: Create Gun client supervisor tests
- **Description**: Test cases for Gun client supervisor
- **Acceptance Criteria**:
  - Tests for supervisor initialization
  - Child specification validation
  - Restart strategy tests
- **Priority**: P0
- **Effort**: 0.5
- **Dependencies**: T1.1
- **Status**: DONE
- **Code Review Rating** Rating: 5/5

### T2.2

- **Name**: Create Gun client supervisor
- **Description**: Implement supervisor for Gun client processes
- **Acceptance Criteria**:
  - Proper child specifications
  - Appropriate restart strategy
  - Configuration via application env
  - All tests passing
- **Priority**: P0
- **Effort**: 1
- **Dependencies**: T2.1
- **Status**: DONE
- **Code Review Rating** Rating: 5/5

### T2.3

- **Name**: Create Gun connection wrapper tests
- **Description**: Test cases for the Gun connection wrapper
- **Acceptance Criteria**:
  - Tests for connection establishment
  - Tests for WebSocket upgrade
  - Tests for message sending
  - Tests for frame handling
- **Priority**: P0
- **Effort**: 1.5
- **Dependencies**: T2.2
- **Status**: DONE
- **Code Review Rating** Rating: 5/5

### T2.4

- **Name**: Implement basic Gun connection wrapper
- **Description**: Create a module that wraps Gun's connection functionality
- **Acceptance Criteria**:
  - Connect/disconnect functions
  - Send frame function
  - Process Gun messages function
  - All tests passing
- **Priority**: P0
- **Effort**: 2
- **Dependencies**: T2.3
- **Status**: DONE
- **Code Review Rating** Rating: 5/5

### T2.5

- **Name**: Create WebSocket frame encoder/decoder tests
- **Description**: Test cases for WebSocket frame handling
- **Acceptance Criteria**:
  - Tests for text frame encoding/decoding
  - Tests for binary frame encoding/decoding
  - Tests for ping/pong frames
  - Tests for close frames with status codes
- **Priority**: P0
- **Effort**: 0.5
- **Dependencies**: T2.4
- **Status**: DONE
- **Code Review Rating** Rating: 5/5

### T2.6

- **Name**: Implement WebSocket frame encoding/decoding
- **Description**: Create module for handling WebSocket frame formats
- **Acceptance Criteria**:
  - Functions for encoding/decoding text frames
  - Functions for encoding/decoding binary frames
  - Functions for control frames (ping/pong/close)
  - All tests passing
- **Priority**: P0
- **Effort**: 1
- **Dependencies**: T2.5
- **Status**: DONE
- **Code Review Rating** Rating: 5/5

### T2.7

- **Name**: Create connection state management tests
- **Description**: Test cases for connection state management
- **Acceptance Criteria**:
  - Tests for state transitions (connecting, connected, disconnected)
  - Tests for automatic reconnection
  - Tests for connection failure handling
- **Priority**: P0
- **Effort**: 1
- **Dependencies**: T2.4
- **Status**: DONE
- **Code Review Rating** Rating: 5/5

### T2.8

- **Name**: Implement connection state management
- **Description**: Create module for managing WebSocket connection state
- **Acceptance Criteria**:
  - State machine for connection lifecycle
  - Event handlers for state transitions
  - Configuration for timeouts and retries
  - All tests passing
- **Priority**: P0
- **Effort**: 2
- **Dependencies**: T2.7
- **Status**: DONE
- **Code Review Rating** Rating: 5/5

### T2.9

- **Name**: Improve resource cleanup handling
- **Description**: Ensure resources are properly released when connections close or errors occur
- **Acceptance Criteria**:
  - Tests for stream cleanup on disconnect
  - Tests for memory leaks in connection/state management
  - Comprehensive connection teardown logic
  - All tests passing
- **Priority**: P0
- **Effort**: 0.5
- **Dependencies**: T2.8
- **Status**: DONE
- **Code Review Rating** Rating: 5/5

### T2.10

- **Name**: Optimize frame handler initialization
- **Description**: Improve the ETS table initialization pattern for frame handlers
- **Acceptance Criteria**:
  - Single initialization point (application startup)
  - Remove redundant init calls in public functions
  - Add fallback mechanism for unexpected states
  - All tests passing
- **Priority**: P1
- **Effort**: 0.5
- **Dependencies**: T2.6
- **Status**: DONE
- **Code Review Rating** Rating: 5/5

### T2.11

- **Name**: Create integration tests for connection wrapper
- **Description**: Test actual Gun interaction (not just test mode) in controlled environment
- **Acceptance Criteria**:
  - Tests with a mock WebSocket server
  - Tests for real Gun client integration
  - Tests for actual socket communication
  - Tests for various network scenarios
- **Priority**: P1
- **Effort**: 1
- **Dependencies**: T2.8
- **Status**: DONE
- **Code Review Rating** Rating: 4/5,
  The implementation provides solid coverage of the core functionality and demonstrates a well-designed test infrastructure. The mock server is particularly well-implemented, with support for different scenarios and network conditions.
  However, the integration tests don't fully cover all the acceptance criteria, particularly the "Tests for various network scenarios" which could be more comprehensive. Additionally, the task is still marked as "IN_PROGRESS" which aligns with these missing elements.
  The code quality and design of the testing infrastructure is excellent, but the scope of tests needs to be expanded to fully satisfy the acceptance criteria.

### T2.12

- **Name**: Improve edge case handling in connection wrapper
- **Description**: Add robust handling for edge cases and unexpected states
- **Acceptance Criteria**:
  - Tests for invalid stream references
  - Tests for unexpected Gun messages
  - Improved error logging and diagnostics
  - Invalid state transition prevention
  - All tests passing
- **Priority**: P1
- **Effort**: 0.5
- **Dependencies**: T2.11
- **Status**: DONE
- **Code Review Rating** Rating: 4.5/5
  Why not a 5?
  The only minor deductions are for some non-deterministic test outcomes (due to the realities of process death and async messaging), and the use of direct state mutation in tests. These are pragmatic choices, but with a bit more abstraction or deterministic error handling, it could be a perfect 5.

### T2.13

- **Name**: Add robust Gun process ownership management
- **Description**: Ensure proper Gun ownership setup and message routing between processes
- **Acceptance Criteria**:
  - Tests for proper Gun message routing
  - Implementation of ownership management in ConnectionWrapper
  - Documentation of ownership patterns
  - Handling of ownership transfer edge cases
- **Priority**: P0
- **Effort**: 1
- **Dependencies**: T2.4
- **Status**: DONE
  - Added comprehensive validation in transfer_ownership/receive_ownership functions
  - Improved error handling in ownership transfers
  - Added proper monitor cleanup during transfers
  - Enhanced state handling with StateHelpers.handle_ownership_transfer
  - Added detailed documentation about ownership patterns
  - Implemented test for invalid receive_ownership cases
- **Code Review Rating** Rating: 5/5

### T2.14

- **Name**: Refactor ConnectionWrapper for clean architecture
- **Description**: Refactor the ConnectionWrapper module to better align with the planned behavior-based architecture
- **Acceptance Criteria**:
  - Move business logic to ConnectionManager
  - Standardize error handling patterns
  - Support configurable behavior module callbacks
  - Consistent state management through helpers
  - Improve message handling delegation
  - Clean up ownership transfer code
  - Add telemetry integration
  - Remove test-only and debugging code from production
  - Update documentation to reflect new architecture
  - All tests continue to pass
- **Priority**: P0
- **Effort**: 3
- **Dependencies**: T2.13, T2.8
- **Status**: DONE
- **Code Review Rating** Rating: 4.5/5, The only significant missing item appears to be the telemetry integration, which was listed in the acceptance criteria. Otherwise, the refactoring has been completed according to the plan, with all other criteria met.

## Phase 3: Reconnection & Integration

### T3.1

- **Name**: Create reconnection strategy tests
- **Description**: Test cases for reconnection strategies
- **Acceptance Criteria**:
  - Tests for linear backoff
  - Tests for exponential backoff
  - Tests for jittered backoff
  - Tests for max retry limits
- **Priority**: P1
- **Effort**: 1
- **Dependencies**: T2.8
- **Status**: DONE
- **Code Review Rating** Rating: 5/5

### T3.2

- **Name**: Implement reconnection strategies
- **Description**: Create modules for different reconnection approaches
- **Acceptance Criteria**:
  - LinearBackoff strategy
  - ExponentialBackoff strategy
  - JitteredBackoff strategy
  - Configuration options for each
  - All tests passing
- **Priority**: P1
- **Effort**: 2
- **Dependencies**: T3.1
- **Status**: DONE
- **Code Review Rating** Rating: 5/5

### T3.3

- **Name**: Create Gun-to-behavior bridge tests
- **Description**: Test the integration between Gun and behaviors
- **Acceptance Criteria**:
  - Tests for message routing from Gun to behaviors
  - Tests for behavior callback invocation
  - Tests for error propagation
- **Priority**: P0
- **Effort**: 1.5
- **Dependencies**: T1.9, T2.8
- **Status**: DONE
- **Code Review Rating** Rating: 5/5

### T3.4

- **Name**: Implement Gun-to-behavior bridge
- **Description**: Create module to connect Gun events to behavior callbacks
- **Acceptance Criteria**:
  - Routing of Gun messages to appropriate behavior callbacks
  - Handling of Gun events (connect, disconnect, etc.)
  - Error propagation to ErrorHandler
  - All tests passing
- **Priority**: P0
- **Effort**: 3
- **Dependencies**: T3.3
- **Status**: DONE
- **Code Review Rating** Rating: 5/5

## Phase 4: Enhanced Features

### T4.1

- **Name**: Define SubscriptionHandler behavior tests
- **Description**: Test cases for subscription management
- **Acceptance Criteria**:
  - Tests for subscribe/3, unsubscribe/2, handle_subscription_response/2
  - Tests for subscription state management
- **Priority**: P1
- **Effort**: 0.5
- **Dependencies**: T1.5
- **Status**: DONE
- **Code Review Rating** Rating: 5/5

### T4.2

- **Name**: Define SubscriptionHandler behavior
- **Description**: Create behavior for managing channel subscriptions
- **Acceptance Criteria**:
  - Required callbacks with proper specs
  - Default implementations where appropriate
  - Comprehensive documentation
  - All tests passing
- **Priority**: P1
- **Effort**: 1
- **Dependencies**: T4.1
- **Status**: DONE
- **Code Review Rating** Rating: 5/5

### T4.3

- **Name**: Create subscription management tests
- **Description**: Test implementation of subscription tracking
- **Acceptance Criteria**:
  - Tests for adding/removing subscriptions
  - Tests for subscription state persistence
  - Tests for resubscribing after reconnect
- **Priority**: P1
- **Effort**: 1
- **Dependencies**: T4.2
- **Status**: DONE
- **Code Review Rating** Rating: 5/5

### T4.4

- **Name**: Implement subscription management
- **Description**: Create module for tracking and managing subscriptions
- **Acceptance Criteria**:
  - Functions to add/remove subscriptions
  - State management for subscriptions
  - Automatic resubscription after reconnect
  - All tests passing
- **Priority**: P1
- **Effort**: 2
- **Dependencies**: T4.3
- **Status**: DONE
- **Code Review Rating** Rating: 5/5

### T4.5

- **Name**: Telemetry and Metrics Integration (Combined)
- **Description**: Design and implement a unified telemetry and metrics system. Emit standardized telemetry events throughout the library, and implement a MetricsCollector behavior and default implementation that subscribes to these events. Ensure comprehensive test coverage and documentation.
- **Acceptance Criteria**:
  - Consistent telemetry events are emitted for connection, message, and error events (including performance measurements)
  - MetricsCollector behavior is defined with required callbacks and typespecs
  - DefaultMetricsCollector implementation subscribes to telemetry events and tracks:
    - Connection statistics (counts, durations)
    - Message throughput (count, size, latency)
    - Error metrics by category
  - MetricsCollector supports different metric types (counter, gauge, histogram)
  - Comprehensive tests for telemetry emission and metrics aggregation
  - Documentation for event names, payloads, and metrics integration
  - All tests passing
- **Priority**: P1
- **Effort**: 3
- **Dependencies**: T3.4, T4.4
- **Status**: DONE
- **Progress**:
  - [x] Telemetry event design and documentation complete (`lib/websockex_nova/telemetry/telemetry_events.ex`)
  - [x] MetricsCollector behavior defined (`lib/websockex_nova/behaviors/metrics_collector.ex`)
  - [x] DefaultMetricsCollector implemented and tested (`lib/websockex_nova/defaults/default_metrics_collector.ex`)
  - [x] Tests for event emission and aggregation (`test/websockex_nova/defaults/default_metrics_collector_test.exs`)
  - [x] Telemetry emission integration into core modules (next step)
  - [x] Documentation and guides update
- **Code Review Rating** Rating: 5/5

### T4.7

- **Name**: Define AuthHandler behavior tests
- **Description**: Test cases for authentication handling
- **Acceptance Criteria**:
  - Tests for generate_auth_data/1, handle_auth_response/2, needs_reauthentication?/1
  - Tests for authentication flows
- **Priority**: P1
- **Effort**: 0.5
- **Dependencies**: T3.4
- **Status**: DONE
- **Code Review Rating** Rating: 5/5

### T4.8

- **Name**: Define AuthHandler behavior
- **Description**: Create behavior for authentication flows
- **Acceptance Criteria**:
  - Required callbacks with proper specs
  - Default implementations where appropriate
  - Comprehensive documentation
  - All tests passing
- **Priority**: P1
- **Effort**: 1
- **Dependencies**: T4.7
- **Status**: DONE
- **Code Review Rating** Rating: 5/5

### T4.9

- **Name**: Create authentication flow tests
- **Description**: Test implementation of authentication
- **Acceptance Criteria**:
  - Tests for initial authentication
  - Tests for reauthentication
  - Tests for auth failure handling
- **Priority**: P1
- **Effort**: 1
- **Dependencies**: T4.8
- **Status**: DONE
- **Code Review Rating** Rating: 5/5

### T4.10

- **Name**: Implement authentication flow
- **Description**: Create module for handling authentication
- **Acceptance Criteria**:
  - Initial authentication
  - Token refresh/reauthentication
  - Auth failure recovery
  - All tests passing
- **Priority**: P1
- **Effort**: 2
- **Dependencies**: T4.9
- **Status**: DONE
- **Code Review Rating** Rating: 5/5

### T4.11

- **Name**: Create rate limiting tests
- **Description**: Test cases for rate limiting functionality
- **Acceptance Criteria**:
  - Tests for request throttling
  - Tests for rate limit configuration
  - Tests for burst handling
- **Priority**: P2
- **Effort**: 0.5
- **Dependencies**: T3.4
- **Status**: DONE
- **Code Review Rating** Rating: 5/5

### T4.12

- **Name**: Implement rate limiting
- **Description**: Create module for controlling request rates
- **Acceptance Criteria**:
  - Configurable rate limits
  - Token bucket algorithm implementation
  - Request queueing when needed
  - All tests passing
- **Priority**: P2
- **Effort**: 1.5
- **Dependencies**: T4.11
- **Status**: DONE
- **Code Review Rating** Rating: 5/5

### T4.13

- **Name**: Define LoggingHandler behavior tests
- **Description**: Test cases for standardized logging behavior
- **Acceptance Criteria**:
  - Tests for log_connection_event/3, log_message_event/3, log_error_event/3
  - Tests for log level configuration
  - Tests for log formatting customization
- **Priority**: P2
- **Effort**: 0.5
- **Dependencies**: T3.4
- **Status**: DONE
- **Code Review Rating** Rating: 5/5

### T4.14

- **Name**: Define LoggingHandler behavior
- **Description**: Create behavior for standardized, configurable logging
- **Acceptance Criteria**:
  - Required callbacks with proper specs
  - Default implementations with sensible behavior
  - Support for different log formats and levels
  - Documentation with logging patterns
- **Priority**: P2
- **Effort**: 1
- **Dependencies**: T4.13
- **Status**: DONE
- **Code Review Rating** Rating: 5/5

### T4.15

- **Name**: Implement DefaultLoggingHandler
- **Description**: Create default implementation of LoggingHandler
- **Acceptance Criteria**:
  - Standardized logging for connection lifecycle events
  - Message event logging with configurable verbosity
  - Structured error logging with context
  - Integration with Logger
  - Tests passing
- **Priority**: P2
- **Effort**: 1
- **Dependencies**: T4.14
- **Status**: DONE
- **Code Review Rating** Rating: 5/5

## Phase 5: Production-Grade Orchestration & Integration

### T5.1

- **Name**: Remove DummyClient from all orchestration and integration code
- **Description**: Ensure that DummyClient is no longer used in any part of the codebase, including tests, supervisors, and documentation. All orchestration and integration tests should use the real connection stack (Connection, ConnectionWrapper, Gun, etc.).
- **Acceptance Criteria**:
  - DummyClient is not referenced in any test, supervisor, or runtime code
  - All tests use the real connection stack
  - Documentation is updated to reflect this change
- **Priority**: P0
- **Effort**: 0.5
- **Dependencies**: None
- **Status**: DONE
  - DummyClient fully removed from codebase and replaced with ConnectionWrapper in supervisor.

### T5.2

- **Name**: Comprehensive integration test suite for connection lifecycle
- **Description**: Implement a suite of integration tests covering the full connection lifecycle, including connect, disconnect, send, receive, subscribe, authenticate, ping, status, error handling, and reconnection. Tests should use a real echo/test WebSocket server and the production connection stack.
- **Acceptance Criteria**:
  - Tests for connect/disconnect (normal and error cases)
  - Tests for send/receive (text, JSON, binary)
  - Tests for subscribe/unsubscribe (including error and edge cases)
  - Tests for authenticate (success, failure, expired token, etc.)
  - Tests for ping/pong and status
  - Tests for reconnection logic (simulate dropped connections, network errors, etc.)
  - Tests for error propagation (ensure errors from the wrapper/adapter are surfaced to the client)
  - Tests for ownership transfer between processes
  - All tests pass reliably in CI
- **Priority**: P0
- **Effort**: 2
- **Dependencies**: T3.1
- **Status**: TODO

### T5.3

- **Name**: Telemetry and metrics integration for connection events
- **Description**: Integrate Telemetry events for all major connection lifecycle events (connect, disconnect, send, receive, error, reconnect, etc.) and ensure metrics can be collected by Prometheus/StatsD. Document event names and payloads.
- **Acceptance Criteria**:
  - Telemetry events are emitted for all major lifecycle events
  - Metrics can be collected by Prometheus/StatsD
  - Documentation of event names and payloads is up to date
- **Priority**: P1
- **Effort**: 1
- **Dependencies**: T3.2
- **Status**: TODO

### T5.4

- **Name**: Supervision tree and OTP best practices audit
- **Description**: Review and update the supervision tree to ensure it follows OTP best practices, including restart strategies, graceful shutdown, and dynamic supervision if needed. Document the supervision tree.
- **Acceptance Criteria**:
  - Supervision tree follows OTP best practices
  - All critical processes are supervised
  - Graceful shutdown is implemented
  - Supervision tree is documented
- **Priority**: P1
- **Effort**: 1
- **Dependencies**: T3.2
- **Status**: TODO

## Phase 6: Platform Integration

### T6.1

- **Name**: Create platform adapter template tests
- **Description**: Test cases for the platform adapter base module
- **Acceptance Criteria**:
  - Tests for common adapter functionality
  - Tests for behavior implementations
  - Tests for configuration handling
- **Priority**: P1
- **Effort**: 0.5
- **Dependencies**: T3.4, T4.4
- **Status**: DONE

### T6.2

- **Name**: Create platform adapter template
- **Description**: Base module for platform-specific adapters
- **Acceptance Criteria**:
  - Common adapter functionality
  - Behavior implementations
  - Configuration handling
  - All tests passing
- **Priority**: P1
- **Effort**: 1
- **Dependencies**: T6.1
- **Status**: DONE

### T6.2.1

- **Name**: Create Echo adapter as reference implementation
- **Description**: Implement a simple Echo adapter as a reference implementation
- **Acceptance Criteria**:
  - Echo adapter implementing PlatformAdapter behavior
  - Tests for the Echo adapter
  - Documentation explaining the adapter with examples
  - Simple echo server for integration tests
- **Priority**: P1
- **Effort**: 0.5
- **Dependencies**: T6.2
- **Status**: DONE

### T6.2.2

- **Name**: Implement process-based connection wrapper for Echo adapter
- **Description**: Create a GenServer (or similar process) that wraps the Echo adapter, providing a `start_link/1` function, message routing, and process monitoring. This ensures the Echo adapter can be started, supervised, and tested in the same way as Gun-based connections.
- **Acceptance Criteria**:
  - Echo adapter can be started with `WebsockexNova.Connection.start_link/1` (or equivalent)
  - The process supports monitoring and clean shutdown
  - Messages sent to the connection process are routed to the Echo adapter and replies are routed back
  - Integration tests for the Echo adapter pass
  - Documentation updated to reflect the process-based usage pattern
- **Priority**: P0
- **Effort**: 1
- **Dependencies**: T6.2.1
- **Status**: DONE

### T6.3

- **Name**: Create Deribit adapter tests
- **Description**: Test cases for Deribit platform adapter
- **Acceptance Criteria**:
  - Tests for Deribit-specific message handling
  - Tests for Deribit authentication
  - Tests for Deribit subscriptions
  - Tests for error handling
- **Priority**: P1
- **Effort**: 1.5
- **Dependencies**: T6.2, T4.10
- **Status**: TODO

### T6.4

- **Name**: Implement Deribit platform adapter
- **Description**: Create adapter for the Deribit exchange
- **Acceptance Criteria**:
  - Deribit-specific auth implementation
  - Message handling for Deribit formats
  - Subscription management for Deribit channels
  - Error handling for Deribit errors
  - All tests passing
- **Priority**: P1
- **Effort**: 3
- **Dependencies**: T6.3
- **Status**: TODO

⚠️ What to Watch For with T6.4 (Deribit Adapter)
Adapter contract:
The Deribit adapter will need to implement real logic for authentication, subscription, message handling, etc.
You'll want to override the inert handlers in the connection process for these features.
Tests:
You'll need new tests for Deribit-specific flows (auth, subscribe, etc.).
Use the Echo adapter tests as a template for echoing, but add richer tests for Deribit's protocol.
Client API:
The generic client API is ready, but you may want to add Deribit-specific helpers (e.g., for signing requests, handling Deribit's unique message formats).
Docs:
Add Deribit-specific usage examples to the guides as you implement.

### T6.4.1

- **Name**: Refactor Connection Process for Testability, Modularity, and Robust Lifecycle Management (TDD)
- **Description**: Refactor `lib/websockex_nova/connection.ex` to improve testability, maintainability, and clarity, while preserving robust, production-grade WebSocket lifecycle management. **This refactor must be performed using Test-Driven Development (TDD): write failing tests for all new modules and refactored logic before implementation, and use tests to drive the design.**

#### **Update: Reconnection Logic Findings**

- The codebase already provides a decoupled, shared reconnection logic layer in `WebsockexNova.Transport.Reconnection` and its strategy modules (`LinearBackoff`, `ExponentialBackoff`, `JitteredBackoff`).
- Both the main connection process (`WebsockexNova.Connection.State`) and the Gun connection wrapper (`WebsockexNova.Gun.ConnectionState`) are intentionally different and serve different layers, but both can use the shared reconnection strategies directly, without coupling or translation of state structs.
- **State management is handled by dedicated helpers:** `WebsockexNova.Helpers.StateHelpers` and `WebsockexNova.Gun.Helpers.StateHelpers` provide state mutation and access functions for their respective layers. This separation is intentional and supports modularity, testability, and clear boundaries between connection orchestration and transport details.
- **Reconnection logic is shared, not duplicated:** Both state helpers should focus on state mutation and access, not on reconnection strategy, which is handled by the shared `WebsockexNova.Transport.Reconnection` module.
- This approach avoids code duplication, keeps reconnection logic stateless and testable, and allows each process to use only the fields it needs (e.g., `:reconnect_attempts`, config options).
- **Recommendation:** Future refactors should continue to use this shared module for all backoff/jitter/retry logic, and avoid duplicating reconnection logic or coupling state unnecessarily. If new reconnection strategies are needed, they should be added to the shared module.
- **Performance & Maintainability:** This design is both performant (no extra process/message overhead, no state translation) and highly maintainable (single source of truth for reconnection logic, easy to test and extend).
- **Validation:** This finding validates the current architecture and supports the TDD/testability goals of the refactor. No major state unification is needed; focus should remain on modularity, delegation, and leveraging the shared reconnection logic.

#### **TDD Red/Green Cycles for Each Module**

**Order:**

1. StateHelpers
2. HandlerInvoker
3. Transport Behaviour
4. ConnectionTestHelper
5. Refactor GenServer callbacks

---

#### 1. StateHelpers [x]

- **Red:** Write failing unit tests for:
  - `pop_pending_request/2` (removes a pending request by id, returns {from, new_pending, new_timeouts})
  - `buffer_request/4` (adds a request to the buffer)
  - `flush_buffer/2` (moves buffered requests to pending, returns new state)
  - `cancel_timeout/2` (removes and cancels a timeout by id)
- **Green:** Implement minimal functions to make tests pass.
- **Example Test Cases:**
  - Pops the correct request and updates state
  - Buffers a request and returns updated buffer
  - Flushes buffer and sets timeouts
  - Cancels a timeout and updates state

**Note:**
StateHelpers modules should focus on state mutation, buffering, and correlation logic only.
All reconnection/backoff logic should be delegated to the shared `WebsockexNova.Transport.Reconnection` module, not implemented in state helpers.

#### 2. HandlerInvoker

- **Red:** Write failing unit tests for:
  - `invoke/3` (dispatches to the correct handler and returns the result)
  - Handles all handler types (connection, message, subscription, auth, error, etc.)
- **Green:** Implement dispatcher logic to make tests pass.
- **Example Test Cases:**
  - Invokes the correct handler for a message event
  - Handles missing/optional handlers gracefully

#### 3. Transport Behaviour

- **Red:** Write failing tests for:
  - `send_frame/3`, `upgrade_to_websocket/3`, etc. (ensure the behaviour is enforced)
  - Mock transport in a test and assert calls are routed correctly
- **Green:** Define the behaviour and provide a mock implementation for tests.
- **Example Test Cases:**
  - Calls to transport functions are routed to the mock
  - Errors in transport are handled as expected

#### 4. ConnectionTestHelper

- **Red:** Write failing tests for:
  - `start_connection_in_state/2` (starts a connection in a given state)
  - `simulate_event/2` (simulates a Gun or platform event)
  - `assert_state_transition/3` (asserts state changes after an event)
- **Green:** Implement helpers to make tests pass.
- **Example Test Cases:**
  - Can start a connection in :connected, :disconnected, etc.
  - Can simulate a :gun_down event and assert the correct state

#### 5. Refactor GenServer callbacks

- **Red:** Write integration tests that expect the GenServer to delegate to the new modules (using Mox/mocks as needed).
- **Green:** Refactor callbacks to use the new modules, make tests pass.
- **Example Test Cases:**
  - GenServer delegates state transitions to StateHelpers
  - GenServer delegates handler calls to HandlerInvoker
  - GenServer uses injected Transport

---

- **Acceptance Criteria**:
  - [ ] All new modules and refactored logic are developed using TDD: failing tests are written first, and tests drive the design and implementation.
  - [ ] All state transition, buffer, and correlation logic is moved to `StateHelpers` and covered by unit tests.
  - [ ] Handler invocation is modularized in `HandlerInvoker` and can be tested in isolation.
  - [ ] Transport layer is abstracted and can be mocked in tests; production code uses Gun/ConnectionWrapper.
  - [ ] Test mode supports injection of mocks/fakes and provides helpers for simulating events.
  - [ ] GenServer callbacks in `connection.ex` are thin and delegate to pure/stateless modules.
  - [ ] `ConnectionTestHelper` provides ergonomic helpers for test setup and assertions.
  - [ ] Typespecs and documentation are present for all new modules and functions.
  - [ ] Unit and integration tests cover all lifecycle, error, reconnection, and recovery flows, with high coverage and minimal reliance on process state manipulation.
- **Priority**: P0
- **Effort**: 2
- **Dependencies**: T6.4
- **Status**: TODO
- **Notes**: This refactor is foundational for all platform adapters and is required for robust, production-ready operation. Reference the Gun integration guide and all relevant behaviors for implementation details. See also the architecture and behavior customization guides for best practices.

#### **Plug/Router Test Infrastructure Note**

- The project already uses Plug and Plug.Router in the test infrastructure (see `test/support/mock_websock_server/router.ex`).
- This enables:
  - Injection of test-specific state or mocks into the connection via assigns or custom plugs.
  - Easy extension of the router with new test endpoints or behaviors.
  - Simulation of authentication, rate limiting, error injection, or network scenarios by adding plugs.
  - Use of assigns to pass test context or control flags to handlers.
  - Addition of endpoints for test control (e.g., `/test/trigger_error`, `/test/set_state`).
  - Realistic, production-like test infrastructure, mirroring Phoenix/Plug usage in production.
- **Suggestions for future use:**
  - Add custom plugs to simulate complex scenarios or inject dependencies for integration tests.
  - Use plugs to inject mock transports, handlers, or state into the connection process for end-to-end or integration tests.
  - Extend the router to provide test hooks or control endpoints as needed.

Keep this in mind when designing new tests or integration scenarios, as it provides a flexible and idiomatic foundation for advanced testability and modularity.

### T6.5

- **Name**: Create platform adapter macro tests
- **Description**: Test cases for platform adapter macros
- **Acceptance Criteria**:
  - Tests for macro expansion
  - Tests for generated code
  - Tests for configuration options
- **Priority**: P2
- **Effort**: 0.5
- **Dependencies**: T6.2
- **Status**: TODO

### T6.6

- **Name**: Create using macros for platform adapters
- **Description**: Create macros to simplify adapter creation
- **Acceptance Criteria**:
  - **using** macro for adapters
  - Configuration options in macro
  - Generated code for common tasks
  - All tests passing
- **Priority**: P2
- **Effort**: 1.5
- **Dependencies**: T6.5
- **Status**: TODO

### T6.7

- **Name**: Create platform client template tests
- **Description**: Test cases for platform-specific clients
- **Acceptance Criteria**:
  - Tests for client initialization
  - Tests for client API
  - Tests for configuration
- **Priority**: P2
- **Effort**: 0.5
- **Dependencies**: T6.2
- **Status**: TODO

### T6.8

- **Name**: Create platform-specific client templates
- **Description**: Templates for building platform-specific clients
- **Acceptance Criteria**:
  - Client template module
  - API conventions
  - Configuration handling
  - All tests passing
- **Priority**: P2
- **Effort**: 1.5
- **Dependencies**: T5.7
- **Status**: TODO

## Phase 7: Testing Infrastructure & Documentation

### T7.1

- **Name**: Create module documentation tests
- **Description**: Tests that verify documentation completeness
- **Acceptance Criteria**:
  - Tests for moduledoc presence
  - Tests for function documentation
  - Tests for typespecs
- **Priority**: P1
- **Effort**: 0.5
- **Dependencies**: None
- **Status**: TODO

### T7.2

- **Name**: Create API documentation
- **Description**: Comprehensive documentation for public API
- **Acceptance Criteria**:
  - Module documentation
  - Function documentation
  - Type specifications
  - Examples
  - All doc tests passing
  - **Client API (`WebsockexNova.Client`) is documented as the primary interface for users, with examples for all major functions.**
- **Priority**: P1
- **Effort**: 2
- **Dependencies**: T7.1, T3.4, T4.4, T4.10
- **Status**: TODO

### T7.3

- **Name**: Implement test coverage reporting
- **Description**: Add tools for measuring test coverage
- **Acceptance Criteria**:
  - ExCoveralls integration
  - Coverage targets (>80%)
  - CI integration
- **Priority**: P2
- **Effort**: 0.5
- **Dependencies**: None
- **Status**: TODO

### T7.4

- **Name**: Create example usage guides
- **Description**: Create comprehensive guides with examples
- **Acceptance Criteria**:
  - Basic usage guide
  - Platform integration guide
  - Authentication guide
  - Advanced features guide
  - **All guides use `WebsockexNova.Client` as the recommended interface for sending messages, subscribing, authenticating, etc.**
- **Priority**: P2
- **Effort**: 2
- **Dependencies**: T6.4
- **Status**: TODO

### T7.5

- **Name**: Ensure CI, Static Analysis, and Code Quality Tooling
- **Description**: Integrate and maintain CI workflows and static analysis tools to ensure code quality and reliability.
- **Acceptance Criteria**:
  - GitHub Actions workflows for CI, static analysis, and test coverage are present and up to date
  - Tools: Credo, Dialyzer, Sobelow, ExCoveralls (if not present, add and configure)
  - CI pipeline runs on all pushes and PRs, fails on warnings or low coverage
  - Documentation in README and/or docs/guides/ci_cd.md for running and interpreting these tools
  - Minimum coverage and code quality thresholds are enforced
- **Priority**: P4
- **Effort**: 1
- **Dependencies**: None
- **Status**: TODO

### T7.6

- **Name**: Implement ergonomic client API
- **Description**: Provide a user-friendly, documented API for interacting with platform adapter connections. This module should encapsulate the internal message protocol and expose clear, well-documented functions for common operations such as sending messages, subscribing, authenticating, and querying connection status. The API should be adapter-agnostic and extensible, serving as the primary interface for end users.
- **Acceptance Criteria**:
  - `WebsockexNova.Client` module is implemented with the following functions (at minimum):
    - `send_text/2,3` — Send a text message and receive a reply or timeout.
    - `send_json/2,3` — Send a map as JSON and receive a reply or timeout.
    - `subscribe/3,4` — Subscribe to a channel/topic (if supported by the adapter).
    - `unsubscribe/2,3` — Unsubscribe from a channel/topic (if supported).
    - `authenticate/2,3` — Send authentication data (if supported).
    - `ping/1,2` — Send a ping frame (if supported).
    - `status/1,2` — Query connection status (if supported).
    - `send_raw/2,3` — Send a raw message for advanced use.
    - Async/cast variants for fire-and-forget operations (optional).
  - All functions are documented with typespecs and usage examples.
  - Comprehensive tests for all client API functions.
  - Guides and documentation are updated to recommend the client API as the primary interface for users.
- **Priority**: P1
- **Effort**: 1
- **Dependencies**: T6.2.2 (process-based connection wrapper), T4.4 (subscription management), T4.10 (authentication flow)
- **Status**: DONE

## Phase 8: Advanced Features

### T8.1

- **Name**: Create CodecHandler behavior tests
- **Description**: Test cases for codec handling
- **Acceptance Criteria**:
  - Tests for encoding/decoding
  - Tests for different formats (JSON, Protobuf, MsgPack)
  - Tests for binary data
- **Priority**: P3
- **Effort**: 0.5
- **Dependencies**: T3.4
- **Status**: TODO

### T8.2

- **Name**: Add binary protocol support (CodecHandler)
- **Description**: Create pluggable codec system for different formats
- **Acceptance Criteria**:
  - CodecHandler behavior
  - JSON codec implementation
  - Binary codec implementation
  - Pluggable codec architecture
  - All tests passing
- **Priority**: P3
- **Effort**: 2
- **Dependencies**: T8.1
- **Status**: TODO

### T8.3

- **Name**: Create backpressure mechanism tests
- **Description**: Test cases for flow control
- **Acceptance Criteria**:
  - Tests for buffer limits
  - Tests for backpressure signals
  - Tests for overflow strategies
- **Priority**: P3
- **Effort**: 1
- **Dependencies**: T3.4
- **Status**: TODO

### T8.4

- **Name**: Implement backpressure mechanisms
- **Description**: Create flow control for high-volume streams
- **Acceptance Criteria**:
  - Buffer size management
  - Backpressure signaling
  - Overflow strategies (drop, block)
  - All tests passing
- **Priority**: P3
- **Effort**: 2.5
- **Dependencies**: T8.3
- **Status**: TODO

### T8.5

- **Name**: Create dynamic configuration tests
- **Description**: Test cases for runtime configuration
- **Acceptance Criteria**:
  - Tests for config updates
  - Tests for hot reloading
  - Tests for persistence
- **Priority**: P3
- **Effort**: 0.5
- **Dependencies**: T3.4
- **Status**: TODO

### T8.6

- **Name**: Add dynamic configuration support
- **Description**: Create system for runtime configuration changes
- **Acceptance Criteria**:
  - Runtime config updates
  - Hot reload capability
  - Config persistence options
  - All tests passing
- **Priority**: P3
- **Effort**: 2
- **Dependencies**: T8.5
- **Status**: TODO

### T8.7

- **Name**: Security Hardening & Secret Management
- **Description**: Implement advanced security features including credential rotation, integration with Vault/Secrets Manager, audit logging for sensitive actions, and TLS configuration validation.
- **Acceptance Criteria**:
  - Support for credential rotation and refresh
  - Integration with Vault or other secret managers
  - Audit logging for authentication and sensitive operations
  - TLS configuration validation and enforcement
  - All tests passing
- **Priority**: P2
- **Effort**: 2
- **Dependencies**: None
- **Status**: TODO

### T8.8

- **Name**: Operational Observability & Alerting
- **Description**: Add operational features for production readiness, including alerting integration, health check endpoints, and runbook documentation.
- **Acceptance Criteria**:
  - Prometheus/Sentry alerting integration
  - Health check endpoints for platform adapters/clients
  - Runbook documentation for common operational issues
  - All tests passing
- **Priority**: P3
- **Effort**: 1
- **Dependencies**: None
- **Status**: TODO

### T8.9

- **Name**: Clustering & Distributed State
- **Description**: Implement distributed subscription state, distributed rate limiting, and node failover/handoff for high-availability deployments.
- **Acceptance Criteria**:
  - Distributed subscription state synchronization
  - Distributed rate limiting coordination
  - Node failover and handoff support
  - All tests passing
- **Priority**: P3
- **Effort**: 3
- **Dependencies**: None
- **Status**: TODO

### T8.10

- **Name**: Performance & Load Testing
- **Description**: Add performance and load testing infrastructure, including benchmarking, stress testing, and profiling.
- **Acceptance Criteria**:
  - Benchmarking tools and scripts
  - Stress tests for reconnection, subscription churn, etc.
  - Profiling and tuning documentation
  - All tests passing
- **Priority**: P3
- **Effort**: 1
- **Dependencies**: None
- **Status**: TODO

### T8.11

- **Name**: Compliance & Legal Readiness
- **Description**: Add features and documentation for compliance (e.g., GDPR, audit trails, data retention).
- **Acceptance Criteria**:
  - Data retention and deletion support
  - Audit trails for sensitive actions
  - Compliance documentation
  - All tests passing
- **Priority**: P4
- **Effort**: 1
- **Dependencies**: None
- **Status**: TODO
