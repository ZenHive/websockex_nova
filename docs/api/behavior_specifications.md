# WebSockexNova Behavior Specifications

This document provides detailed specifications for all behaviors defined in WebSockexNova. Each behavior defines a contract that implementations must follow.

## Core Behaviors

### ConnectionHandler

The fundamental behavior for managing WebSocket connection lifecycle events.

```elixir
defmodule WebSockexNova.ConnectionHandler do
  @moduledoc """
  Behavior for managing WebSocket connection lifecycles.
  """

  @doc """
  Initializes a new WebSocket connection.

  Called when a connection is first being established.

  ## Parameters
    * `opts` - Keyword list of options passed to the client

  ## Returns
    * `{:ok, state}` - Successful initialization with initial state
    * `{:error, reason}` - Failed initialization with reason
  """
  @callback init(opts :: Keyword.t()) ::
    {:ok, state :: map()} | {:error, reason :: term()}

  @doc """
  Handles a successful connection.

  Called after the WebSocket connection is successfully established.

  ## Parameters
    * `conn_info` - Map containing connection information
    * `state` - Current state

  ## Returns
    * `{:ok, new_state}` - Connection handled successfully
    * `{:error, reason}` - Connection error
  """
  @callback handle_connect(conn_info :: map(), state :: map()) ::
    {:ok, new_state :: map()} | {:error, reason :: term()}

  @doc """
  Handles disconnection events.

  Called when the WebSocket connection is closed or lost.

  ## Parameters
    * `reason` - Reason for disconnection
    * `state` - Current state

  ## Returns
    * `{:reconnect, delay, new_state}` - Attempt reconnection after delay (ms)
    * `{:stop, reason, new_state}` - Stop the connection process
  """
  @callback handle_disconnect(reason :: term(), state :: map()) ::
    {:reconnect, delay :: non_neg_integer(), new_state :: map()} |
    {:stop, reason :: term(), new_state :: map()}

  @doc """
  Handles WebSocket frames.

  Called for each frame received from the WebSocket connection.

  ## Parameters
    * `frame_type` - Type of WebSocket frame (:text, :binary, etc.)
    * `frame_data` - Binary data contained in the frame
    * `state` - Current state

  ## Returns
    * `{:ok, new_state}` - Frame handled successfully
    * `{:reply, frame_type, frame_data, new_state}` - Reply with a frame
    * `{:error, reason, new_state}` - Error handling frame
  """
  @callback handle_frame(frame_type :: atom(), frame_data :: binary(), state :: map()) ::
    {:ok, new_state :: map()} |
    {:reply, frame_type :: atom(), frame_data :: binary(), new_state :: map()} |
    {:error, reason :: term(), new_state :: map()}

  @optional_callbacks [init: 1]
end
```

### MessageHandler

Handles parsing, validation, and routing of WebSocket messages.

```elixir
defmodule WebSockexNova.MessageHandler do
  @moduledoc """
  Behavior for processing WebSocket messages.
  """

  @doc """
  Processes an incoming message and routes it appropriately.

  ## Parameters
    * `message` - The decoded message content
    * `state` - Current state

  ## Returns
    * `{:ok, new_state, processed_message}` - Message processed successfully
    * `{:error, reason, new_state}` - Error processing message
  """
  @callback handle_message(message :: term(), state :: map()) ::
    {:ok, new_state :: map(), processed_message :: map()} |
    {:error, reason :: term(), new_state :: map()}

  @doc """
  Validates a message format.

  ## Parameters
    * `message` - The message to validate

  ## Returns
    * `:ok` - Message is valid
    * `{:error, reason}` - Message is invalid
  """
  @callback validate_message(message :: term()) ::
    :ok | {:error, reason :: term()}

  @doc """
  Determines the type of a message.

  ## Parameters
    * `message` - The message to categorize

  ## Returns
    * `{:subscription, channel}` - Message is subscription data
    * `{:response, id}` - Message is a response to a request
    * `{:heartbeat, term()}` - Message is a heartbeat
    * `{:unknown, term()}` - Message type is unknown
  """
  @callback message_type(message :: term()) ::
    {:subscription, channel :: String.t()} |
    {:response, id :: term()} |
    {:heartbeat, term()} |
    {:unknown, term()}

  @doc """
  Encodes a message for sending over the WebSocket.

  ## Parameters
    * `message` - The message to encode
    * `state` - Current state

  ## Returns
    * `{:ok, encoded_message}` - Message encoded successfully
    * `{:error, reason}` - Error encoding message
  """
  @callback encode_message(message :: term(), state :: map()) ::
    {:ok, encoded_message :: binary()} |
    {:error, reason :: term()}

  @optional_callbacks [validate_message: 1]
end
```

### SubscriptionHandler

Manages channel/topic subscriptions for the WebSocket connection.

```elixir
defmodule WebSockexNova.SubscriptionHandler do
  @moduledoc """
  Behavior for managing WebSocket subscriptions.
  """

  @doc """
  Subscribes to a channel or topic.

  ## Parameters
    * `channel` - Channel or topic to subscribe to
    * `opts` - Subscription options
    * `state` - Current state

  ## Returns
    * `{:ok, new_state, subscription_id}` - Subscription successful
    * `{:error, reason, new_state}` - Subscription failed
  """
  @callback subscribe(channel :: term(), opts :: Keyword.t(), state :: map()) ::
    {:ok, new_state :: map(), subscription_id :: String.t()} |
    {:error, reason :: term(), new_state :: map()}

  @doc """
  Unsubscribes from a channel or topic.

  ## Parameters
    * `subscription_id` - ID of the subscription to cancel
    * `state` - Current state

  ## Returns
    * `{:ok, new_state}` - Unsubscription successful
    * `{:error, reason, new_state}` - Unsubscription failed
  """
  @callback unsubscribe(subscription_id :: String.t(), state :: map()) ::
    {:ok, new_state :: map()} |
    {:error, reason :: term(), new_state :: map()}

  @doc """
  Handles subscription responses.

  ## Parameters
    * `response` - Subscription-related response message
    * `state` - Current state

  ## Returns
    * `{:ok, new_state}` - Response handled successfully
    * `{:error, reason, new_state}` - Error handling response
  """
  @callback handle_subscription_response(response :: term(), state :: map()) ::
    {:ok, new_state :: map()} |
    {:error, reason :: term(), new_state :: map()}
end
```

### ErrorHandler

Manages error handling and recovery strategies for WebSocket errors.

```elixir
defmodule WebSockexNova.ErrorHandler do
  @moduledoc """
  Behavior for handling WebSocket errors and recovery.
  """

  @doc """
  Handles an error during message processing.

  ## Parameters
    * `error` - The error that occurred
    * `context` - Context information about where the error occurred
    * `state` - Current state

  ## Returns
    * `{:retry, delay, new_state}` - Retry the operation after delay (ms)
    * `{:stop, reason, new_state}` - Stop the connection process
  """
  @callback handle_error(error :: term(), context :: map(), state :: map()) ::
    {:retry, delay :: non_neg_integer(), new_state :: map()} |
    {:stop, reason :: term(), new_state :: map()}

  @doc """
  Determines whether to reconnect after an error.

  ## Parameters
    * `error` - The error that occurred
    * `attempt` - Current reconnection attempt number
    * `state` - Current state

  ## Returns
    * `{boolean(), delay | nil}` - Whether to reconnect and optional delay
  """
  @callback should_reconnect?(error :: term(), attempt :: non_neg_integer(), state :: map()) ::
    {boolean(), delay :: non_neg_integer() | nil}

  @doc """
  Logs an error with appropriate context.

  ## Parameters
    * `error` - The error that occurred
    * `context` - Context information about where the error occurred
    * `state` - Current state

  ## Returns
    * `:ok` - Error logged successfully
  """
  @callback log_error(error :: term(), context :: map(), state :: map()) :: :ok

  @optional_callbacks [log_error: 3]
end
```

### AuthHandler

Manages authentication and authorization flows for WebSocket connections.

```elixir
defmodule WebSockexNova.AuthHandler do
  @moduledoc """
  Behavior for handling WebSocket authentication.
  """

  @doc """
  Generates authentication data for the connection.

  ## Parameters
    * `opts` - Authentication options

  ## Returns
    * `{:ok, auth_data}` - Authentication data generated successfully
    * `{:error, reason}` - Error generating authentication data
  """
  @callback generate_auth_data(opts :: Keyword.t()) ::
    {:ok, auth_data :: term()} |
    {:error, reason :: term()}

  @doc """
  Handles authentication responses.

  ## Parameters
    * `response` - Authentication response message
    * `state` - Current state

  ## Returns
    * `{:ok, new_state}` - Authentication response handled successfully
    * `{:error, reason, new_state}` - Error handling authentication response
  """
  @callback handle_auth_response(response :: term(), state :: map()) ::
    {:ok, new_state :: map()} |
    {:error, reason :: term(), new_state :: map()}

  @doc """
  Determines if reauthentication is needed.

  ## Parameters
    * `state` - Current state

  ## Returns
    * `boolean()` - Whether reauthentication is needed
  """
  @callback needs_reauthentication?(state :: map()) :: boolean()
end
```

### HeartbeatHandler

Manages WebSocket heartbeat protocols for keeping connections alive.

```elixir
defmodule WebSockexNova.HeartbeatHandler do
  @moduledoc """
  Behavior for managing WebSocket heartbeat protocols.
  """

  @doc """
  Configures heartbeat parameters.

  ## Parameters
    * `interval` - Heartbeat interval in milliseconds
    * `opts` - Additional heartbeat options
    * `state` - Current state

  ## Returns
    * `{:ok, new_state}` - Heartbeat configured successfully
    * `{:error, reason}` - Error configuring heartbeat
  """
  @callback configure(interval :: non_neg_integer(), opts :: Keyword.t(), state :: map()) ::
    {:ok, new_state :: map()} |
    {:error, reason :: term()}

  @doc """
  Processes a heartbeat message.

  ## Parameters
    * `message` - Heartbeat message
    * `state` - Current state

  ## Returns
    * `{:ok, new_state}` - Heartbeat processed successfully
    * `{:error, reason, new_state}` - Error processing heartbeat
  """
  @callback handle_heartbeat(message :: term(), state :: map()) ::
    {:ok, new_state :: map()} |
    {:error, reason :: term(), new_state :: map()}

  @doc """
  Generates a heartbeat message.

  ## Parameters
    * `state` - Current state

  ## Returns
    * `{:ok, heartbeat_message, new_state}` - Heartbeat message generated
    * `{:error, reason}` - Error generating heartbeat message
  """
  @callback generate_heartbeat(state :: map()) ::
    {:ok, heartbeat_message :: term(), new_state :: map()} |
    {:error, reason :: term()}
end
```

### RateLimitHandler

Manages rate limiting for WebSocket connections and API calls.

```elixir
defmodule WebSockexNova.RateLimitHandler do
  @moduledoc """
  Behavior for handling WebSocket rate limiting.
  """

  @doc """
  Checks if an operation would exceed the rate limit.

  ## Parameters
    * `operation` - The operation to check
    * `state` - Current state

  ## Returns
    * `{:ok, new_state}` - Operation is within rate limits
    * `{:rate_limited, retry_after, new_state}` - Operation would exceed rate limits
  """
  @callback check_rate_limit(operation :: atom(), state :: map()) ::
    {:ok, new_state :: map()} |
    {:rate_limited, retry_after :: non_neg_integer(), new_state :: map()}

  @doc """
  Updates rate limit state after an operation.

  ## Parameters
    * `operation` - The operation that was executed
    * `state` - Current state

  ## Returns
    * `{:ok, new_state}` - Rate limit state updated successfully
  """
  @callback update_rate_limit(operation :: atom(), state :: map()) ::
    {:ok, new_state :: map()}

  @doc """
  Handles rate limit exceeded responses.

  ## Parameters
    * `response` - Rate limit response message
    * `state` - Current state

  ## Returns
    * `{:retry, delay, new_state}` - Retry after delay (ms)
    * `{:error, reason, new_state}` - Error handling rate limit
  """
  @callback handle_rate_limited(response :: term(), state :: map()) ::
    {:retry, delay :: non_neg_integer(), new_state :: map()} |
    {:error, reason :: term(), new_state :: map()}
end
```

## Clustering Behaviors

### ClusterAware

Optional behavior for components that need to be aware of cluster state changes.

```elixir
defmodule WebSockexNova.ClusterAware do
  @moduledoc """
  Behavior for components that need to respond to cluster state changes.
  """

  @doc """
  Handles cluster node state changes.

  ## Parameters
    * `change_type` - Type of node change (:joined, :left, :reconnected)
    * `node_name` - Name of the node that changed
    * `state` - Current state

  ## Returns
    * `{:ok, new_state}` - Node change handled successfully
    * `{:error, reason, new_state}` - Error handling node change
  """
  @callback handle_node_transition(change_type :: atom(), node_name :: atom(), state :: map()) ::
    {:ok, new_state :: map()} |
    {:error, reason :: term(), new_state :: map()}

  @doc """
  Processes a state update received from another cluster node.

  ## Parameters
    * `update` - State update data
    * `source_node` - Node that sent the update
    * `state` - Current state

  ## Returns
    * `{:ok, new_state}` - Update processed successfully
    * `{:error, reason, new_state}` - Error processing update
  """
  @callback handle_cluster_update(update :: term(), source_node :: atom(), state :: map()) ::
    {:ok, new_state :: map()} |
    {:error, reason :: term(), new_state :: map()}

  @doc """
  Prepares local state for synchronization to other nodes.

  ## Parameters
    * `state` - Current state

  ## Returns
    * `{:ok, sync_data}` - State prepared for synchronization
    * `{:error, reason}` - Error preparing state for synchronization
  """
  @callback prepare_state_sync(state :: map()) ::
    {:ok, sync_data :: term()} |
    {:error, reason :: term()}
end
```

## Advanced Behaviors

### CircuitBreaker

Optional behavior for implementing circuit breaker patterns on WebSocket connections.

```elixir
defmodule WebSockexNova.CircuitBreaker do
  @moduledoc """
  Behavior for implementing circuit breaker patterns.
  """

  @doc """
  Checks if a circuit is open (i.e., temporary suspension of operations).

  ## Parameters
    * `operation` - The operation being attempted
    * `state` - Current state

  ## Returns
    * `{:closed, new_state}` - Circuit is closed, operation allowed
    * `{:open, retry_after, new_state}` - Circuit is open, retry after delay
  """
  @callback check_circuit(operation :: atom(), state :: map()) ::
    {:closed, new_state :: map()} |
    {:open, retry_after :: non_neg_integer(), new_state :: map()}

  @doc """
  Records a successful operation, potentially closing an open circuit.

  ## Parameters
    * `operation` - The operation that succeeded
    * `state` - Current state

  ## Returns
    * `{:ok, new_state}` - Success recorded
  """
  @callback record_success(operation :: atom(), state :: map()) ::
    {:ok, new_state :: map()}

  @doc """
  Records a failure, potentially opening the circuit.

  ## Parameters
    * `operation` - The operation that failed
    * `error` - The error that occurred
    * `state` - Current state

  ## Returns
    * `{:ok, new_state}` - Failure recorded
  """
  @callback record_failure(operation :: atom(), error :: term(), state :: map()) ::
    {:ok, new_state :: map()}

  @doc """
  Resets circuit breaker state.

  ## Parameters
    * `state` - Current state

  ## Returns
    * `{:ok, new_state}` - Circuit breaker reset successfully
  """
  @callback reset_circuit(state :: map()) ::
    {:ok, new_state :: map()}
end
```

## Default Behavior Implementations

WebSockexNova provides default implementations for all core behaviors. These implementations can be reused by platform adapters through `__using__` macros, allowing you to focus on platform-specific logic rather than reimplementing common WebSocket functionality.

### Default Implementation Modules

Each behavior has a corresponding default implementation module:

```
lib/
├── websockex_nova/
    ├── behaviors/                   # Behavior definitions
    │   ├── connection_handler.ex    # Behavior specification
    │   ├── message_handler.ex
    │   ├── error_handler.ex
    │   └── ...
    │
    ├── implementations/             # Default implementations of behaviors
    │   ├── connection_handler.ex    # Default implementation
    │   ├── message_handler.ex
    │   ├── error_handler.ex
    │   └── ...
```

### Using Default Implementations

To use a default implementation in your adapter:

```elixir
defmodule MyApp.WebSocket.DeribitClient do
  use WebSockexNova.Implementations.ConnectionHandler
  use WebSockexNova.Implementations.MessageHandler
  use WebSockexNova.Implementations.SubscriptionHandler

  # Only override the callbacks that need platform-specific behavior
  def handle_message(message, state) do
    # Custom Deribit-specific message handling
    decoded = Jason.decode!(message)
    # ...custom processing...
    {:ok, state, processed_message}
  end
end
```

### Example Default Implementation

Here's an example of how default implementations are structured:

```elixir
defmodule WebSockexNova.Implementations.ConnectionHandler do
  @moduledoc """
  Default implementation of ConnectionHandler behavior.
  """

  defmacro __using__(_opts) do
    quote do
      @behaviour WebSockexNova.ConnectionHandler

      # Default implementation of init/1
      def init(opts) do
        {:ok, %{
          connection_opts: opts,
          retry_count: 0,
          subscriptions: %{}
        }}
      end

      # Default implementation of handle_connect/2
      def handle_connect(conn_info, state) do
        Logger.info("Connected to WebSocket: #{inspect(conn_info)}")
        {:ok, Map.put(state, :connected_at, DateTime.utc_now())}
      end

      # Default implementation of handle_disconnect/2
      def handle_disconnect(reason, state) do
        retry_count = Map.get(state, :retry_count, 0)
        max_retries = Map.get(state, :connection_opts, [])
                      |> Keyword.get(:max_retries, 10)

        if retry_count < max_retries do
          delay = calculate_backoff(retry_count)
          Logger.info("Disconnected: #{inspect(reason)}. Reconnecting in #{delay}ms")
          {:reconnect, delay, Map.update(state, :retry_count, 1, &(&1 + 1))}
        else
          Logger.error("Disconnected: #{inspect(reason)}. Max retries exceeded.")
          {:stop, :max_retries_exceeded, state}
        end
      end

      # Default implementation of handle_frame/3
      def handle_frame(frame_type, frame_data, state) do
        case frame_type do
          :text ->
            {:ok, state}
          :binary ->
            {:ok, state}
          :ping ->
            {:reply, :pong, "", state}
          :pong ->
            {:ok, Map.put(state, :last_pong, DateTime.utc_now())}
          _ ->
            Logger.warn("Unhandled frame type: #{inspect(frame_type)}")
            {:ok, state}
        end
      end

      # Helper function for exponential backoff
      defp calculate_backoff(retry_count) do
        # Exponential backoff with jitter
        base = :math.pow(2, retry_count) * 100
        max_delay = 30_000  # 30 seconds
        delay = min(base, max_delay)
        # Add jitter to prevent thundering herd problem
        trunc(delay * (0.5 + :rand.uniform() * 0.5))
      end

      # Allow overriding any of the default implementations
      defoverridable [init: 1, handle_connect: 2, handle_disconnect: 2, handle_frame: 3]
    end
  end
end
```

### Customizing Default Implementations

You can customize the default implementations by overriding specific callbacks:

```elixir
defmodule MyApp.WebSocket.DeribitClient do
  use WebSockexNova.Implementations.ConnectionHandler

  # Override only the handle_frame callback
  def handle_frame(:text, frame_data, state) do
    # Custom text frame handling for Deribit
    parsed = Jason.decode!(frame_data)
    process_deribit_message(parsed, state)
  end

  # Use default implementations for other callbacks

  defp process_deribit_message(parsed, state) do
    # Deribit-specific processing logic...
    {:ok, updated_state}
  end
end
```

## Creating Platform-Specific Adapters

When creating a new platform adapter:

1. **Use Default Implementations**: Start by using the default implementations for all behaviors.
2. **Override Platform-Specific Logic**: Override only the callbacks that need platform-specific behavior.
3. **Organize in Platform Directory**: Place your adapter in the appropriate platform directory.

Example adapter structure:

```elixir
defmodule WebSockexNova.Platform.Deribit.Adapter do
  use WebSockexNova.Implementations.ConnectionHandler
  use WebSockexNova.Implementations.MessageHandler
  use WebSockexNova.Implementations.SubscriptionHandler
  use WebSockexNova.Implementations.AuthHandler

  # Override authentication for Deribit
  def generate_auth_data(opts) do
    # Deribit-specific authentication logic
    api_key = Keyword.fetch!(opts, :api_key)
    api_secret = Keyword.fetch!(opts, :api_secret)
    # ... generate Deribit auth payload ...
    {:ok, auth_payload}
  end

  # Override message encoding for Deribit
  def encode_message(message, state) do
    # Deribit-specific message encoding
    encoded = Jason.encode!(message)
    {:ok, encoded}
  end

  # Other overrides as needed...
end
```

## Using Behaviors and Implementations

To implement a behavior, create a module that implements all required callbacks:

```elixir
defmodule MyApp.CustomConnectionHandler do
  @behaviour WebSockexNova.ConnectionHandler

  # Implement required callbacks
  def handle_connect(conn_info, state) do
    # Custom implementation
    {:ok, state}
  end

  def handle_disconnect(reason, state) do
    # Custom implementation
    {:reconnect, 1000, state}
  end

  def handle_frame(frame_type, frame_data, state) do
    # Custom implementation
    {:ok, state}
  end

  # Optional callbacks can be omitted if the default is suitable
end
```

## Extending Behaviors

You can extend behaviors by creating custom behaviors that include the original:

```elixir
defmodule MyApp.EnhancedConnectionHandler do
  @moduledoc """
  Enhanced connection handler with additional callbacks.
  """

  # Include all WebSockexNova.ConnectionHandler callbacks
  @callback init(opts :: Keyword.t()) ::
    {:ok, state :: map()} | {:error, reason :: term()}
  @callback handle_connect(conn_info :: map(), state :: map()) ::
    {:ok, new_state :: map()} | {:error, reason :: term()}
  @callback handle_disconnect(reason :: term(), state :: map()) ::
    {:reconnect, delay :: non_neg_integer(), new_state :: map()} |
    {:stop, reason :: term(), new_state :: map()}
  @callback handle_frame(frame_type :: atom(), frame_data :: binary(), state :: map()) ::
    {:ok, new_state :: map()} |
    {:reply, frame_type :: atom(), frame_data :: binary(), new_state :: map()} |
    {:error, reason :: term(), new_state :: map()}

  # Add custom callbacks
  @callback handle_special_event(event :: term(), state :: map()) ::
    {:ok, new_state :: map()} | {:error, reason :: term()}
end
```

## Behavior Composition

WebSockexNova platform implementations often compose multiple behaviors:

```elixir
defmodule WebSockexNova.Platform.Deribit.Client do
  @behaviour WebSockexNova.ConnectionHandler
  @behaviour WebSockexNova.MessageHandler
  @behaviour WebSockexNova.SubscriptionHandler
  @behaviour WebSockexNova.AuthHandler
  @behaviour WebSockexNova.HeartbeatHandler
  @behaviour WebSockexNova.RateLimitHandler

  # Implementation of all required callbacks...
end
```
