# WebsockexNova Platform Adapter Implementation Guide

This guide provides comprehensive instructions for implementing WebsockexNova platform adapters,
including examples, best practices, and common patterns.

## What is a Platform Adapter?

A platform adapter translates between WebsockexNova's generic interface and a specific WebSocket service's
requirements. It handles:

1. Connection setup for the specific service
2. Message encoding/decoding
3. Authentication processes
4. Subscription management
5. Platform-specific error handling

## Adapter Implementation Checklist

When implementing a new platform adapter, ensure you:

- [ ] Implement all required callbacks from `WebsockexNova.Platform.Adapter`
- [ ] Define service-specific defaults (host, port, path)
- [ ] Implement JSON encoding/decoding if applicable
- [ ] Handle platform-specific message formats
- [ ] Implement reconnection and error recovery strategies
- [ ] Document the adapter's specific behavior and configuration options

## Basic Implementation Example

Below is a template for implementing a basic adapter:

```elixir
defmodule MyApp.Adapters.MyServiceAdapter do
  use WebsockexNova.Platform.Adapter,
    default_host: "api.myservice.com",
    default_port: 443,
    default_path: "/ws"

  require Logger

  @impl true
  def init(opts) do
    # Process options with defaults
    state = opts
      |> Map.new()
      |> Map.put_new(:message_id, 1)
      |> Map.put_new(:subscriptions, %{})

    {:ok, state}
  end

  @impl true
  def handle_platform_message(message, state) when is_binary(message) do
    # Handle text message
    case Jason.decode(message) do
      {:ok, json} -> handle_json_message(json, state)
      {:error, error} ->
        Logger.error("Failed to decode JSON: #{inspect(error)}")
        {:error, %{reason: :invalid_json, details: error}, state}
    end
  end

  def handle_platform_message(message, state) when is_map(message) do
    # Handle already decoded map message
    handle_json_message(message, state)
  end

  @impl true
  def encode_auth_request(credentials) do
    # Create authentication request for the platform
    {:text, Jason.encode!(%{
      id: "auth-#{System.os_time(:millisecond)}",
      method: "login",
      params: %{
        api_key: credentials.api_key,
        api_secret: credentials.api_secret
      }
    })}
  end

  @impl true
  def encode_subscription_request(channel, params) do
    # Create subscription request for the platform
    {:text, Jason.encode!(%{
      id: "sub-#{System.os_time(:millisecond)}",
      method: "subscribe",
      params: %{
        channels: [channel],
        options: params
      }
    })}
  end

  @impl true
  def encode_unsubscription_request(channel) do
    # Create unsubscription request for the platform
    {:text, Jason.encode!(%{
      id: "unsub-#{System.os_time(:millisecond)}",
      method: "unsubscribe",
      params: %{
        channels: [channel]
      }
    })}
  end

  # Private helper functions

  defp handle_json_message(%{"method" => "heartbeat"} = msg, state) do
    # Handle heartbeat message
    reply = %{
      id: msg["id"],
      result: "pong",
      timestamp: :os.system_time(:millisecond)
    }

    {:reply, {:text, Jason.encode!(reply)}, state}
  end

  defp handle_json_message(%{"method" => "subscription", "params" => params}, state) do
    # Handle subscription update
    Logger.debug("Received subscription update: #{inspect(params)}")
    {:ok, state}
  end

  defp handle_json_message(%{"id" => id, "result" => result}, state) do
    # Handle response to a request
    Logger.debug("Received response for request #{id}: #{inspect(result)}")
    {:ok, state}
  end

  defp handle_json_message(%{"error" => error}, state) do
    # Handle error response
    Logger.warning("Received error: #{inspect(error)}")
    {:error, %{reason: :platform_error, details: error}, state}
  end

  defp handle_json_message(other, state) do
    # Handle any other JSON message
    Logger.debug("Received unhandled message: #{inspect(other)}")
    {:ok, state}
  end
end
```

## Advanced Implementation Patterns

### Connection State Management

Manage connection state effectively:

```elixir
defp update_connection_state(state, status) do
  state
  |> Map.put(:connection_status, status)
  |> Map.put(:last_status_change, DateTime.utc_now())
end
```

### Message ID Generation

Generate unique, sequential message IDs:

```elixir
defp next_message_id(state) do
  id = state.message_id
  {id, Map.put(state, :message_id, id + 1)}
end
```

### Request Tracking

Track pending requests for correlation with responses:

```elixir
defp track_request(state, id, type, params) do
  request = %{
    id: id,
    type: type,
    params: params,
    timestamp: System.monotonic_time(:millisecond)
  }

  Map.update(state, :pending_requests, %{id => request}, &Map.put(&1, id, request))
end
```

### Subscription Management

Maintain active subscriptions:

```elixir
defp add_subscription(state, channel, params) do
  Map.update(
    state,
    :subscriptions,
    %{channel => params},
    &Map.put(&1, channel, params)
  )
end

defp remove_subscription(state, channel) do
  Map.update(
    state,
    :subscriptions,
    %{},
    &Map.delete(&1, channel)
  )
end
```

## Working with Different Message Formats

### JSON-RPC

For JSON-RPC based services:

```elixir
def encode_json_rpc_request(method, params, id) do
  {:text, Jason.encode!(%{
    jsonrpc: "2.0",
    method: method,
    params: params,
    id: id
  })}
end
```

### Simple Message Formats

For simpler protocols:

```elixir
def encode_simple_request(action, payload) do
  {:text, Jason.encode!(%{
    action: action,
    payload: payload,
    timestamp: :os.system_time(:millisecond)
  })}
end
```

## Error Handling Patterns

### Categorize Errors

```elixir
defp handle_error(error, state) do
  case categorize_error(error) do
    :authentication -> {:error, %{type: :auth_error, details: error}, state}
    :rate_limit -> {:error, %{type: :rate_limit, details: error}, state}
    :connection -> {:error, %{type: :connection_error, details: error}, state}
    _ -> {:error, %{type: :unknown_error, details: error}, state}
  end
end
```

## Testing Strategies

### Mock WebSocket Server

Create a mock server for testing:

```elixir
defmodule MockServer do
  def start_link do
    # Start a mock WebSocket server
  end

  def expect_message(server, pattern, response) do
    # Set up an expectation
  end
end
```

### Integration Testing

```elixir
test "subscribes to a channel" do
  server = start_supervised!(MockServer)
  MockServer.expect_message(server, %{method: "subscribe"}, %{result: "success"})

  {:ok, conn} = WebsockexNova.Connection.start_link(adapter: MyAdapter)
  assert {:ok, _} = WebsockexNova.Client.subscribe(conn, "test_channel")
end
```

## Logging Best Practices

Add useful context in logs:

```elixir
defp log_connection_event(event, details, state) do
  metadata = [
    adapter: __MODULE__,
    connection_id: state.connection_id,
    event: event
  ]

  Logger.info("Connection event: #{event}", metadata)
  Logger.debug("Connection details: #{inspect(details)}", metadata)
end
```

## Performance Considerations

1. **Minimize Binary-to-Term Conversions**: Avoid repeated encoding/decoding
2. **Use Binary Pattern Matching**: When possible, extract only needed fields
3. **Request Batching**: Batch requests when the protocol supports it

## Documentation Templates

Document your adapters thoroughly:

````elixir
@moduledoc """
WebsockexNova adapter for Service X.

## Features
- Feature 1
- Feature 2

## Configuration
- `:api_key` - API key for authentication
- `:timeout` - Connection timeout in ms (default: 5000)

## Usage
```elixir
{:ok, conn} = WebsockexNova.Connection.start_link(
  adapter: MyAdapter,
  api_key: "my-key",
  api_secret: "my-secret"
)
````

## Limitations

- Any known limitations
  """

```

```
