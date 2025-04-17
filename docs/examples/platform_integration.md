# Platform Integration Guide

This guide provides examples and best practices for implementing platform-specific integrations with WebSockexNova.

## Platform Integration Structure

Each platform integration typically follows this directory structure:

```
lib/websockex_nova/platform/
├── [platform_name]/             # e.g., deribit, bybit, slack, discord
│   ├── adapter.ex               # Main integration adapter
│   ├── auth.ex                  # Authentication implementation
│   ├── client.ex                # WebSocket client implementation
│   ├── message.ex               # Message handling
│   ├── subscription.ex          # Subscription management
│   ├── types.ex                 # Platform-specific types
│   └── rate_limit.ex            # Rate limiting (optional)
```

## Implementation Example: Deribit

Below is a comprehensive example of a Deribit integration:

### 1. Adapter Module

The adapter module serves as the main entry point for the platform integration:

```elixir
defmodule WebSockexNova.Platform.Deribit.Adapter do
  @moduledoc """
  Deribit platform adapter for WebSockexNova.

  This module provides the integration layer between WebSockexNova's behavior-based
  architecture and the Deribit API.
  """

  use WebSockexNova.Implementations.ConnectionHandler
  use WebSockexNova.Implementations.MessageHandler
  use WebSockexNova.Implementations.SubscriptionHandler
  use WebSockexNova.Implementations.AuthHandler

  alias WebSockexNova.Platform.Deribit.Auth
  alias WebSockexNova.Platform.Deribit.Message
  alias WebSockexNova.Platform.Deribit.Subscription

  # Override default implementations with platform-specific behavior

  @impl true
  def init(opts) do
    state = %{
      connection_opts: opts,
      api_key: Keyword.get(opts, :api_key),
      api_secret: Keyword.get(opts, :api_secret),
      subscriptions: %{},
      request_id: 0,
      requests: %{},
      authenticated: false
    }

    {:ok, state}
  end

  @impl true
  def handle_connect(_conn_info, state) do
    if state.api_key && state.api_secret do
      authenticate(state)
    else
      {:ok, state}
    end
  end

  @impl true
  def handle_frame(:text, frame_data, state) do
    with {:ok, parsed} <- Jason.decode(frame_data),
         {:ok, state, _message} <- handle_message(parsed, state) do
      {:ok, state}
    else
      {:error, %Jason.DecodeError{} = error} ->
        Logger.error("Failed to decode Deribit message: #{inspect(error)}")
        {:ok, state}

      {:error, reason, state} ->
        Logger.error("Error handling Deribit message: #{inspect(reason)}")
        {:ok, state}
    end
  end

  # Implementation of platform-specific message handling and routing
  @impl true
  def handle_message(message, state) do
    Message.handle(message, state)
  end

  # Implementation of subscription handling
  @impl true
  def subscribe(channel, opts, state) do
    Subscription.subscribe(channel, opts, state)
  end

  @impl true
  def unsubscribe(subscription_id, state) do
    Subscription.unsubscribe(subscription_id, state)
  end

  # Implementation of authentication handling
  @impl true
  def generate_auth_data(opts) do
    Auth.generate_credentials(opts)
  end

  @impl true
  def handle_auth_response(response, state) do
    Auth.handle_response(response, state)
  end

  # Helper functions
  defp authenticate(state) do
    case Auth.authenticate(state) do
      {:ok, request, updated_state} ->
        {:reply, :text, request, updated_state}

      {:error, reason} ->
        Logger.error("Failed to authenticate with Deribit: #{inspect(reason)}")
        {:ok, state}
    end
  end
end
```

### 2. Authentication Module

The authentication module handles platform-specific authentication flows:

```elixir
defmodule WebSockexNova.Platform.Deribit.Auth do
  @moduledoc """
  Handles authentication with the Deribit API.
  """

  @doc """
  Generates an authentication request for Deribit.
  """
  def authenticate(state) do
    request_id = get_next_request_id(state)

    auth_request = %{
      jsonrpc: "2.0",
      id: request_id,
      method: "public/auth",
      params: %{
        grant_type: "client_credentials",
        client_id: state.api_key,
        client_secret: state.api_secret
      }
    }

    case Jason.encode(auth_request) do
      {:ok, encoded} ->
        updated_state =
          state
          |> Map.put(:request_id, request_id)
          |> register_request(request_id, :authentication)

        {:ok, encoded, updated_state}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Handles an authentication response.
  """
  def handle_response(%{"result" => result}, state) when is_map(result) do
    token = result["access_token"]
    expires = result["expires_in"]
    refresh_token = result["refresh_token"]

    if token do
      expiry_time = DateTime.utc_now() |> DateTime.add(expires, :second)

      updated_state =
        state
        |> Map.put(:authenticated, true)
        |> Map.put(:auth_token, token)
        |> Map.put(:refresh_token, refresh_token)
        |> Map.put(:token_expiry, expiry_time)

      {:ok, updated_state}
    else
      {:error, :auth_token_missing, state}
    end
  end

  def handle_response(%{"error" => error}, state) do
    {:error, error, state}
  end

  def handle_response(response, state) do
    {:error, {:invalid_auth_response, response}, state}
  end

  @doc """
  Generates credentials for authentication.
  """
  def generate_credentials(opts) do
    api_key = Keyword.fetch!(opts, :api_key)
    api_secret = Keyword.fetch!(opts, :api_secret)

    {:ok, %{api_key: api_key, api_secret: api_secret}}
  end

  # Helper functions
  defp get_next_request_id(state) do
    Map.get(state, :request_id, 0) + 1
  end

  defp register_request(state, request_id, type) do
    requests = Map.put(
      Map.get(state, :requests, %{}),
      request_id,
      %{type: type, timestamp: DateTime.utc_now()}
    )

    Map.put(state, :requests, requests)
  end
end
```

### 3. Message Module

The message module handles platform-specific message formats and routing:

```elixir
defmodule WebSockexNova.Platform.Deribit.Message do
  @moduledoc """
  Handles Deribit WebSocket messages.
  """

  require Logger
  alias WebSockexNova.Platform.Deribit.Auth
  alias WebSockexNova.Platform.Deribit.Subscription

  @doc """
  Routes and processes incoming messages.
  """
  def handle(message, state) do
    case message_type(message) do
      {:subscription, channel} ->
        handle_subscription_data(message, channel, state)

      {:response, id} ->
        handle_response(message, id, state)

      {:heartbeat, _} ->
        {:ok, state, message}

      {:unknown, _} ->
        Logger.warn("Unknown Deribit message format: #{inspect(message)}")
        {:ok, state, message}
    end
  end

  @doc """
  Determines the type of a Deribit WebSocket message.
  """
  def message_type(%{"method" => "subscription", "params" => %{"channel" => channel}})
      when is_binary(channel) do
    {:subscription, channel}
  end

  def message_type(%{"id" => id}) when is_integer(id) do
    {:response, id}
  end

  def message_type(%{"method" => "heartbeat"}) do
    {:heartbeat, nil}
  end

  def message_type(_) do
    {:unknown, nil}
  end

  # Handle subscription data updates
  defp handle_subscription_data(message, channel, state) do
    data = get_in(message, ["params", "data"])

    if data do
      # Process subscription data
      # ...

      {:ok, state, %{channel: channel, data: data}}
    else
      {:error, :invalid_subscription_data, state}
    end
  end

  # Handle method responses
  defp handle_response(message, id, state) do
    case get_request_type(state, id) do
      :authentication ->
        Auth.handle_response(message, state)

      :subscription ->
        Subscription.handle_response(message, state)

      :unsubscribe ->
        Subscription.handle_unsubscribe_response(message, state)

      _ ->
        # Handle generic response
        {:ok, state, message}
    end
  end

  # Helper function to get request type from state
  defp get_request_type(state, request_id) do
    case get_in(state, [:requests, request_id]) do
      %{type: type} -> type
      _ -> nil
    end
  end
end
```

### 4. Subscription Module

The subscription module manages platform-specific channel subscriptions:

```elixir
defmodule WebSockexNova.Platform.Deribit.Subscription do
  @moduledoc """
  Handles Deribit WebSocket subscriptions.
  """

  require Logger

  @doc """
  Subscribes to a Deribit channel.
  """
  def subscribe(channel, opts, state) do
    request_id = get_next_request_id(state)

    subscribe_request = %{
      jsonrpc: "2.0",
      id: request_id,
      method: "public/subscribe",
      params: %{
        channels: [channel]
      }
    }

    case Jason.encode(subscribe_request) do
      {:ok, encoded} ->
        updated_state =
          state
          |> Map.put(:request_id, request_id)
          |> register_request(request_id, :subscription)
          |> register_subscription(channel, opts)

        {:ok, updated_state, encoded}

      {:error, reason} ->
        {:error, reason, state}
    end
  end

  @doc """
  Unsubscribes from a Deribit channel.
  """
  def unsubscribe(channel, state) do
    request_id = get_next_request_id(state)

    unsubscribe_request = %{
      jsonrpc: "2.0",
      id: request_id,
      method: "public/unsubscribe",
      params: %{
        channels: [channel]
      }
    }

    case Jason.encode(unsubscribe_request) do
      {:ok, encoded} ->
        updated_state =
          state
          |> Map.put(:request_id, request_id)
          |> register_request(request_id, :unsubscribe)

        {:ok, updated_state, encoded}

      {:error, reason} ->
        {:error, reason, state}
    end
  end

  @doc """
  Handles a subscription response.
  """
  def handle_response(%{"result" => channels}, state) when is_list(channels) do
    # Update subscription state with confirmed channels
    updated_state = update_subscription_state(state, channels)
    {:ok, updated_state}
  end

  def handle_response(%{"error" => error}, state) do
    {:error, error, state}
  end

  @doc """
  Handles an unsubscribe response.
  """
  def handle_unsubscribe_response(%{"result" => channels}, state) when is_list(channels) do
    # Remove unsubscribed channels
    updated_state = remove_subscriptions(state, channels)
    {:ok, updated_state}
  end

  def handle_unsubscribe_response(%{"error" => error}, state) do
    {:error, error, state}
  end

  # Helper functions
  defp get_next_request_id(state) do
    Map.get(state, :request_id, 0) + 1
  end

  defp register_request(state, request_id, type) do
    requests = Map.put(
      Map.get(state, :requests, %{}),
      request_id,
      %{type: type, timestamp: DateTime.utc_now()}
    )

    Map.put(state, :requests, requests)
  end

  defp register_subscription(state, channel, opts) do
    subscriptions = Map.put(
      Map.get(state, :subscriptions, %{}),
      channel,
      %{
        status: :pending,
        options: opts,
        timestamp: DateTime.utc_now()
      }
    )

    Map.put(state, :subscriptions, subscriptions)
  end

  defp update_subscription_state(state, channels) do
    subscriptions = Map.get(state, :subscriptions, %{})

    updated_subscriptions =
      Enum.reduce(channels, subscriptions, fn channel, acc ->
        case Map.get(acc, channel) do
          %{} = sub_info ->
            Map.put(acc, channel, Map.put(sub_info, :status, :active))

          nil ->
            # Channel wasn't in our records but got confirmed
            Map.put(acc, channel, %{
              status: :active,
              options: [],
              timestamp: DateTime.utc_now()
            })
        end
      end)

    Map.put(state, :subscriptions, updated_subscriptions)
  end

  defp remove_subscriptions(state, channels) do
    subscriptions = Map.get(state, :subscriptions, %{})

    updated_subscriptions =
      Enum.reduce(channels, subscriptions, fn channel, acc ->
        Map.delete(acc, channel)
      end)

    Map.put(state, :subscriptions, updated_subscriptions)
  end
end
```

## Creating a New Platform Integration

Follow these steps to create a new platform integration:

1. **Create Directory Structure**

   Start by creating the appropriate directory structure for your platform:

   ```
   lib/websockex_nova/platform/[your_platform_name]/
   ```

2. **Define Adapter Module**

   Create an adapter module that uses WebSockexNova's default implementations:

   ```elixir
   defmodule WebSockexNova.Platform.YourPlatform.Adapter do
     use WebSockexNova.Implementations.ConnectionHandler
     use WebSockexNova.Implementations.MessageHandler
     use WebSockexNova.Implementations.SubscriptionHandler
     # Add other behaviors as needed

     # Override only necessary callbacks
   end
   ```

3. **Implement Platform-Specific Modules**

   Create modules for:
   - Authentication
   - Message handling
   - Subscription management
   - Any other platform-specific concerns

4. **Test Your Implementation**

   Create test modules to verify your implementation:

   ```elixir
   defmodule WebSockexNova.Platform.YourPlatform.Test do
     use ExUnit.Case

     # Test cases for your implementation
   end
   ```

5. **Create Client Convenience Module**

   Create a client module that makes it easy to use your platform:

   ```elixir
   defmodule WebSockexNova.Platform.YourPlatform.Client do
     @moduledoc """
     Convenience client for YourPlatform WebSocket API.

     ## Examples

     ```elixir
     {:ok, client} = WebSockexNova.Platform.YourPlatform.Client.start_link(
       api_key: "your_key",
       api_secret: "your_secret"
     )

     # Subscribe to a channel
     WebSockexNova.Platform.YourPlatform.Client.subscribe(client, "channel_name")
     ```
     """

     use WebSockexNova.Client,
       platform: :your_platform,
       profile: :standard

     # Additional client-specific functions
   end
   ```

## Customization Options

When integrating with platforms, you can customize various aspects:

### 1. Authentication

Customize authentication by overriding these callbacks:

```elixir
# Generate authentication data
def generate_auth_data(opts) do
  # Platform-specific authentication logic
  {:ok, auth_data}
end

# Handle authentication responses
def handle_auth_response(response, state) do
  # Process authentication result
  {:ok, updated_state}
end
```

### 2. Message Handling

Customize message handling:

```elixir
# Determine message types
def message_type(message) do
  cond do
    # Platform-specific message type detection
    is_subscription_message(message) ->
      {:subscription, get_channel(message)}
    is_response_message(message) ->
      {:response, get_id(message)}
    is_heartbeat_message(message) ->
      {:heartbeat, nil}
    true ->
      {:unknown, nil}
  end
end

# Handle incoming messages
def handle_message(message, state) do
  # Platform-specific message handling
  {:ok, updated_state, processed_message}
end
```

### 3. Rate Limiting

Implement rate limiting for platforms that require it:

```elixir
# Check if operation would exceed rate limit
def check_rate_limit(operation, state) do
  # Platform-specific rate limiting logic
  if within_limits?(operation, state) do
    {:ok, state}
  else
    {:rate_limited, retry_after_milliseconds, state}
  end
end
```

## Best Practices for Platform Integrations

1. **Use Default Implementations**

   Start with WebSockexNova's default implementations and only override the callbacks that need platform-specific behavior.

2. **Handle Reconnections Properly**

   Ensure your platform adapter properly handles reconnection scenarios, including re-authentication and re-subscribing to channels.

3. **Organize Code by Responsibility**

   Split platform-specific logic into separate modules based on responsibility (auth, messages, subscriptions).

4. **Document Platform-Specific Behavior**

   Include clear documentation about platform-specific behaviors, rate limits, authentication requirements, etc.

5. **Provide Usage Examples**

   Include example code showing how to use your platform integration.

## Common Patterns

### Subscription Management

Most WebSocket platforms follow similar subscription patterns:

1. Send subscription request
2. Receive confirmation response
3. Start receiving updates on subscribed channels

```elixir
def subscribe(channel, opts, state) do
  # Generate subscription request
  request = create_subscription_request(channel, opts)

  # Send request and update state to track pending subscription
  {:ok, track_pending_subscription(state, channel), encoded_request}
end
```

### Authentication Flow

Common authentication flow:

1. Connect to WebSocket
2. Send authentication request
3. Receive authentication response
4. Track token expiry
5. Re-authenticate before token expires

```elixir
def handle_connect(_conn_info, state) do
  # Authenticate immediately after connection
  {:reply, :text, auth_request, updated_state}
end
```

### Request-Response Tracking

Track outgoing requests to correlate with responses:

```elixir
defp register_request(state, request_id, type) do
  requests = Map.put(
    Map.get(state, :requests, %{}),
    request_id,
    %{type: type, timestamp: DateTime.utc_now()}
  )

  Map.put(state, :requests, requests)
end
```

## Related Resources

- [WebSockexNova API Documentation](/docs/api/)
- [Behavior Specifications](/docs/api/behavior_specifications.md)
- [Telemetry Guides](/docs/guides/telemetry.md)
- [Example: Deribit Integration](/docs/examples/deribit_integration.md)
