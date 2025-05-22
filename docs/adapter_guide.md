# WebsockexNew Adapter Development Guide

Learn how to create platform-specific adapters for WebsockexNew.

## What are Adapters?

Adapters wrap `WebsockexNew.Client` with platform-specific functionality:
- Custom authentication flows
- Protocol-specific message formats  
- Platform error handling
- Subscription management
- Heartbeat responses

## Adapter Architecture

Adapters follow a simple wrapper pattern:

```elixir
defmodule YourPlatform.Adapter do
  # Wrap WebsockexNew.Client with platform state
  defstruct [:client, :platform_specific_fields]
  
  # Platform-specific connection
  def connect(opts)
  
  # Platform authentication  
  def authenticate(adapter)
  
  # Platform subscriptions
  def subscribe(adapter, channels)
  
  # Platform message handling
  def handle_message(frame)
end
```

## Step-by-Step Adapter Development

### 1. Define Adapter Struct

Start with the client and platform-specific state:

```elixir
defmodule MyPlatform.Adapter do
  alias WebsockexNew.Client
  
  defstruct [
    :client,              # WebsockexNew.Client instance
    :authenticated,       # Authentication state
    :subscriptions,       # Active subscriptions
    :api_key,            # Platform credentials
    :session_token       # Session state
  ]
  
  @type t :: %__MODULE__{
    client: Client.t(),
    authenticated: boolean(),
    subscriptions: MapSet.t(),
    api_key: String.t() | nil,
    session_token: String.t() | nil
  }
end
```

### 2. Implement Connection Function

Wrap `WebsockexNew.Client.connect/1` with platform setup:

```elixir
@spec connect(keyword()) :: {:ok, t()} | {:error, term()}
def connect(opts \\ []) do
  api_key = Keyword.get(opts, :api_key)
  url = Keyword.get(opts, :url, "wss://api.myplatform.com/ws")
  
  case Client.connect(url) do
    {:ok, client} ->
      adapter = %__MODULE__{
        client: client,
        authenticated: false,
        subscriptions: MapSet.new(),
        api_key: api_key,
        session_token: nil
      }
      
      {:ok, adapter}
      
    error ->
      error
  end
end
```

### 3. Add Authentication Logic

Implement platform-specific authentication:

```elixir
@spec authenticate(t()) :: {:ok, t()} | {:error, term()}
def authenticate(%__MODULE__{api_key: nil}), do: {:error, :missing_api_key}

def authenticate(%__MODULE__{client: client, api_key: api_key} = adapter) do
  auth_message = create_auth_message(api_key)
  
  case Client.send_message(client, auth_message) do
    :ok ->
      # Wait for auth response or mark as authenticated
      {:ok, %{adapter | authenticated: true}}
      
    error ->
      error
  end
end

defp create_auth_message(api_key) do
  Jason.encode!(%{
    type: "auth",
    api_key: api_key,
    timestamp: System.system_time(:second)
  })
end
```

### 4. Implement Subscription Management

Handle platform-specific channel subscriptions:

```elixir
@spec subscribe(t(), list(String.t())) :: {:ok, t()} | {:error, term()}
def subscribe(%__MODULE__{client: client, subscriptions: subs} = adapter, channels) do
  subscription_message = create_subscription_message(channels)
  
  case Client.send_message(client, subscription_message) do
    :ok ->
      new_subs = Enum.reduce(channels, subs, &MapSet.put(&2, &1))
      {:ok, %{adapter | subscriptions: new_subs}}
      
    error ->
      error
  end
end

defp create_subscription_message(channels) do
  Jason.encode!(%{
    type: "subscribe",
    channels: channels,
    timestamp: System.system_time(:second)
  })
end
```

### 5. Handle Platform Messages

Process platform-specific message formats:

```elixir
@spec handle_message(term()) :: :ok | {:response, binary()}
def handle_message({:text, message}) do
  case Jason.decode(message) do
    {:ok, %{"type" => "ping"}} ->
      # Handle platform heartbeat
      response = Jason.encode!(%{type: "pong"})
      {:response, response}
      
    {:ok, %{"type" => "auth_success", "token" => token}} ->
      # Handle successful authentication
      handle_auth_success(token)
      :ok
      
    {:ok, %{"type" => "data", "channel" => channel, "payload" => data}} ->
      # Handle channel data
      handle_channel_data(channel, data)
      :ok
      
    {:ok, %{"type" => "error", "code" => code, "message" => msg}} ->
      # Handle platform errors
      handle_platform_error(code, msg)
      :ok
      
    {:error, _reason} ->
      :ok
  end
end

def handle_message(_message), do: :ok
```

### 6. Create Message Handler Factory

Provide a convenient message handler creator:

```elixir
@spec create_message_handler(keyword()) :: function()
def create_message_handler(opts \\ []) do
  on_message = Keyword.get(opts, :on_message, &default_message_handler/1)
  on_auth = Keyword.get(opts, :on_auth, &default_auth_handler/1)
  on_error = Keyword.get(opts, :on_error, &default_error_handler/1)
  
  WebsockexNew.MessageHandler.create_handler(
    on_message: fn frame ->
      case handle_message(frame) do
        {:response, response} ->
          # Send automatic response (e.g., heartbeat)
          send_response(response)
          
        :ok ->
          on_message.(frame)
      end
    end,
    on_error: on_error
  )
end
```

## DeribitAdapter Example Analysis

Let's examine the DeribitAdapter implementation:

### Key Features

1. **Authentication Flow**
   ```elixir
   def authenticate(%__MODULE__{client: client, client_id: client_id, client_secret: client_secret} = adapter) do
     auth_message = Jason.encode!(%{
       jsonrpc: "2.0",
       id: :erlang.unique_integer([:positive]),
       method: "public/auth",
       params: %{
         grant_type: "client_credentials",
         client_id: client_id,
         client_secret: client_secret
       }
     })
   ```

2. **Subscription Management**
   ```elixir
   def subscribe(%__MODULE__{client: client, subscriptions: subs} = adapter, channels) do
     subscription_message = Jason.encode!(%{
       jsonrpc: "2.0",
       id: :erlang.unique_integer([:positive]),
       method: "public/subscribe",
       params: %{channels: channels}
     })
   ```

3. **Heartbeat Handling**
   ```elixir
   def handle_message({:text, message}) do
     case Jason.decode(message) do
       {:ok, %{"method" => "heartbeat", "params" => %{"type" => "test_request"}}} ->
         response = Jason.encode!(%{
           jsonrpc: "2.0",
           method: "public/test",
           params: %{}
         })
         {:response, response}
   ```

## Platform-Specific Considerations

### JSON-RPC Platforms (like Deribit)

- Use `jsonrpc: "2.0"` field
- Include unique `id` for request tracking
- Structure as `method` and `params`

### REST-style WebSocket APIs

- Use simple message types
- Include authentication tokens in headers or message body
- Handle subscription confirmations

### Binary Protocol Platforms

- Use `WebsockexNew.Frame.binary/1` for binary messages
- Implement custom encoding/decoding
- Handle binary heartbeats

### Real-time Trading Platforms

- Implement fast heartbeat responses
- Handle market data efficiently
- Support order management messages

## Testing Your Adapter

### Unit Tests

Test adapter logic in isolation:

```elixir
defmodule MyPlatform.AdapterTest do
  use ExUnit.Case
  
  test "handles authentication" do
    adapter = %MyPlatform.Adapter{api_key: "test_key"}
    {:ok, authenticated} = MyPlatform.Adapter.authenticate(adapter)
    assert authenticated.authenticated == true
  end
  
  test "handles platform messages" do
    message = {:text, Jason.encode!(%{type: "ping"})}
    {:response, response} = MyPlatform.Adapter.handle_message(message)
    assert response =~ "pong"
  end
end
```

### Integration Tests

Test with real platform endpoints:

```elixir
defmodule MyPlatform.IntegrationTest do
  use ExUnit.Case
  
  @tag :integration
  test "connects to test environment" do
    {:ok, adapter} = MyPlatform.Adapter.connect(url: "wss://test.myplatform.com/ws")
    {:ok, adapter} = MyPlatform.Adapter.authenticate(adapter)
    {:ok, _adapter} = MyPlatform.Adapter.subscribe(adapter, ["test.channel"])
  end
end
```

## Best Practices

### 1. Keep Adapters Thin

Focus on protocol translation, not business logic:

```elixir
# Good: Simple protocol translation
def subscribe(adapter, channels) do
  message = create_subscription_message(channels)
  Client.send_message(adapter.client, message)
end

# Avoid: Complex business logic in adapter
def subscribe(adapter, channels) do
  validated_channels = validate_and_transform_channels(channels)
  enriched_channels = add_metadata_to_channels(validated_channels)
  # ... complex processing
end
```

### 2. Handle Errors Gracefully

Pass raw errors without wrapping:

```elixir
# Good: Pass raw errors
case Client.send_message(client, message) do
  :ok -> {:ok, adapter}
  error -> error  # Pass raw error
end

# Avoid: Wrapping errors
case Client.send_message(client, message) do
  :ok -> {:ok, adapter}  
  error -> {:error, {:adapter_error, error}}  # Don't wrap
end
```

### 3. Preserve Subscription State

Track subscriptions for reconnection:

```elixir
defstruct [
  :client,
  subscriptions: MapSet.new(),  # Track active subscriptions
  # ...
]

def subscribe(adapter, channels) do
  # ... send subscription message
  new_subs = Enum.reduce(channels, adapter.subscriptions, &MapSet.put(&2, &1))
  {:ok, %{adapter | subscriptions: new_subs}}
end
```

### 4. Support Reconnection

Implement subscription restoration:

```elixir
def restore_subscriptions(adapter) do
  channels = MapSet.to_list(adapter.subscriptions)
  subscribe(adapter, channels)
end
```

### 5. Document Platform Specifics

Include platform documentation:

```elixir
@moduledoc """
MyPlatform WebSocket adapter for WebsockexNew.

Platform specifics:
- Requires API key authentication
- Uses heartbeat every 30 seconds  
- Supports channels: ticker.*, trades.*, orderbook.*
- Rate limit: 100 messages/second

## Example Usage

    {:ok, adapter} = MyPlatform.Adapter.connect(api_key: "your_key")
    {:ok, adapter} = MyPlatform.Adapter.authenticate(adapter)
    {:ok, adapter} = MyPlatform.Adapter.subscribe(adapter, ["ticker.BTC-USD"])
"""
```

## Common Adapter Patterns

### Authentication Patterns

1. **API Key in Header**
   ```elixir
   def connect(opts) do
     headers = [{"Authorization", "Bearer #{opts[:api_key]}"}]
     Client.connect(url, headers: headers)
   end
   ```

2. **Authentication Message**
   ```elixir
   def authenticate(adapter) do
     auth_msg = create_auth_message(adapter.credentials)
     Client.send_message(adapter.client, auth_msg)
   end
   ```

3. **Token Refresh**
   ```elixir
   def refresh_token(adapter) do
     # Implement token refresh logic
   end
   ```

### Message Handling Patterns

1. **Request/Response Tracking**
   ```elixir
   defstruct [:client, :pending_requests]
   
   def send_request(adapter, method, params) do
     id = generate_request_id()
     # Track pending request
     # Send message with ID
   end
   ```

2. **Channel Routing**
   ```elixir
   def handle_message({:text, message}) do
     case Jason.decode(message) do
       {:ok, %{"channel" => channel, "data" => data}} ->
         route_channel_message(channel, data)
     end
   end
   ```

3. **Error Code Mapping**
   ```elixir
   defp map_platform_error(code) do
     case code do
       1001 -> :invalid_credentials
       1002 -> :rate_limited
       _ -> :unknown_error
     end
   end
   ```

This guide provides the foundation for creating robust, platform-specific adapters that integrate seamlessly with WebsockexNew's simple architecture.