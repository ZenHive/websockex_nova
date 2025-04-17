# Protocol Integration Guide

This guide provides examples and best practices for implementing protocol-specific integrations with WebSockexNova.

## Protocol vs. Platform Integrations

While platform integrations focus on specific service providers (like Deribit or Slack), protocol integrations focus on communication protocols that may be used by multiple platforms:

- **Platform Integration**: Specific to a service provider (Deribit, Bybit, Slack, Discord)
- **Protocol Integration**: Focused on a communication protocol (Ethereum JSON-RPC, Phoenix Channels, STOMP)

## Protocol Integration Structure

Protocol integrations typically follow this directory structure:

```
lib/websockex_nova/protocol/
├── [protocol_name]/            # e.g., ethereum, phoenix, stomp
│   ├── adapter.ex              # Main integration adapter
│   ├── client.ex               # Protocol client implementation
│   ├── codec.ex                # Protocol encoding/decoding
│   ├── message.ex              # Message handling
│   ├── types.ex                # Protocol-specific types
│   └── transport.ex            # Transport-specific handling
```

## Implementation Example: Ethereum JSON-RPC

Below is a comprehensive example of an Ethereum JSON-RPC protocol integration:

### 1. Adapter Module

The adapter module implements the protocol-specific behavior:

```elixir
defmodule WebSockexNova.Protocol.Ethereum.Adapter do
  @moduledoc """
  Ethereum JSON-RPC protocol adapter for WebSockexNova.

  This module provides the integration layer between WebSockexNova's behavior-based
  architecture and the Ethereum JSON-RPC protocol specification.
  """

  use WebSockexNova.Implementations.ConnectionHandler
  use WebSockexNova.Implementations.MessageHandler
  use WebSockexNova.Implementations.SubscriptionHandler

  alias WebSockexNova.Protocol.Ethereum.Codec
  alias WebSockexNova.Protocol.Ethereum.Message

  # Override default implementations with protocol-specific behavior

  @impl true
  def init(opts) do
    state = %{
      connection_opts: opts,
      request_id: 0,
      requests: %{},
      subscriptions: %{}
    }

    {:ok, state}
  end

  @impl true
  def handle_connect(_conn_info, state) do
    # Ethereum protocol doesn't require connection-time setup
    {:ok, state}
  end

  @impl true
  def handle_frame(:text, frame_data, state) do
    with {:ok, parsed} <- Jason.decode(frame_data),
         {:ok, state, _message} <- handle_message(parsed, state) do
      {:ok, state}
    else
      {:error, %Jason.DecodeError{} = error} ->
        Logger.error("Failed to decode Ethereum JSON-RPC message: #{inspect(error)}")
        {:ok, state}

      {:error, reason, state} ->
        Logger.error("Error handling Ethereum JSON-RPC message: #{inspect(reason)}")
        {:ok, state}
    end
  end

  # Implementation of protocol-specific message handling
  @impl true
  def handle_message(message, state) do
    Message.handle(message, state)
  end

  @impl true
  def message_type(message) do
    Message.determine_type(message)
  end

  # Implementation of subscription handling for Ethereum pubsub
  @impl true
  def subscribe(method, params, state) do
    request_id = next_request_id(state)

    subscribe_request = %{
      jsonrpc: "2.0",
      id: request_id,
      method: "eth_subscribe",
      params: [method | List.wrap(params)]
    }

    case Codec.encode(subscribe_request) do
      {:ok, encoded} ->
        updated_state =
          state
          |> Map.put(:request_id, request_id)
          |> register_request(request_id, :subscription, %{method: method, params: params})

        {:ok, updated_state, encoded}

      {:error, reason} ->
        {:error, reason, state}
    end
  end

  @impl true
  def unsubscribe(subscription_id, state) do
    request_id = next_request_id(state)

    unsubscribe_request = %{
      jsonrpc: "2.0",
      id: request_id,
      method: "eth_unsubscribe",
      params: [subscription_id]
    }

    case Codec.encode(unsubscribe_request) do
      {:ok, encoded} ->
        updated_state =
          state
          |> Map.put(:request_id, request_id)
          |> register_request(request_id, :unsubscribe, %{subscription_id: subscription_id})

        {:ok, updated_state, encoded}

      {:error, reason} ->
        {:error, reason, state}
    end
  end

  @impl true
  def encode_message(message, _state) do
    Codec.encode(message)
  end

  # Helper functions
  defp next_request_id(state) do
    Map.get(state, :request_id, 0) + 1
  end

  defp register_request(state, request_id, type, metadata \\ %{}) do
    requests = Map.put(
      Map.get(state, :requests, %{}),
      request_id,
      Map.merge(%{
        type: type,
        timestamp: DateTime.utc_now()
      }, metadata)
    )

    Map.put(state, :requests, requests)
  end
end
```

### 2. Codec Module

The codec module handles protocol-specific encoding and decoding:

```elixir
defmodule WebSockexNova.Protocol.Ethereum.Codec do
  @moduledoc """
  Encodes and decodes Ethereum JSON-RPC messages.
  """

  @doc """
  Encodes an Ethereum JSON-RPC message.

  ## Examples

      iex> encode(%{jsonrpc: "2.0", id: 1, method: "eth_blockNumber"})
      {:ok, "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"eth_blockNumber\"}"}
  """
  def encode(message) do
    Jason.encode(message)
  end

  @doc """
  Decodes an Ethereum JSON-RPC message.

  ## Examples

      iex> decode("{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":\"0x1b4\"}")
      {:ok, %{"jsonrpc" => "2.0", "id" => 1, "result" => "0x1b4"}}
  """
  def decode(message) when is_binary(message) do
    Jason.decode(message)
  end

  @doc """
  Converts hex-encoded integers to decimal integers.

  ## Examples

      iex> hex_to_integer("0x1b4")
      436
  """
  def hex_to_integer("0x" <> hex_value) do
    String.to_integer(hex_value, 16)
  end

  @doc """
  Converts decimal integers to hex-encoded strings.

  ## Examples

      iex> integer_to_hex(436)
      "0x1b4"
  """
  def integer_to_hex(value) when is_integer(value) do
    "0x" <> Integer.to_string(value, 16)
  end
end
```

### 3. Message Module

The message module handles protocol-specific message formats:

```elixir
defmodule WebSockexNova.Protocol.Ethereum.Message do
  @moduledoc """
  Handles Ethereum JSON-RPC WebSocket messages.
  """

  require Logger

  @doc """
  Determines the type of an Ethereum JSON-RPC message.
  """
  def determine_type(%{"method" => "eth_subscription", "params" => %{"subscription" => subscription_id}})
      when is_binary(subscription_id) do
    {:subscription, subscription_id}
  end

  def determine_type(%{"id" => id}) when is_integer(id) or is_binary(id) do
    {:response, id}
  end

  def determine_type(_) do
    {:unknown, nil}
  end

  @doc """
  Handles an incoming Ethereum JSON-RPC message.
  """
  def handle(message, state) do
    case determine_type(message) do
      {:subscription, subscription_id} ->
        handle_subscription_notification(message, subscription_id, state)

      {:response, id} ->
        handle_response(message, id, state)

      {:unknown, _} ->
        Logger.warn("Unknown Ethereum JSON-RPC message format: #{inspect(message)}")
        {:ok, state, message}
    end
  end

  @doc """
  Creates a standard Ethereum JSON-RPC request.
  """
  def create_request(method, params, id) do
    %{
      jsonrpc: "2.0",
      id: id,
      method: method,
      params: params
    }
  end

  # Private functions

  defp handle_subscription_notification(message, subscription_id, state) do
    subscription_data = get_in(message, ["params", "result"])
    subscription_method = get_subscription_method(state, subscription_id)

    if subscription_data do
      # Process subscription data based on method
      processed_data = process_subscription_data(subscription_method, subscription_data)

      {:ok, state, %{
        subscription_id: subscription_id,
        method: subscription_method,
        data: processed_data
      }}
    else
      {:error, :invalid_subscription_data, state}
    end
  end

  defp handle_response(message, id, state) do
    case get_request_type(state, id) do
      :subscription when is_map_key(message, "result") ->
        # This is a successful subscription response with new subscription ID
        subscription_id = message["result"]
        request_info = get_request_info(state, id)

        # Associate method with subscription_id for future notifications
        updated_state = register_subscription(
          state,
          subscription_id,
          request_info.method,
          request_info.params
        )

        {:ok, updated_state, message}

      :unsubscribe when is_map_key(message, "result") ->
        # Successful unsubscribe
        subscription_id = get_in(get_request_info(state, id), [:subscription_id])
        updated_state = remove_subscription(state, subscription_id)

        {:ok, updated_state, message}

      _ ->
        # Handle other response types
        {:ok, state, message}
    end
  end

  # Helper functions for handling subscription state

  defp get_request_type(state, request_id) do
    case get_in(state, [:requests, request_id]) do
      %{type: type} -> type
      _ -> nil
    end
  end

  defp get_request_info(state, request_id) do
    Map.get(state.requests || %{}, request_id, %{})
  end

  defp get_subscription_method(state, subscription_id) do
    case get_in(state, [:subscriptions, subscription_id]) do
      %{method: method} -> method
      _ -> nil
    end
  end

  defp register_subscription(state, subscription_id, method, params) do
    subscriptions = Map.put(
      Map.get(state, :subscriptions, %{}),
      subscription_id,
      %{
        method: method,
        params: params,
        timestamp: DateTime.utc_now()
      }
    )

    Map.put(state, :subscriptions, subscriptions)
  end

  defp remove_subscription(state, subscription_id) do
    update_in(
      state,
      [:subscriptions],
      &Map.delete(&1 || %{}, subscription_id)
    )
  end

  # Process subscription data based on method
  defp process_subscription_data("newHeads", data) do
    # Process new block headers
    %{
      number: data["number"],
      hash: data["hash"],
      timestamp: data["timestamp"]
    }
  end

  defp process_subscription_data("logs", data) do
    # Process log events
    %{
      address: data["address"],
      topics: data["topics"],
      data: data["data"],
      block_number: data["blockNumber"],
      transaction_hash: data["transactionHash"],
      log_index: data["logIndex"]
    }
  end

  defp process_subscription_data(_, data) do
    # Default processing for other methods
    data
  end
end
```

### 4. Client Module

The client module provides a convenient API for using the Ethereum JSON-RPC protocol:

```elixir
defmodule WebSockexNova.Protocol.Ethereum.Client do
  @moduledoc """
  Client for Ethereum JSON-RPC WebSocket API.

  This module provides a high-level API for interacting with Ethereum nodes
  via WebSocket using the JSON-RPC protocol.

  ## Examples

  ```elixir
  # Connect to an Ethereum node
  {:ok, client} = WebSockexNova.Protocol.Ethereum.Client.start_link(
    url: "wss://mainnet.infura.io/ws/v3/YOUR_PROJECT_ID"
  )

  # Subscribe to new block headers
  {:ok, subscription_id} = WebSockexNova.Protocol.Ethereum.Client.subscribe(
    client, "newHeads"
  )

  # Call an RPC method
  {:ok, block_number} = WebSockexNova.Protocol.Ethereum.Client.call(
    client, "eth_blockNumber", []
  )
  ```
  """

  use WebSockexNova.Client,
    protocol: :ethereum,
    profile: :standard

  alias WebSockexNova.Protocol.Ethereum.Message

  @doc """
  Subscribes to an Ethereum event.

  Available subscription types:
  - "newHeads" - New block headers
  - "logs" - New logs matching a filter
  - "newPendingTransactions" - New pending transactions
  - "syncing" - Syncing status changes

  ## Examples

  ```elixir
  # Subscribe to new blocks
  {:ok, subscription_id} = subscribe(client, "newHeads")

  # Subscribe to specific logs
  filter = %{address: "0x1234...", topics: ["0xabcd..."]}
  {:ok, subscription_id} = subscribe(client, "logs", filter)
  ```
  """
  def subscribe(client, method, params \\ []) do
    GenServer.call(client, {:subscribe, method, params})
  end

  @doc """
  Unsubscribes from an Ethereum event.

  ## Examples

  ```elixir
  :ok = unsubscribe(client, subscription_id)
  ```
  """
  def unsubscribe(client, subscription_id) do
    GenServer.call(client, {:unsubscribe, subscription_id})
  end

  @doc """
  Makes a JSON-RPC call to the Ethereum node.

  ## Examples

  ```elixir
  # Get latest block number
  {:ok, block_number} = call(client, "eth_blockNumber", [])

  # Get balance
  {:ok, balance} = call(client, "eth_getBalance", ["0x1234...", "latest"])
  ```
  """
  def call(client, method, params) do
    GenServer.call(client, {:call, method, params})
  end

  # GenServer callbacks to handle client API

  def handle_call({:subscribe, method, params}, _from, state) do
    # Implementation details
    # ...
  end

  def handle_call({:unsubscribe, subscription_id}, _from, state) do
    # Implementation details
    # ...
  end

  def handle_call({:call, method, params}, _from, state) do
    # Implementation details
    # ...
  end

  # Other implementation details
  # ...
end
```

## Creating a New Protocol Integration

Follow these steps to implement a new protocol integration:

1. **Understand the Protocol**

   Thoroughly understand the protocol specification, including:

   - Message format
   - Subscription mechanism
   - Authentication requirements (if any)
   - Error handling
   - Special protocol-specific features

2. **Create Directory Structure**

   Set up the appropriate directory structure:

   ```
   lib/websockex_nova/protocol/[your_protocol_name]/
   ```

3. **Define Protocol-Specific Types**

   Create a types module that defines protocol-specific types and structures:

   ```elixir
   defmodule WebSockexNova.Protocol.YourProtocol.Types do
     @moduledoc """
     Type definitions for the YourProtocol protocol.
     """

     @type request :: %{
       required(:id) => integer() | String.t(),
       required(:method) => String.t(),
       optional(:params) => list() | map()
       # Other protocol-specific fields
     }

     @type response :: %{
       required(:id) => integer() | String.t(),
       optional(:result) => term(),
       optional(:error) => error()
       # Other protocol-specific fields
     }

     @type error :: %{
       required(:code) => integer(),
       required(:message) => String.t(),
       optional(:data) => term()
     }

     # Additional type definitions
   end
   ```

4. **Implement Codec**

   Create a codec module for encoding and decoding protocol messages:

   ```elixir
   defmodule WebSockexNova.Protocol.YourProtocol.Codec do
     @moduledoc """
     Encodes and decodes YourProtocol messages.
     """

     def encode(message) do
       # Protocol-specific encoding
     end

     def decode(message) do
       # Protocol-specific decoding
     end

     # Additional helper functions for protocol-specific encoding/decoding
   end
   ```

5. **Implement Message Handler**

   Create a message module to handle protocol-specific message formats and routing:

   ```elixir
   defmodule WebSockexNova.Protocol.YourProtocol.Message do
     @moduledoc """
     Handles YourProtocol WebSocket messages.
     """

     def determine_type(message) do
       # Protocol-specific message type detection
     end

     def handle(message, state) do
       # Protocol-specific message handling
     end

     # Additional helper functions
   end
   ```

6. **Implement Protocol Adapter**

   Create an adapter that implements WebSockexNova behaviors with protocol-specific logic:

   ```elixir
   defmodule WebSockexNova.Protocol.YourProtocol.Adapter do
     @moduledoc """
     YourProtocol adapter for WebSockexNova.
     """

     use WebSockexNova.Implementations.ConnectionHandler
     use WebSockexNova.Implementations.MessageHandler
     use WebSockexNova.Implementations.SubscriptionHandler

     # Override behavior callbacks with protocol-specific implementations
   end
   ```

7. **Create Convenient Client API**

   Create a client module with a user-friendly API:

   ```elixir
   defmodule WebSockexNova.Protocol.YourProtocol.Client do
     @moduledoc """
     Client for YourProtocol WebSocket API.
     """

     use WebSockexNova.Client,
       protocol: :your_protocol,
       profile: :standard

     # Implement user-friendly API functions

     # Implement required callbacks
   end
   ```

8. **Document Protocol-Specific Details**

   Create comprehensive documentation that covers:

   - Protocol overview
   - Supported features
   - Usage examples
   - Protocol-specific configuration options
   - Error handling strategies

## Protocol-Specific Considerations

Different protocols have unique characteristics that require special handling:

### JSON-RPC Protocol

JSON-RPC protocols (like Ethereum) typically have:

- Request/response pattern with IDs
- Method-based operations
- Subscription system for real-time updates
- Error objects with standardized fields

Key considerations:
- Track request IDs to correlate responses
- Handle subscription confirmations and data notifications
- Parse error objects consistently

### STOMP Protocol

STOMP (Simple Text Oriented Messaging Protocol) has:

- Frame-based message format with commands
- Destination-based routing
- Header-based metadata
- Simple subscription model

Key considerations:
- Parse frames with command, headers, and body
- Handle connection and subscription state
- Implement heart-beating mechanism

### Phoenix Channels Protocol

Phoenix Channels protocol has:

- Topic-based messaging
- Join/leave lifecycle
- Push/response pattern
- Presence tracking

Key considerations:
- Implement proper join/leave handling
- Track channel state
- Handle push messages and replies

## Best Practices for Protocol Integrations

1. **Follow Protocol Specifications Precisely**

   Adhere strictly to protocol specifications to ensure compatibility.

2. **Implement Comprehensive Error Handling**

   Handle all error conditions defined in the protocol specification.

3. **Use Protocol-Specific Validation**

   Validate messages according to protocol rules before processing.

4. **Document Protocol Limitations**

   Clearly document any protocol features not supported by your implementation.

5. **Support Protocol Versioning**

   Consider how to handle multiple versions of the protocol if applicable.

## Testing Protocol Integrations

Test protocol integrations thoroughly:

1. **Unit Tests for Protocol Components**

   ```elixir
   defmodule WebSockexNova.Protocol.YourProtocol.CodecTest do
     use ExUnit.Case

     alias WebSockexNova.Protocol.YourProtocol.Codec

     test "encodes messages according to protocol specification" do
       message = %{field: "value"}
       assert {:ok, encoded} = Codec.encode(message)
       # Verify encoding is correct
     end

     test "decodes messages according to protocol specification" do
       encoded = "protocol-formatted-message"
       assert {:ok, decoded} = Codec.decode(encoded)
       # Verify decoding is correct
     end
   end
   ```

2. **Integration Tests with Mock Servers**

   Create mock servers that implement the protocol for integration testing.

3. **Compatibility Tests**

   Test against real protocol implementations to verify compatibility.

## Related Resources

- [WebSockexNova API Documentation](/docs/api/)
- [Behavior Specifications](/docs/api/behavior_specifications.md)
- [Telemetry Guides](/docs/guides/telemetry.md)
- [Platform Integration Guide](/docs/examples/platform_integration.md)
