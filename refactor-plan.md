# Refactor Plan: Single Source of Truth for State in WebsockexNova

## Goal

Refactor the codebase so that:

- **All application/session state** (e.g., `auth_status`, `access_token`, `subscriptions`, etc.) lives in a single, canonical place (the connection/client struct, e.g., `WebsockexNova.ClientConn` or a dedicated `ConnectionState`).
- **Transport modules** (e.g., Gun, Mint) only store transport-specific state (e.g., pids, stream refs).
- **Handlers** (in `lib/websockex_nova/defaults/` and elsewhere) reference and update only the canonical state, not their own copies.
- **Multiple callback PIDs** are supported for decoupled, real-time, and observable message routing.

---

## 1. Audit Current State Usage

- [ ] Identify all fields in the codebase that are mutable and may be duplicated (e.g., `auth_status`, `access_token`, `credentials`, `subscriptions`, etc.).
- [ ] List all locations where these fields are stored or updated:
  - Top-level connection/client state (`ClientConn`, `ConnectionState`)
  - Transport state (`Gun.ConnectionWrapper`, etc.)
  - Handler state (e.g., `subscription_handler_state.adapter_state`)

---

## 2. Define Canonical State Structure

- [ ] Design or update a struct (e.g., `WebsockexNova.ClientConn` or `ConnectionState`) to hold all application/session state.
- [ ] Ensure this struct is transport-agnostic and contains all fields needed for session management.
- [ ] Example:

```elixir
defmodule WebsockexNova.ClientConn do
  defstruct [
    :transport,           # e.g., WebsockexNova.Gun.ConnectionWrapper
    :transport_pid,
    :stream_ref,
    :adapter,
    :adapter_state,       # <-- All application/session state here
    :callback_pids,       # <-- Set of callback PIDs (MapSet or list)
    :connection_info
  ]
end
```

---

## 3. Support Multiple Callback PIDs

**Rationale:**

- Enables decoupled observers (UI, background jobs, metrics, tests, etc.) to receive connection events.
- Implements a simple pub/sub pattern for real-time updates and observability.
- Improves testability, fault-tolerance, and extensibility.

**Checklist:**

- [ ] Store `callback_pids` as a `MapSet` or list in the canonical connection state.
- [ ] Implement API functions to register and unregister callback PIDs:
  - `register_callback(conn, pid)`
  - `unregister_callback(conn, pid)`
- [ ] When routing messages/events, broadcast to all registered callback PIDs:
  ```elixir
  Enum.each(state.callback_pids, fn pid -> send(pid, message) end)
  ```
- [ ] Update documentation and tests to cover multi-callback scenarios.

---

## 4. Refactor Transport Modules

- [ ] Update `lib/websockex_nova/gun/connection_wrapper.ex` and any other transport modules (e.g., Mint) to only store transport-specific state:
  - Gun PID, monitor refs, stream refs, protocol details
  - **No application/session state** (e.g., no `auth_status`, `access_token`, etc.)
- [ ] Update the `WebsockexNova.Transport` behaviour to ensure all transports follow this pattern.

---

## 5. Refactor Handlers

- [ ] Update all handler modules in `lib/websockex_nova/defaults/`:
  - `default_connection_handler.ex`
  - `default_error_handler.ex`
  - `default_auth_handler.ex`
  - `default_subscription_handler.ex`
  - `default_message_handler.ex`
  - `default_metrics_collector.ex`
  - `default_rate_limit_handler.ex`
  - `default_logging_handler.ex`
- [ ] Ensure handlers receive the canonical state as an argument and do not maintain their own copies of application/session state.
- [ ] When a handler needs to update state, it should return the updated canonical state to the connection/client process.

---

## 6. Update Client and Connection Logic

- [ ] Update `lib/websockex_nova/client.ex` and any connection management modules to:
  - Always pass the canonical state to handlers and transports.
  - Store and update all application/session state in the canonical struct.
  - Only pass transport-specific state to transport modules.
  - Use the callback registration and message routing API for all event notifications.

---

## 7. Remove Duplicated State

- [ ] Remove any duplicated fields from:
  - Transport state structs
  - Handler state structs
  - Nested `adapter_state` fields in handler states
- [ ] Ensure all state transitions (e.g., after authentication, subscription, reconnection) update only the canonical state.

---

## 8. Testing and Validation

- [ ] Update or add tests to assert that state is only stored in the canonical location.
- [ ] Add tests to ensure that after any operation (auth, subscribe, reconnect, etc.), the relevant state is correct and not duplicated.
- [ ] Add tests for multiple callback PIDs (e.g., all registered PIDs receive events).

---

## 9. Documentation

- [ ] Update module and function docs to clarify where each piece of mutable state is stored and how it should be accessed/updated.
- [ ] Document the new state structure, handler/transport patterns, and callback PID registration for future contributors.

---

## 10. Optional: Migration Script

- [ ] If needed, write a script or migration function to move state from old locations to the new canonical structure during upgrade.

---

## 11. Review and Merge

- [ ] Review the refactor with the team.
- [ ] Merge changes and update any deployment or onboarding docs.

---

## References

- `lib/websockex_nova/client.ex`
- `lib/websockex_nova/gun/connection_wrapper.ex`
- `lib/websockex_nova/defaults/`
- Any other transport or handler modules
