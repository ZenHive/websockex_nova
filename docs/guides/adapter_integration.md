# Writing Platform Adapters for WebsockexNova

This guide explains how to implement a platform adapter that works seamlessly with the process-based connection wrapper (`WebsockexNova.Connection`). It also provides a template for integration tests and a proposal for an ergonomic client API.

---

## 1. Adapter Contract

To be compatible with `WebsockexNova.Connection`, your adapter module **must** implement the following contract:

### Required Functions

```elixir
def init(opts :: map()) :: {:ok, state()} | {:error, reason}

def handle_platform_message(message, state) ::
  {:reply, reply, state} |
  {:ok, state} |
  {:noreply, state} |
  {:error, error_info, state}
```

- `init/1` receives a map of options and returns `{:ok, state}`.
- `handle_platform_message/2` receives a message (usually a string or map) and the current state, and returns one of the supported tuples.

### Example Adapter Skeleton

```elixir
defmodule MyPlatform.Adapter do
  use WebsockexNova.Platform.Adapter,
    default_host: "wss://example.com",
    default_port: 443

  @impl true
  def init(opts) do
    # Initialize state from opts
    {:ok, %{opts: opts, ...}}
  end

  @impl true
  def handle_platform_message(message, state) when is_binary(message) do
    # Handle text message
    {:reply, {:text, "Echo: " <> message}, state}
  end

  def handle_platform_message(message, state) when is_map(message) do
    # Handle JSON message
    {:reply, {:text, Jason.encode!(%{"echo" => message})}, state}
  end
end
```

---

## 2. Integration Test Template

Create a test file like `test/integration/my_adapter_integration_test.exs`:

```elixir
defmodule WebsockexNova.Integration.MyAdapterIntegrationTest do
  use ExUnit.Case, async: false
  alias WebsockexNova.Connection

  setup do
    {:ok, pid} = Connection.start_link(adapter: MyPlatform.Adapter, api_key: "demo-key")
    on_exit(fn ->
      if Process.alive?(pid), do: Process.exit(pid, :kill)
    end)
    %{pid: pid}
  end

  test "echoes text messages", %{pid: pid} do
    send(pid, {:platform_message, "Hello", self()})
    assert_receive {:reply, {:text, "Echo: Hello"}}, 500
  end

  # Add more tests for ping, auth, subscribe, etc.
end
```

- Always use `Process.unlink(pid)` before killing if you want to assert on monitor messages.

---

## 3. Ergonomic Client API Proposal

For a more user-friendly API, you can add a client module that wraps message sending and provides adapter-specific helpers.

### Example: `WebsockexNova.Client`

```elixir
defmodule WebsockexNova.Client do
  @moduledoc """
  Ergonomic client API for interacting with platform adapters.
  """

  def start_link(opts), do: WebsockexNova.Connection.start_link(opts)

  def send_text(pid, text) when is_binary(text) do
    send(pid, {:platform_message, text, self()})
    receive do
      {:reply, reply} -> reply
    after
      1000 -> {:error, :timeout}
    end
  end

  def send_json(pid, map) when is_map(map) do
    send(pid, {:platform_message, map, self()})
    receive do
      {:reply, reply} -> reply
    after
      1000 -> {:error, :timeout}
    end
  end

  # Add more helpers as needed (subscribe, auth, etc.)
end
```

---

## 4. Summary

- The connection wrapper is adapter-agnostic and works for any module implementing the documented contract.
- Integration tests should follow the provided template for reliability and clarity.
- An ergonomic client API can further simplify usage for end users.

For more details, see the Echo adapter and its integration tests as a reference implementation.
