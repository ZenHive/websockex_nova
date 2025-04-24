# WebsockexNova State Refactor Plan

## Goal

Make `ClientConn` the single source of truth for all connection state, regardless of transport (Gun, Mint, etc.), and ensure all stateful operations (including handler state) are managed through it. This will enable true transport abstraction and simplify handler/state management.

---

## Steps

### 1. Unify State

- [ ] **Migrate all transport-specific state structs to `ClientConn`**
  - [ ] Map all fields from `Gun.ConnectionState` to `ClientConn`:
    - [ ] Add `:transport_pid` (was `gun_pid`)
    - [ ] Add `:stream_ref` (was `ws_stream_ref`)
    - [ ] Add `:status` (connection status)
    - [ ] Add `:active_streams` (if needed for all transports)
    - [ ] Merge `:host`, `:port`, `:path`, `:ws_opts`, `:transport` into `:connection_info` or top-level fields
    - [ ] Merge `:options` into `:connection_info` or `:extras`
    - [ ] Add/merge handler modules and states into namespaced handler fields (e.g., `:connection_handler_settings`)
    - [ ] Add/merge any other relevant fields
  - [ ] Map all fields from `Connection.State` to `ClientConn`:
    - [ ] Add/merge `:adapter`, `:adapter_state`
    - [ ] Add/merge handler modules and states
    - [ ] Add/merge `:reconnect_attempts`, `:backoff_state` (to `:reconnection` map)
    - [ ] Add/merge `:config` (to `:connection_info` or `:extras`)
    - [ ] Add/merge buffers if needed (to `:extras` or keep ephemeral)
- [ ] **Identify and keep ephemeral/process-local state in GenServer state only**
  - [ ] `:gun_monitor_ref`, `:wrapper_pid`, timers, and references remain process-local
- [ ] **Update all code to use `ClientConn` as the canonical state**
  - [ ] Refactor all modules/functions that create or manipulate `Gun.ConnectionState` or `Connection.State` to use `ClientConn`
  - [ ] Refactor handler state logic to use namespaced fields in `ClientConn`
- [ ] **Remove or deprecate legacy state structs and helpers**
  - [ ] Remove `Gun.ConnectionState` and `Connection.State` modules
  - [ ] Remove or refactor helpers that expect legacy state structs
- [ ] **Update tests to use unified state model**
  - [ ] Refactor or rewrite tests that use legacy state structs

### 2. Transport API

- Ensure all transport modules (Gun, Mint, etc.) implement the same behaviour and only accept/return `ClientConn`.
- Remove any direct use of transport-specific state in public APIs.

### 3. Handler State

- All default handler modules (connection, auth, error, logging, metrics, message, rate limit, subscription) are already using `ClientConn` as their canonical state. No changes needed for default handlers.

### 4. Client API

- `WebsockexNova.Client` should only ever work with `ClientConn`.
- All calls to the transport layer should pass the `ClientConn` struct.

### 5. Manager/Wrapper

- Refactor or remove `connection_manager`, `connection_wrapper`, etc., so they do not maintain their own state.
- They should act as pure functions or GenServers that operate on and return `ClientConn`.

### 6. Legacy State

- Remove or migrate any use of `WebsockexNova.Connection.State` and helpers to use `ClientConn`.

### 7. Testing/Compatibility

- Ensure all tests and adapters use the new unified state model.
- Provide migration helpers if needed.

---

## Machine-Readable Task List

### unify_state

- [ ] migrate_gun_connection_state_fields_to_client_conn
- [ ] migrate_connection_state_fields_to_client_conn
- [ ] migrate_handler_state_to_client_conn
- [ ] keep_ephemeral_state_process_local
- [ ] refactor_code_to_use_client_conn_everywhere
- [ ] remove_legacy_state_structs_and_helpers
- [ ] update_tests_for_unified_state

---

## Modules to Refactor/Touch

- `lib/websockex_nova/gun/connection_manager.ex`
- `lib/websockex_nova/gun/connection_wrapper.ex`
- `lib/websockex_nova/gun/connection_state.ex`
- `lib/websockex_nova/client.ex`
- `lib/websockex_nova/client_conn.ex`
- `lib/websockex_nova/connection/state.ex`
- `lib/websockex_nova/helpers/state_helpers.ex`
- Any other transport or handler modules that manipulate state.

---

## Notes

- All state transitions, handler updates, and connection metadata should be reflected in `ClientConn`.
- Transport modules should be stateless or only keep minimal process state, delegating all connection/session state to `ClientConn`.
- This refactor will make it easier to add new transports and to reason about connection state across the codebase.
