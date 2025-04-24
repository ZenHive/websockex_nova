# Refactor Plan: Single Source of Truth for State in WebsockexNova

## Progress Summary (as of now)

- [x] DefaultAuthHandler refactored to use canonical state struct with `auth_handler_settings`
- [x] DefaultSubscriptionHandler refactored to use canonical state struct with `subscription_handler_settings`
- [x] DefaultConnectionHandler refactored to use canonical state struct with `connection_handler_settings`
- [ ] Other handlers (error, message, rate limit, logging, metrics) still pending
- [x] Tests for auth, subscription, and connection handlers updated and passing

---

## Goal

Refactor the codebase so that:

- **All application/session state** (e.g., `auth_status`, `access_token`, `subscriptions`, etc.) lives in a single, canonical place (the connection/client struct, e.g., `WebsockexNova.ClientConn` or a dedicated `ConnectionState`).
- **Handler-specific state** is stored in dedicated namespaced fields in the canonical struct (e.g., `auth_handler_settings`, `subscription_handler_settings`, `connection_handler_settings`).
- **Transport modules** (e.g., Gun, Mint) only store transport-specific state (e.g., pids, stream refs).
- **Handlers** (in `lib/websockex_nova/defaults/` and elsewhere) reference and update only the canonical state, not their own copies.
- **Multiple callback PIDs** are supported for decoupled, real-time, and observable message routing.
- **Extras** field is reserved for ad-hoc or cross-cutting data only.

---

## 1. Audit Current State Usage

- [x] Identify all fields in the codebase that are mutable and may be duplicated (e.g., `auth_status`, `access_token`, `credentials`, `subscriptions`, etc.).
- [x] List all locations where these fields are stored or updated:
  - Top-level connection/client state (`ClientConn`, `ConnectionState`)
  - Transport state (`Gun.ConnectionWrapper`, etc.)
  - Handler state (e.g., `*_handler_settings` in canonical struct)

---

## 2. Define Canonical State Structure

- [x] Design or update a struct (e.g., `WebsockexNova.ClientConn` or `ConnectionState`) to hold all application/session state.
- [x] Ensure this struct is transport-agnostic and contains all fields needed for session management, including handler-specific settings fields.
- [x] Example:

```elixir
defmodule WebsockexNova.ClientConn do
  defstruct [
    :transport,           # e.g., WebsockexNova.Gun.ConnectionWrapper
    :transport_pid,
    :stream_ref,
    :adapter,
    :adapter_state,       # Adapter-specific state
    :callback_pids,       # Set of callback PIDs (MapSet or list)
    :connection_info,
    :auth_status,
    :access_token,
    :credentials,
    :subscriptions,
    :subscription_timeout,
    :reconnect_attempts,
    :last_error,
    :auth_expires_at,
    :auth_refresh_threshold,
    :auth_error,
    :rate_limit,
    :logging,
    :metrics,
    :connection_handler_settings,      # Handler-specific state
    :auth_handler_settings,            # Handler-specific state
    :subscription_handler_settings,    # Handler-specific state
    :extras                           # Ad-hoc/cross-cutting data
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

- [x] Update all handler modules in `lib/websockex_nova/defaults/`:
  - [x] `default_auth_handler.ex`
  - [x] `default_subscription_handler.ex`
  - [x] `default_connection_handler.ex`
  - [ ] `
