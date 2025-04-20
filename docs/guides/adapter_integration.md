# Writing Platform Adapters for WebsockexNova

This guide explains how to implement a platform adapter that works seamlessly with the process-based connection wrapper (`WebsockexNova.Connection`). It also clarifies the distinction between behaviors and default implementations, and provides a step-by-step template for adapter development and integration testing.

---

## 1. Architecture: Behaviors vs. Defaults

WebsockexNova is designed for composability and extensibility. It separates concerns using **behaviors** (contracts) and **default implementations** (sensible, overridable modules):

- **Behaviors** (in `lib/websockex_nova/behaviors/`) define the required callbacks for connection, message, error, subscription, authentication, rate limiting, logging, and metrics handling. Behaviors do **not** provide any default logic.
- **Defaults** (in `lib/websockex_nova/defaults/`) provide full, overridable implementations for each behavior. You can use these as-is, or override only the callbacks you need to customize.

**Best Practice:** Compose your adapter by using or extending the default handlers, and override only what is platform-specific.

---

## 2. Writing a Platform Adapter: Step-by-Step

### Step 1: Use the Platform Adapter Macro

Start your adapter module with the `WebsockexNova.Platform.Adapter` macro. This sets up the contract and default config for your platform:

```elixir
defmodule MyApp.PlatformAdapters.Deribit do
  use WebsockexNova.Platform.Adapter,
    default_host: "wss://www.deribit.com/ws/api/v2",
    default_port: 443

  # ...implement required callbacks below
end
```

### Step 2: Compose with Default Handlers

You can use or extend the default handler modules for connection, message, error, subscription, authentication, rate limiting, logging, and metrics. For example:

```elixir
defmodule MyApp.DeribitConnectionHandler do
  use WebsockexNova.Defaults.DefaultConnectionHandler
  # Override only what you need:
  def handle_connect(conn_info, state) do
    # Custom Deribit handshake logic
    {:reply, :text, "{\"jsonrpc\":\"2.0\",...}", state}
  end
end

defmodule MyApp.DeribitMessageHandler do
  use WebsockexNova.Defaults.DefaultMessageHandler
  # Override message_type/1, handle_message/2, etc. as needed
end
```

You can do the same for error, subscription, auth, rate limit, logging, and metrics handlers.

### Step 3: Implement Platform-Specific Logic

Implement the required callbacks for your platform adapter (see `WebsockexNova.Platform.Adapter` docs):

- `init/1`
- `handle_platform_message/2`
- `encode_auth_request/1`
- `encode_subscription_request/2`
- `encode_unsubscription_request/1`

Example:

```elixir
@impl true
def handle_platform_message(%{"method" => "heartbeat"}, state) do
  {:noreply, state}
end

@impl true
def encode_auth_request(credentials) do
  {:text, Jason.encode!(%{"jsonrpc" => "2.0", ...})}
end
# ...and so on
```

### Step 4: Start a Connection with Your Adapter

```elixir
{:ok, pid} = WebsockexNova.Connection.start_link(
  adapter: MyApp.PlatformAdapters.Deribit,
  connection_handler: MyApp.DeribitConnectionHandler,
  message_handler: MyApp.DeribitMessageHandler,
  # ...other handlers as needed
  credentials: %{api_key: "...", secret: "..."}
)
```

### Step 5: Interact via the Client API

**Always use the `WebsockexNova.Client` module as the primary interface for interacting with your connection:**

```elixir
WebsockexNova.Client.send_text(pid, "Hello")
WebsockexNova.Client.send_json(pid, %{foo: "bar"})
WebsockexNova.Client.subscribe(pid, "ticker.BTC-PERPETUAL.raw")
WebsockexNova.Client.authenticate(pid, %{api_key: "...", secret: "..."})
WebsockexNova.Client.ping(pid)
WebsockexNova.Client.status(pid)
```

---

## 3. Integration Test Template (Recommended)

Create a test file like `test/integration/deribit_adapter_integration_test.exs`:

```elixir
defmodule WebsockexNova.Integration.DeribitAdapterIntegrationTest do
  use ExUnit.Case, async: false
  alias WebsockexNova.Connection

  setup do
    {:ok, pid} = Connection.start_link(
      adapter: MyApp.PlatformAdapters.Deribit,
      connection_handler: MyApp.DeribitConnectionHandler,
      message_handler: MyApp.DeribitMessageHandler,
      # ...other handlers as needed
      credentials: %{api_key: "demo-key", secret: "demo-secret"}
    )
    on_exit(fn ->
      if Process.alive?(pid), do: Process.exit(pid, :kill)
    end)
    %{pid: pid}
  end

  test "echoes text messages", %{pid: pid} do
    WebsockexNova.Client.send_text(pid, "Hello")
    assert_receive {:reply, {:text, _}}, 500
  end

  # Add more tests for ping, auth, subscribe, etc.
end
```

---

## 4. Best Practices & Common Pitfalls

- **Use default handlers** as a base and override only what you need.
- **Do not implement the behaviors from scratch** unless you have a strong reason; leverage the tested defaults.
- **Always use the Client API** (`WebsockexNova.Client`) for interacting with connections.
- **Pass all required handlers and credentials** when starting a connection.
- **Test your adapter with real and mock servers** to ensure protocol compliance.
- **Consult the Echo adapter and its tests** for a minimal, working reference.

---

## 5. Summary

- **Behaviors** define contracts; **defaults** provide full, overridable implementations.
- **Compose your adapter** by using/extending defaults and implementing only platform-specific logic.
- **Start connections** with all required handlers and credentials.
- **Interact via the Client API** for safety and ergonomics.
- **Write integration tests** using the provided template.

For more details, see the Echo adapter and its integration tests as a reference implementation.
