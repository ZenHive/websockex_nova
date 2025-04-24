# Refactor Plan: Single Source of Truth for State in WebsockexNova

## Progress Summary (as of now)

- [x] DefaultAuthHandler refactored to use canonical state struct with `auth_handler_settings`
- [x] DefaultSubscriptionHandler refactored to use canonical state struct with `subscription_handler_settings`
- [x] DefaultConnectionHandler refactored to use canonical state struct with `connection_handler_settings`
- [x] DefaultErrorHandler refactored to use canonical state struct with `error_handler_settings`
- [x] DefaultMessageHandler refactored to use canonical state struct with `message_handler_settings`
- [x] DefaultRateLimitHandler refactored to use canonical state struct with `rate_limit` (tests updated and passing)
- [x] DefaultLoggingHandler refactored to use canonical state struct with `logging` (tests updated and passing)
- [ ] Other handlers (metrics) still pending
- [x] Tests for auth, subscription, connection, error, message, rate limit, and logging handlers updated and passing

---

## Status Summary

All major handlers (auth, subscription, connection, error, message, rate limit, logging) are now refactored to use the canonical `%WebsockexNova.ClientConn{}` struct as the single source of truth, with handler-specific state namespaced in dedicated fields. All tests for these handlers are updated and passing. Continue with the next handler (metrics) using the same conventions and process.

---

## Next Steps

- [ ] Refactor DefaultMetricsCollector to use canonical state struct with `metrics` or `metrics_collector_settings`
- [ ] Update or add tests for each handler as you go
- [ ] Review and update this plan as progress continues

---

## Prompt for New Chat

You are continuing a refactor of a Phoenix/Elixir codebase to ensure all handler and application state is stored in a single, canonical struct (`WebsockexNova.ClientConn`).

- All handler-specific state must be namespaced in dedicated fields (e.g., `*_handler_settings`) in the struct.
- All tests must use the canonical struct for state setup and assertions.
- Each handler and its tests should be refactored one at a time, following Phoenix/Elixir best practices and idioms.
- Use clear, descriptive field names and leverage pattern matching for clarity and correctness.
- Confirm each handler's tests pass before moving to the next.
- Document progress and update the refactor plan as you go.

Continue with the next handler (rate limit, logging, or metrics) using this process.

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

## 6. Refactor Client.ex
