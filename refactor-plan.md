# WebsockexNova State Refactor Plan

## Goal

Make `ClientConn` the single source of truth for all connection state, regardless of transport (Gun, Mint, etc.), and ensure all stateful operations (including handler state) are managed through it. This enables true transport abstraction, simplifies handler/state management, and improves testability.

---

## Refactor Steps (with Test Instructions)

### 1. Core State Structs and Helpers

- [ ] Refactor `lib/websockex_nova/client_conn.ex`:
  - [ ] Ensure all fields from legacy states are present.
  - [ ] Add/adjust namespaced handler state fields.
  - [ ] Update typespecs and documentation.
- [ ] Refactor `lib/websockex_nova/helpers/state_helpers.ex`:
  - [ ] Update helpers to operate on `ClientConn`.
  - [ ] Remove/adapt helpers expecting legacy state structs.
- [ ] **Test:** Add/adjust unit tests for `ClientConn` and all state helpers. All tests must pass before proceeding.

### 2. Define and Enforce Shared Behaviors

- [ ] Ensure WebsockexNova.Transport behavior is up-to-date and complete
- [ ] Define ConnectionManagerBehaviour (generic connection manager behavior)
- [ ] Update documentation for both behaviors
- [ ] Test: add behavior compliance tests/mocks

### 3. Implement Behaviors in Transports

- [ ] Refactor Gun modules to implement WebsockexNova.Transport and ConnectionManagerBehaviour
- [ ] Refactor Mint modules (or add) to implement WebsockexNova.Transport and ConnectionManagerBehaviour
- [ ] Test: transport and connection manager compliance for Gun and Mint

### 4. Remove/Deprecate Legacy State Modules

- [ ] Remove or stub out:
  - [ ] `lib/websockex_nova/gun/connection_state.ex`
  - [ ] `lib/websockex_nova/connection/state.ex`
- [ ] **Test:** Remove or rewrite any tests using these legacy structs. All tests must pass before proceeding.

### 5. Refactor Handler Modules

- [ ] Update all handler modules to use namespaced state in `ClientConn`:
  - [ ] `lib/websockex_nova/defaults/` (e.g., `default_connection_handler.ex`, `default_auth_handler.ex`, etc.)
  - [ ] Any custom/user-defined handlers
- [ ] **Test:** Refactor handler tests to use `ClientConn` and test state namespacing. All tests must pass before proceeding.

### 6. Refactor Client API

- [ ] Update the main client API to use only `ClientConn` and new transport/handler logic:
  - [ ] `lib/websockex_nova/client.ex`
- [ ] **Test:** Refactor all client API and integration/property-based tests. All tests must pass before proceeding.

### 7. Refactor Manager/Wrapper Modules

- [ ] Refactor or remove any manager/wrapper modules that maintain their own state:
  - [ ] `lib/websockex_nova/gun/connection_manager.ex`
  - [ ] `lib/websockex_nova/gun/connection_wrapper.ex` (if not already done)
  - [ ] Any other wrappers
- [ ] **Test:** Refactor or remove related tests. All tests must pass before proceeding.

### 8. Refactor Adapters, Examples, and Platform Integrations

- [ ] Update any adapters or example clients to use the new state model:
  - [ ] `lib/websockex_nova/examples/`
  - [ ] `lib/websockex_nova/platform/`
  - [ ] Any custom adapters
- [ ] **Test:** Refactor or add integration tests for adapters and examples. All tests must pass before proceeding.

### 9. Final Cleanup

- [ ] Remove any remaining references to legacy state.
- [ ] Update documentation and guides.
- [ ] **Test:** Run the full test suite and property-based tests. All tests must pass before considering the refactor complete.

---

## Machine-Readable Task List

- [ ] core_state_structs_and_helpers
  - [ ] refactor_client_conn
  - [ ] refactor_state_helpers
  - [ ] test_client_conn_and_helpers
- [ ] define_and_enforce_shared_behaviors
  - [ ] ensure WebsockexNova.Transport behavior is up-to-date and complete
  - [ ] define ConnectionManagerBehaviour (generic connection manager behavior)
  - [ ] update documentation for both behaviors
  - [ ] test: add behavior compliance tests/mocks
- [ ] implement_behaviors_in_transports
  - [ ] refactor Gun modules to implement WebsockexNova.Transport and ConnectionManagerBehaviour
  - [ ] refactor Mint modules (or add) to implement WebsockexNova.Transport and ConnectionManagerBehaviour
  - [ ] test: transport and connection manager compliance for Gun and Mint
- [ ] remove_legacy_state_modules
  - [ ] remove_gun_connection_state
  - [ ] remove_connection_state
  - [ ] test_no_legacy_state_usage
- [ ] refactor_handler_modules
  - [ ] refactor_default_handlers (ensure transport-agnostic)
  - [ ] refactor_custom_handlers (ensure transport-agnostic)
  - [ ] test_handler_modules
- [ ] refactor_client_api
  - [ ] refactor_client_ex (use only behaviors and ClientConn)
  - [ ] test_client_api
- [ ] refactor_manager_wrapper_modules
  - [ ] refactor_connection_manager_state_machine
    - [ ] Ensure only ClientConn is persistent state
    - [ ] Move all ephemeral/process-local state (monitors, timers, etc.) to GenServer state
    - [ ] Drive state transitions via ClientConn.status or dedicated state field
    - [ ] Delegate all handler logic via ClientConn
    - [ ] Make state machine logic easily testable
    - [ ] Document responsibilities and best practices inline
  - [ ] refactor_connection_manager
  - [ ] refactor_connection_wrapper
  - [ ] refactor_other_wrappers
  - [ ] test_manager_wrapper_modules
- [ ] refactor_adapters_examples_platform
  - [ ] refactor_examples
  - [ ] refactor_platform
  - [ ] refactor_custom_adapters
  - [ ] test_adapters_examples_platform
- [ ] final_cleanup
  - [ ] remove_remaining_legacy_references
  - [ ] update_docs_and_guides
  - [ ] test_full_suite

---

## Summary Table

| Step | Module(s) / Directory                                                | Test Focus                        |
| ---- | -------------------------------------------------------------------- | --------------------------------- |
| 1    | `client_conn.ex`, `helpers/state_helpers.ex`                         | Unit tests for state/helpers      |
| 2    | `gun/connection_state.ex`, `connection/state.ex`                     | Remove/replace legacy state tests |
| 3    | `gun/connection_wrapper.ex`, `gun/connection_manager.ex`, transports | Transport tests                   |
| 4    | `defaults/`, handlers                                                | Handler state tests               |
| 5    | `client.ex`                                                          | Client API/integration tests      |
| 6    | `gun/connection_manager.ex`, wrappers                                | Manager/wrapper tests             |
| 7    | `examples/`, `platform/`, adapters                                   | Adapter/integration tests         |
| 8    | Cleanup, docs, guides                                                | Full test suite                   |

---

## Instructions

- Complete each step in order. Do not proceed to the next step until all tests for the current step pass.
- Refactor both the module and its tests together.
- Use `ClientConn` as the canonical state everywhere.
- Remove all legacy state structs and helpers.
- Ensure all handler and transport modules operate on `ClientConn`.
- Keep ephemeral/process-local state (monitors, timers, etc.) only in GenServer state, not in `ClientConn`.
- Update documentation and guides to reflect the new state model.
- Run the full test suite after each major step.
- The refactor is complete only when all tests pass and no legacy state remains.

---

## Architectural Placement: Connection Manager as State Machine

The connection manager remains a process-based state machine, but in the new architecture, it is a thin orchestrator whose only persistent state is the canonical `ClientConn` struct. All connection/session state transitions are explicit and testable, and all ephemeral/process-local state (monitors, timers, etc.) is kept out of `ClientConn` and only in the GenServer state.

### Responsibilities

- Orchestrate the connection lifecycle: establish, maintain, close, and reconnect connections
- Handle reconnection logic, backoff, and error recovery
- Manage transitions between connection states (e.g., connecting, connected, reconnecting, disconnected, closed)
- Delegate stateful operations to handler modules, always passing and updating `ClientConn`

### State Ownership

- **Persistent state:** Only `ClientConn` (all connection/session state)
- **Ephemeral/process-local state:** Monitors, timers, references, etc. (kept in GenServer state, never in `ClientConn`)

### Structure

- Module: `WebsockexNova.Gun.ConnectionManager` (or generic `Transport.ConnectionManager`)
- State example:
  ```elixir
  %{
    client_conn: %ClientConn{},   # Canonical connection/session state
    monitor_ref: reference(),     # Ephemeral/process-local
    timer_ref: reference(),       # Ephemeral/process-local
    # ... any other process-local fields
  }
  ```
- State machine logic is driven by pattern matching on `ClientConn.status` or a dedicated state field.

### Best Practices

- All connection/session state is in `ClientConn`.
- No parallel state: connection manager does not maintain any state outside of `ClientConn` except for ephemeral/process-local data.
- All state transitions result in a new `ClientConn` struct.
- The state machine logic should be easily testable by passing in and asserting on `ClientConn` transitions.

---
