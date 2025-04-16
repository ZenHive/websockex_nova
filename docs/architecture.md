# WebSockexNova Architecture Overview

## Transport Layer: Gun Integration

WebSockexNova uses [Gun](https://github.com/ninenines/gun) as its underlying WebSocket transport layer. Gun is a mature HTTP/WebSocket client for Erlang/OTP maintained by the Cowboy team, offering:

1. **Battle-tested implementation**: Robust WebSocket protocol handling
2. **Connection Management**: Built-in connection pooling and management
3. **Protocol Support**: HTTP/1.1, HTTP/2, and WebSocket protocols
4. **Modern TLS**: Comprehensive TLS options and security features

### Gun Adapter

WebSockexNova wraps Gun with a thin adapter layer:

```elixir
defmodule WebSockexNova.Transport.GunClient do
  @moduledoc """
  WebSocket client adapter for Gun.
  """

  use GenServer

  # Client API and internal implementation
  # ...
end
```

This adapter translates between the Gun API and WebSockexNova's behavior interfaces, allowing us to focus on platform-specific implementations rather than WebSocket protocol handling.

## Core Design Principles

### 1. Behavior Separation

- **Transport Core** (`websockex_nova/transport/`)
  - Protocol-agnostic WebSocket behaviors
  - Connection management (`ConnectionHandler` behavior)
  - Rate limiting (`RateLimitHandler` behavior)
  - Heartbeat management (`HeartbeatHandler` behavior)
  - Common utilities

- **Message Core** (`websockex_nova/message/`)
  - Message processing (`MessageHandler` behavior)
  - Subscription management (`SubscriptionHandler` behavior)
  - Authentication flows (`AuthHandler` behavior)
  - Error handling (`ErrorHandler` behavior)

- **Platform Core** (`websockex_nova/platform/`)
  - Platform-specific behaviors and adapters
  - Provider-specific modules (e.g., Deribit, Bybit, Slack, Discord)
  - Protocol-specific handling (e.g., Ethereum, JSON-RPC)

### 2. Implementation Libraries

#### Platform Integrations

```elixir
websockex_nova/platform/deribit/
  lib/
    adapter.ex         # Implements platform behaviors
    client.ex          # WebSocket client implementation
    message.ex         # Message processing
    subscription.ex    # Subscription management
    types.ex           # Platform-specific types
```

#### Protocol Integrations

```elixir
websockex_nova/platform/ethereum/
  lib/
    adapter.ex         # Implements platform behaviors
    client.ex          # WebSocket client implementation
    message.ex         # Message processing
    subscription.ex    # Subscription handling
    types.ex           # Protocol-specific types
```

## WebSockexNova Architecture

### 1. High-Level Component Diagram

```
                      ┌───────────────────────┐
                      │  ConnectionHandler    │
                      │    (Behavior)         │
                      └───────────────────────┘
                                 ▲
                                 │ implements
                                 │
┌─────────────────┐    ┌─────────────────────┐    ┌───────────────────┐
│SubscriptionMgr  │◄───┤  Platform Adapters  │───►│  MessageHandler   │
└─────────────────┘    │  (Deribit, Slack,   │    └───────────────────┘
                       │   Discord, etc.)     │            │
                       └─────────────────────┘            │
                                 │                         │
                                 ▼                         ▼
                       ┌─────────────────────┐    ┌───────────────────┐
                       │  ConnectionManager  │    │   ErrorHandler    │
                       └─────────────────────┘    └───────────────────┘
                                 │                         │
                                 ▼                         │
                       ┌─────────────────────┐            │
                       │  AuthHandler        │◄───────────┘
                       └─────────────────────┘
                                 │
                                 ▼
                       ┌─────────────────────┐
                       │  HeartbeatHandler   │
                       └─────────────────────┘
                                 │
                                 ▼
                       ┌─────────────────────┐
                       │   RateLimitHandler  │
                       └─────────────────────┘
```

### 2. Core Behaviors and Modules

#### 2.1 ConnectionHandler Behavior

The foundational behavior for managing WebSocket connection lifecycles:

```elixir
defmodule WebSockexNova.ConnectionHandler do
  @moduledoc """
  Behavior for managing WebSocket connection lifecycles.
  """

  @doc """
  Initializes a new WebSocket connection.
  """
  @callback init(opts :: Keyword.t()) ::
    {:ok, state :: map()} | {:error, reason :: term()}

  @doc """
  Handles a successful connection.
  """
  @callback handle_connect(conn_info :: map(), state :: map()) ::
    {:ok, new_state :: map()} | {:error, reason :: term()}

  @doc """
  Handles disconnection events.
  """
  @callback handle_disconnect(reason :: term(), state :: map()) ::
    {:reconnect, delay :: non_neg_integer(), new_state :: map()} |
    {:stop, reason :: term(), new_state :: map()}

  @doc """
  Handles WebSocket frames.
  """
  @callback handle_frame(frame_type :: atom(), frame_data :: binary(), state :: map()) ::
    {:ok, new_state :: map()} |
    {:reply, frame_type :: atom(), frame_data :: binary(), new_state :: map()} |
    {:error, reason :: term(), new_state :: map()}
end
```

#### 2.2 MessageHandler Behavior

Handles parsing, validating, and routing messages:

```elixir
defmodule WebSockexNova.MessageHandler do
  @moduledoc """
  Behavior for processing WebSocket messages.
  """

  @doc """
  Processes an incoming message and routes it appropriately.
  """
  @callback handle_message(message :: term(), state :: map()) ::
    {:ok, new_state :: map(), processed_message :: map()} |
    {:error, reason :: term(), new_state :: map()}

  @doc """
  Validates a message format.
  """
  @callback validate_message(message :: term()) ::
    :ok | {:error, reason :: term()}

  @doc """
  Determines the type of a message (e.g., subscription data, heartbeat, response).
  """
  @callback message_type(message :: term()) ::
    {:subscription, channel :: String.t()} |
    {:response, id :: term()} |
    {:heartbeat, term()} |
    {:unknown, term()}

  @doc """
  Encodes a message for sending over the WebSocket.
  """
  @callback encode_message(message :: term(), state :: map()) ::
    {:ok, encoded_message :: binary()} |
    {:error, reason :: term()}
end
```

#### 2.3 SubscriptionHandler Behavior

Manages channel/topic subscriptions:

```elixir
defmodule WebSockexNova.SubscriptionHandler do
  @moduledoc """
  Behavior for managing WebSocket subscriptions.
  """

  @doc """
  Subscribes to a channel or topic.
  """
  @callback subscribe(channel :: term(), opts :: Keyword.t(), state :: map()) ::
    {:ok, new_state :: map(), subscription_id :: String.t()} |
    {:error, reason :: term(), new_state :: map()}

  @doc """
  Unsubscribes from a channel or topic.
  """
  @callback unsubscribe(subscription_id :: String.t(), state :: map()) ::
    {:ok, new_state :: map()} |
    {:error, reason :: term(), new_state :: map()}

  @doc """
  Handles subscription responses.
  """
  @callback handle_subscription_response(response :: term(), state :: map()) ::
    {:ok, new_state :: map()} |
    {:error, reason :: term(), new_state :: map()}
end
```

#### 2.4 ErrorHandler Behavior

Manages error handling and recovery:

```elixir
defmodule WebSockexNova.ErrorHandler do
  @moduledoc """
  Behavior for handling WebSocket errors and recovery.
  """

  @doc """
  Handles an error during message processing.
  """
  @callback handle_error(error :: term(), context :: map(), state :: map()) ::
    {:retry, delay :: non_neg_integer(), new_state :: map()} |
    {:stop, reason :: term(), new_state :: map()}

  @doc """
  Determines whether to reconnect after an error.
  """
  @callback should_reconnect?(error :: term(), attempt :: non_neg_integer(), state :: map()) ::
    {boolean(), delay :: non_neg_integer() | nil}

  @doc """
  Logs an error with appropriate context.
  """
  @callback log_error(error :: term(), context :: map(), state :: map()) :: :ok
end
```

#### 2.5 AuthHandler Behavior

Manages authentication and authorization:

```elixir
defmodule WebSockexNova.AuthHandler do
  @moduledoc """
  Behavior for handling WebSocket authentication.
  """

  @doc """
  Generates authentication data for the connection.
  """
  @callback generate_auth_data(opts :: Keyword.t()) ::
    {:ok, auth_data :: term()} |
    {:error, reason :: term()}

  @doc """
  Handles authentication responses.
  """
  @callback handle_auth_response(response :: term(), state :: map()) ::
    {:ok, new_state :: map()} |
    {:error, reason :: term(), new_state :: map()}

  @doc """
  Determines if reauthentication is needed.
  """
  @callback needs_reauthentication?(state :: map()) :: boolean()
end
```

#### 2.6 HeartbeatHandler Behavior

Manages WebSocket heartbeat protocols:

```elixir
defmodule WebSockexNova.HeartbeatHandler do
  @moduledoc """
  Behavior for managing WebSocket heartbeat protocols.
  """

  @doc """
  Configures heartbeat parameters.
  """
  @callback configure(interval :: non_neg_integer(), opts :: Keyword.t(), state :: map()) ::
    {:ok, new_state :: map()} |
    {:error, reason :: term()}

  @doc """
  Processes a heartbeat message.
  """
  @callback handle_heartbeat(message :: term(), state :: map()) ::
    {:ok, new_state :: map()} |
    {:error, reason :: term(), new_state :: map()}

  @doc """
  Generates a heartbeat message.
  """
  @callback generate_heartbeat(state :: map()) ::
    {:ok, heartbeat_message :: term(), new_state :: map()} |
    {:error, reason :: term()}
end
```

#### 2.7 RateLimitHandler Behavior

Manages rate limiting:

```elixir
defmodule WebSockexNova.RateLimitHandler do
  @moduledoc """
  Behavior for handling WebSocket rate limiting.
  """

  @doc """
  Checks if an operation would exceed the rate limit.
  """
  @callback check_rate_limit(operation :: atom(), state :: map()) ::
    {:ok, new_state :: map()} |
    {:rate_limited, retry_after :: non_neg_integer(), new_state :: map()}

  @doc """
  Updates rate limit state after an operation.
  """
  @callback update_rate_limit(operation :: atom(), state :: map()) ::
    {:ok, new_state :: map()}

  @doc """
  Handles rate limit exceeded responses.
  """
  @callback handle_rate_limited(response :: term(), state :: map()) ::
    {:retry, delay :: non_neg_integer(), new_state :: map()} |
    {:error, reason :: term(), new_state :: map()}
end
```

## Telemetry Hooks and Observability

WebSockexNova implements standardized telemetry events throughout the system for metrics, logging, and alerting.

### Core Telemetry Events

```elixir
defmodule WebSockexNova.Telemetry do
  @moduledoc """
  Telemetry events for WebSocket operations.
  """

  def execute_event(event_name, measurements, metadata) do
    :telemetry.execute([:websockex_nova | event_name], measurements, metadata)
  end

  # Connection events
  def connection_started(client_id, metadata \\ %{}) do
    execute_event([:connection, :started], %{system_time: System.system_time()},
      Map.merge(%{client_id: client_id}, metadata))
  end

  def connection_completed(client_id, duration, metadata \\ %{}) do
    execute_event([:connection, :completed], %{duration: duration},
      Map.merge(%{client_id: client_id}, metadata))
  end

  # Subscription events
  def subscription_started(client_id, channel, metadata \\ %{}) do
    execute_event([:subscription, :started], %{system_time: System.system_time()},
      Map.merge(%{client_id: client_id, channel: channel}, metadata))
  end

  def subscription_completed(client_id, channel, duration, metadata \\ %{}) do
    execute_event([:subscription, :completed], %{duration: duration},
      Map.merge(%{client_id: client_id, channel: channel}, metadata))
  end

  # Message events
  def message_received(client_id, type, size, metadata \\ %{}) do
    execute_event([:message, :received], %{size: size, system_time: System.system_time()},
      Map.merge(%{client_id: client_id, type: type}, metadata))
  end

  def message_sent(client_id, type, size, metadata \\ %{}) do
    execute_event([:message, :sent], %{size: size, system_time: System.system_time()},
      Map.merge(%{client_id: client_id, type: type}, metadata))
  end

  # Error events
  def error_occurred(client_id, error_type, metadata \\ %{}) do
    execute_event([:error, :occurred], %{system_time: System.system_time()},
      Map.merge(%{client_id: client_id, error_type: error_type}, metadata))
  end

  # Reconnection events
  def reconnection_started(client_id, attempt, metadata \\ %{}) do
    execute_event([:reconnection, :started], %{system_time: System.system_time(), attempt: attempt},
      Map.merge(%{client_id: client_id}, metadata))
  end

  def reconnection_completed(client_id, attempt, duration, metadata \\ %{}) do
    execute_event([:reconnection, :completed], %{duration: duration, attempt: attempt},
      Map.merge(%{client_id: client_id}, metadata))
  end
end
```

### Telemetry Reporter Configuration

Applications consuming WebSockexNova can attach handlers to these telemetry events:

```elixir
defmodule MyApp.Telemetry do
  use Supervisor
  import Telemetry.Metrics

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  def init(_arg) do
    children = [
      # Telemetry poller for VM metrics
      {:telemetry_poller, measurements: [{:process_info, :memory}], period: 10_000},

      # Reporter(s) using the metrics below
      {TelemetryMetricsPrometheus, metrics: metrics()}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  def metrics do
    [
      # Connection metrics
      counter("websockex_nova.connection.started.count", tags: [:client_id]),
      distribution("websockex_nova.connection.completed.duration",
        tags: [:client_id], unit: {:native, :millisecond}),

      # Subscription metrics
      counter("websockex_nova.subscription.started.count", tags: [:client_id, :channel]),
      distribution("websockex_nova.subscription.completed.duration",
        tags: [:client_id, :channel], unit: {:native, :millisecond}),

      # Message metrics
      counter("websockex_nova.message.received.count", tags: [:client_id, :type]),
      summary("websockex_nova.message.received.size", tags: [:client_id, :type]),
      counter("websockex_nova.message.sent.count", tags: [:client_id, :type]),
      summary("websockex_nova.message.sent.size", tags: [:client_id, :type]),

      # Error metrics
      counter("websockex_nova.error.occurred.count", tags: [:client_id, :error_type]),

      # Reconnection metrics
      counter("websockex_nova.reconnection.started.count", tags: [:client_id]),
      distribution("websockex_nova.reconnection.completed.duration",
        tags: [:client_id], unit: {:native, :millisecond})
    ]
  end
end
```

## Platform Integration Generators

WebSockexNova provides a mix generator task for creating platform-specific integrations:

```elixir
# Generate with: mix websockex_nova.gen.integration NAME --platform PLATFORM_NAME
defmodule Mix.Tasks.WebsockexNova.Gen.Integration do
  use Mix.Task

  @shortdoc "Generates a new WebSockexNova platform integration"
  def run(args) do
    # Parse arguments
    {opts, [name], _} = OptionParser.parse(args,
      strict: [platform: :string, test: :boolean],
      aliases: [p: :platform, t: :test]
    )

    platform = Keyword.get(opts, :platform, "generic")
    generate_test = Keyword.get(opts, :test, true)

    # Generate files
    generate_adapter(name, platform)
    generate_client(name, platform)
    generate_message_handler(name, platform)
    generate_subscription_handler(name, platform)

    if generate_test do
      generate_tests(name, platform)
    end

    # Output success message
    Mix.shell().info("""

    Platform integration #{name} generated successfully!

    The following files were created:
      * lib/websockex_nova/platform/#{name}/adapter.ex
      * lib/websockex_nova/platform/#{name}/client.ex
      * lib/websockex_nova/platform/#{name}/message.ex
      * lib/websockex_nova/platform/#{name}/subscription.ex
    #{if generate_test, do: "  * test/websockex_nova/platform/#{name}/client_test.exs\n  * test/websockex_nova/platform/#{name}/message_test.exs", else: ""}

    Get started by:

    1. Configure your #{name} credentials in config/config.exs:

       config :websockex_nova, :#{name},
         api_key: System.get_env("#{String.upcase(name)}_API_KEY"),
         api_secret: System.get_env("#{String.upcase(name)}_API_SECRET"),
         endpoint: "wss://#{name}.example.com/ws"

    2. Create a client:

       client = WebSockexNova.Platform.#{String.capitalize(name)}.Client.start_link(
         name: :#{name}_client
       )

    3. Subscribe to channels:

       WebSockexNova.Platform.#{String.capitalize(name)}.Subscription.subscribe(
         client, ["channel_name"], []
       )
    """)
  end

  # File generation functions
  defp generate_adapter(name, platform) do
    # Generate adapter.ex content based on platform
  end

  defp generate_client(name, platform) do
    # Generate client.ex content based on platform
  end

  defp generate_message_handler(name, platform) do
    # Generate message.ex content based on platform
  end

  defp generate_subscription_handler(name, platform) do
    # Generate subscription.ex content based on platform
  end

  defp generate_tests(name, platform) do
    # Generate test files based on platform
  end
end
```

## Common Macros and Using Directives

WebSockexNova provides macros via `__using__` for common WebSocket client patterns:

```elixir
defmodule WebSockexNova.Macros do
  defmacro __using__(opts) do
    strategy = Keyword.get(opts, :strategy, :default)

    case strategy do
      :always_reconnect ->
        quote do
          @behaviour WebSockexNova.ConnectionHandler
          @behaviour WebSockexNova.ErrorHandler

          # Default implementation for always reconnecting
          def handle_disconnect(_reason, state) do
            {:reconnect, calculate_backoff(state), state}
          end

          def should_reconnect?(_error, _attempt, _state), do: {true, nil}

          defp calculate_backoff(state) do
            # Exponential backoff implementation
            attempt = Map.get(state, :reconnect_attempt, 0)
            base_delay = 250
            max_delay = 30_000
            min(base_delay * :math.pow(2, attempt), max_delay)
          end

          # Allow overriding
          defoverridable [handle_disconnect: 2, should_reconnect?: 3]
        end

      :fail_fast ->
        quote do
          @behaviour WebSockexNova.ConnectionHandler
          @behaviour WebSockexNova.ErrorHandler

          # Fail fast implementation
          def handle_disconnect(reason, state) do
            {:stop, reason, state}
          end

          def should_reconnect?(_error, _attempt, _state), do: {false, nil}

          # Allow overriding
          defoverridable [handle_disconnect: 2, should_reconnect?: 3]
        end

      :log_and_continue ->
        quote do
          @behaviour WebSockexNova.ConnectionHandler
          @behaviour WebSockexNova.ErrorHandler

          # Log and continue implementation
          def handle_disconnect(reason, state) do
            require Logger
            Logger.warn("Disconnected: #{inspect(reason)}. Reconnecting...")
            {:reconnect, calculate_backoff(state), state}
          end

          def should_reconnect?(_error, _attempt, _state), do: {true, nil}

          def log_error(error, context, _state) do
            require Logger
            Logger.error("Error: #{inspect(error)}, Context: #{inspect(context)}")
            :ok
          end

          defp calculate_backoff(state) do
            # Simple backoff implementation
            attempt = Map.get(state, :reconnect_attempt, 0)
            base_delay = 1000
            base_delay * (attempt + 1)
          end

          # Allow overriding
          defoverridable [handle_disconnect: 2, should_reconnect?: 3, log_error: 3]
        end

      :echo ->
        quote do
          @behaviour WebSockexNova.ConnectionHandler
          @behaviour WebSockexNova.MessageHandler

          # Echo implementation
          def handle_frame(:text, frame_data, state) do
            {:reply, :text, frame_data, state}
          end

          def handle_frame(:binary, frame_data, state) do
            {:reply, :binary, frame_data, state}
          end

          def handle_frame(_frame_type, _frame_data, state) do
            {:ok, state}
          end

          def handle_message(message, state) do
            {:ok, state, message}
          end

          # Allow overriding
          defoverridable [handle_frame: 3, handle_message: 2]
        end

      _ ->
        quote do
          # Default basic implementation with required callbacks
          @behaviour WebSockexNova.ConnectionHandler
        end
    end
  end
end
```

## Error Handling Strategy

WebSockexNova implements robust error handling with several strategies:

1. **Connection Failures**
   - Automatic reconnection with exponential backoff
   - Configurable max retry attempts
   - Customizable retry delay

2. **Message Processing Errors**
   - Structured error reporting
   - Error classification (fatal vs. non-fatal)
   - Telemetry events for monitoring

3. **Rate Limiting**
   - Proactive rate limit tracking
   - Reactive handling of rate limit errors
   - Automatic backoff when limits are approached

## Configuration Management

WebSockexNova provides flexible configuration options:

```elixir
config :websockex_nova,
  default_reconnect_delay: 1_000,
  max_reconnect_delay: 30_000,
  max_reconnect_attempts: 10,
  connection_timeout: 10_000,

  # Platform-specific configurations
  deribit: [
    api_key: {:system, "DERIBIT_API_KEY"},
    api_secret: {:system, "DERIBIT_API_SECRET"},
    endpoint: "wss://www.deribit.com/ws/api/v2"
  ]
```

## Type Safety

WebSockexNova leverages Elixir typespecs and Dialyzer for enhanced type safety:

```elixir
@type websocket_frame :: {:text, binary()} | {:binary, binary()}
@type websocket_error :: {:error, atom(), String.t()}
@type reconnection_strategy :: :exponential | :linear | :constant
```

## Common Data Structures

```elixir
defmodule WebSockexNova.Types.ConnectionState do
  @moduledoc """
  Represents the state of a WebSocket connection.
  """

  @type status :: :disconnected | :connecting | :connected | :authenticated | :error

  @type t :: %__MODULE__{
    status: status(),
    last_connected_at: DateTime.t() | nil,
    disconnect_reason: term() | nil,
    reconnection_attempts: non_neg_integer(),
    subscription_status: %{optional(String.t()) => :active | :pending | :error}
  }

  defstruct [
    status: :disconnected,
    last_connected_at: nil,
    disconnect_reason: nil,
    reconnection_attempts: 0,
    subscription_status: %{}
  ]
end

defmodule WebSockexNova.Types.Subscription do
  @moduledoc """
  Represents a channel subscription.
  """

  @type t :: %__MODULE__{
    id: String.t(),
    channel: String.t(),
    status: :active | :pending | :error,
    created_at: DateTime.t(),
    error: term() | nil
  }

  @enforce_keys [:id, :channel, :created_at]
  defstruct [:id, :channel, status: :pending, :created_at, error: nil]
end

defmodule WebSockexNova.Types.ClientConfig do
  @moduledoc """
  Configuration for a WebSocket client.
  """

  @type t :: %__MODULE__{
    name: atom() | nil,
    uri: String.t(),
    headers: [{String.t(), String.t()}],
    timeout: non_neg_integer(),
    heartbeat_interval: non_neg_integer() | nil,
    reconnect_strategy: :exponential | :linear | :constant,
    backoff_initial: non_neg_integer(),
    backoff_max: non_neg_integer(),
    max_reconnect_attempts: non_neg_integer() | :infinity
  }

  defstruct [
    name: nil,
    uri: nil,
    headers: [],
    timeout: 30_000,
    heartbeat_interval: nil,
    reconnect_strategy: :exponential,
    backoff_initial: 250,
    backoff_max: 30_000,
    max_reconnect_attempts: :infinity
  ]
end
```

## Clustering Support

WebSockexNova provides robust support for clustered environments, enhancing resilience, performance, and geo-distribution capabilities.

### Clustering Rationale

Operating WebSocket connections in a clustered environment offers several critical advantages:

1. **Geographical Proximity**
   - Deploy nodes closer to exchange/platform data centers to reduce network latency
   - Optimize connection routes for specific geographical markets
   - Improve data freshness for time-sensitive financial applications

2. **High Availability and Fault Tolerance**
   - Maintain connection state across multiple nodes
   - Provide seamless failover if a node experiences issues
   - Distribute connection load across the cluster

3. **Distributed State Management**
   - Share subscription states across the cluster
   - Coordinate rate limiting across multiple connection points
   - Synchronize authentication and authorization state

4. **Load Balancing**
   - Distribute WebSocket connections across multiple nodes
   - Prevent any single node from becoming a connection bottleneck
   - Scale horizontally to handle high-volume data streams

### Clustering Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        Node 1 (us-east)                         │
│                                                                 │
│  ┌─────────────┐     ┌──────────────┐    ┌──────────────────┐   │
│  │ WebSocket   │     │ Subscription │    │ Local Connection │   │
│  │ Connections │────►│ Handler      │───►│ State            │   │
│  └─────────────┘     └──────────────┘    └──────────────────┘   │
│         │                                         │             │
│         │                ┌──────────┐             │             │
│         └───────────────►│ Telemetry│◄────────────┘             │
│                          └──────────┘                           │
│                               │                                 │
└───────────────────────────────┼─────────────────────────────────┘
                                │
                                ▼
                        ┌───────────────┐
                        │  Distributed  │
                        │  PubSub       │
                        └───────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                       Node 2 (eu-west)                          │
│                                                                 │
│  ┌─────────────┐     ┌──────────────┐    ┌──────────────────┐   │
│  │ WebSocket   │     │ Subscription │    │ Local Connection │   │
│  │ Connections │────►│ Handler      │───►│ State            │   │
│  └─────────────┘     └──────────────┘    └──────────────────┘   │
│         │                                         │             │
│         │                ┌──────────┐             │             │
│         └───────────────►│ Telemetry│◄────────────┘             │
│                          └──────────┘                           │
└─────────────────────────────────────────────────────────────────┘
```

### WebSockexNova.Cluster Module

The `WebSockexNova.Cluster` module provides the core functionality for operating in a clustered environment:

```elixir
defmodule WebSockexNova.Cluster do
  @moduledoc """
  Provides clustering capabilities for WebSockexNova.

  This module manages node discovery, distributed subscription state,
  and geo-aware connection routing.
  """

  use GenServer
  alias Phoenix.PubSub

  @pubsub_topic "websockex_nova:cluster"

  @doc """
  Starts the cluster manager with the given options.

  ## Options

    * `:pubsub` - The PubSub module to use for communication (default: WebSockexNova.PubSub)
    * `:node_region` - Geographic region identifier for this node (e.g., "us-east", "eu-west")
    * `:strategy` - The clustering strategy to use (:active or :passive)
    * `:sync_interval` - Interval in ms to sync state across nodes (default: 30_000)
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Distributes a subscription across the cluster.
  """
  def distribute_subscription(subscription_id, channel, opts \\ []) do
    message = {:subscription, node(), subscription_id, channel, opts}
    PubSub.broadcast(pubsub_name(), @pubsub_topic, message)
    :ok
  end

  @doc """
  Distributes connection state information across the cluster.
  """
  def distribute_connection_state(client_id, state) do
    message = {:connection_state, node(), client_id, state}
    PubSub.broadcast(pubsub_name(), @pubsub_topic, message)
    :ok
  end

  @doc """
  Gets the closest node to a specific geographic region.
  """
  def get_closest_node(region) do
    # Implementation to find the closest node based on region
  end

  @doc """
  Returns the current cluster state.
  """
  def get_cluster_state do
    GenServer.call(__MODULE__, :get_cluster_state)
  end

  # GenServer callbacks
  # ...

  defp pubsub_name do
    Application.get_env(:websockex_nova, :pubsub, WebSockexNova.PubSub)
  end
end
```

### Cluster Supervisor

The clustering functionality is supervised through a dedicated supervisor:

```elixir
defmodule WebSockexNova.ClusterSupervisor do
  @moduledoc """
  Supervisor for cluster-related processes.
  """

  use Supervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    pubsub_name = Keyword.get(opts, :pubsub, WebSockexNova.PubSub)

    children = [
      # PubSub for cluster communication
      {Phoenix.PubSub, name: pubsub_name},

      # Cluster node manager
      {WebSockexNova.Cluster, Keyword.put(opts, :pubsub, pubsub_name)},

      # Distributed subscription registry
      {WebSockexNova.Cluster.SubscriptionRegistry, opts},

      # Optional: integration with libcluster for node discovery
      libcluster_child_spec(opts)
    ] |> Enum.filter(&(&1 != nil))

    Supervisor.init(children, strategy: :one_for_one)
  end

  defp libcluster_child_spec(opts) do
    if Code.ensure_loaded?(:libcluster) and Keyword.get(opts, :use_libcluster, false) do
      topologies = Application.get_env(:websockex_nova, :topologies, [])
      {Cluster.Supervisor, [topologies, [name: WebSockexNova.ClusterSupervisor.ClusterNodes]]}
    else
      nil
    end
  end
end
```

### Distributed Subscription Management

WebSockexNova provides a distributed subscription registry to maintain subscription state across the cluster:

```elixir
defmodule WebSockexNova.Cluster.SubscriptionRegistry do
  @moduledoc """
  Registry for tracking subscriptions across the cluster.
  """

  use GenServer
  alias Phoenix.PubSub

  @registry_name :websockex_nova_subscriptions
  @pubsub_topic "websockex_nova:subscriptions"

  # Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Registers a subscription in the distributed registry.
  """
  def register(subscription_id, channel, client_id, opts \\ []) do
    Registry.register(@registry_name, channel, {subscription_id, client_id, opts})
    PubSub.broadcast(pubsub_name(), @pubsub_topic, {:subscription_added, node(), subscription_id, channel, client_id})
    :ok
  end

  @doc """
  Unregisters a subscription from the distributed registry.
  """
  def unregister(subscription_id) do
    Registry.unregister(@registry_name, subscription_id)
    PubSub.broadcast(pubsub_name(), @pubsub_topic, {:subscription_removed, node(), subscription_id})
    :ok
  end

  @doc """
  Lists all active subscriptions across the cluster.
  """
  def list_subscriptions do
    Registry.select(@registry_name, [{{:"$1", :"$2", :"$3"}, [], [{{:"$1", :"$2", :"$3"}}]}])
  end

  # GenServer callbacks

  @impl true
  def init(opts) do
    pubsub = Keyword.get(opts, :pubsub, WebSockexNova.PubSub)
    Registry.start_link(keys: :duplicate, name: @registry_name)
    PubSub.subscribe(pubsub, @pubsub_topic)
    {:ok, %{pubsub: pubsub}}
  end

  # Handle subscription messages from other nodes
  @impl true
  def handle_info({:subscription_added, remote_node, id, channel, client_id}, state) do
    # Synchronize subscription state from other nodes
    {:noreply, state}
  end

  defp pubsub_name do
    Application.get_env(:websockex_nova, :pubsub, WebSockexNova.PubSub)
  end
end
```

### Distributed Rate Limiting

For applications requiring distributed rate limiting across the cluster:

```elixir
defmodule WebSockexNova.Cluster.RateLimiter do
  @moduledoc """
  Distributed rate limiting across the cluster.
  """

  alias Phoenix.PubSub

  @pubsub_topic "websockex_nova:rate_limits"

  @doc """
  Checks if an operation would exceed the distributed rate limit.
  """
  def check_rate_limit(operation, client_id) do
    case :global.whereis_name({:rate_limit, client_id, operation}) do
      :undefined ->
        # No rate limiter process exists yet, create one
        {:ok, pid} = WebSockexNova.Cluster.RateLimiter.Worker.start_link(client_id, operation)
        :global.register_name({:rate_limit, client_id, operation}, pid)
        GenServer.call(pid, :check)

      pid ->
        # Rate limiter exists, check with it
        GenServer.call(pid, :check)
    end
  end

  @doc """
  Updates the rate limit state after an operation is performed.
  """
  def update_rate_limit(operation, client_id) do
    case :global.whereis_name({:rate_limit, client_id, operation}) do
      :undefined -> :ok
      pid -> GenServer.cast(pid, :increment)
    end
  end
end

defmodule WebSockexNova.Cluster.RateLimiter.Worker do
  @moduledoc false
  use GenServer

  # Implementation of the rate limiter worker process
  # ...
end
```

### Geo-Aware Connection Management

WebSockexNova can intelligently route connections based on geographic proximity:

```elixir
defmodule WebSockexNova.Cluster.GeoRouter do
  @moduledoc """
  Routes WebSocket connections based on geographic proximity.
  """

  @doc """
  Determines the optimal node for a connection based on region.
  """
  def optimal_node(exchange, region) do
    # Get exchange location from config
    exchange_region = get_exchange_region(exchange)

    # Find nodes in the target region
    nodes_in_region = get_nodes_in_region(exchange_region)

    case nodes_in_region do
      [] ->
        # No nodes in ideal region, find closest alternative
        get_closest_node_to_region(exchange_region)

      [node] ->
        # Single node in region, use it
        node

      nodes ->
        # Multiple nodes in region, select based on load
        select_least_loaded_node(nodes)
    end
  end

  # Helper functions for node selection
  # ...
end
```

### Configuration for Clustering

WebSockexNova provides flexible configuration options for clustering:

```elixir
config :websockex_nova,
  clustering: [
    enabled: true,
    node_region: "us-east",
    discovery_method: :libcluster, # or :manual
    sync_interval: 30_000,         # ms between state syncs
    active_sync: true              # proactively sync state
  ],

  # libcluster topology configuration (if using)
  topologies: [
    websockex_nova: [
      strategy: Cluster.Strategy.Kubernetes,
      config: [
        kubernetes_selector: "app=websockex-nova",
        kubernetes_node_basename: "websockex-nova"
      ]
    ]
  ]
```

### Integration with Telemetry

Clustered operations emit specialized telemetry events:

```elixir
defmodule WebSockexNova.Cluster.Telemetry do
  @doc """
  Emits telemetry events for cluster operations.
  """
  def execute_cluster_event(event_name, measurements, metadata) do
    :telemetry.execute([:websockex_nova, :cluster | event_name], measurements,
      Map.merge(%{node: node()}, metadata))
  end

  # Specific cluster events

  def node_joined(node_name, metadata \\ %{}) do
    execute_cluster_event([:node, :joined], %{system_time: System.system_time()},
      Map.merge(%{node_name: node_name}, metadata))
  end

  def node_left(node_name, metadata \\ %{}) do
    execute_cluster_event([:node, :left], %{system_time: System.system_time()},
      Map.merge(%{node_name: node_name}, metadata))
  end

  def subscription_synchronized(subscription_id, metadata \\ %{}) do
    execute_cluster_event([:subscription, :synchronized], %{system_time: System.system_time()},
      Map.merge(%{subscription_id: subscription_id}, metadata))
  end

  # More cluster-specific telemetry events
  # ...
end
```

### Best Practices for Clustered Deployments

#### 1. Network Configuration

- Ensure reliable, low-latency connectivity between cluster nodes
- Use a dedicated private network for inter-node communication
- Configure firewalls to permit Erlang distribution protocol traffic
- Consider using encrypted distribution for security

#### 2. Geo-Distribution Strategy

- Deploy nodes near exchanges/data sources to minimize latency
- For global markets, place nodes in multiple geographic regions
- Consider using a regional node selection strategy:
  - Primary market hours: Prioritize nodes in the active market's region
  - Off-hours: Distribute load evenly or use nodes in quieter regions

#### 3. State Management

- Limit shared state to essential connection information
- Use appropriate replication strategies:
  - Full replication for critical subscription data
  - Partial replication for non-critical state
  - Local-only for ephemeral state
- Regularly prune stale subscription data

#### 4. Failure Handling

- Implement node heartbeats to detect cluster partitions
- Define clear failover policies for each subscription type
- Handle temporary network partitions gracefully
- Use local buffers to prevent message loss during failovers

#### 5. Monitoring and Debugging

- Deploy distributed tracing across the cluster
- Monitor inter-node message volume and latency
- Track subscription synchronization status
- Alert on cluster partition events

### Example: Deploying a Geo-Distributed Cluster

```elixir
# Node 1 (us-east) configuration
config :websockex_nova,
  clustering: [
    enabled: true,
    node_region: "us-east",
    discovery_method: :libcluster,
    node_selector_tag: "region=us-east"
  ],

  # Exchanges with prioritized regions
  exchanges: [
    nyse: [primary_region: "us-east", failover_regions: ["us-west", "eu-west"]],
    nasdaq: [primary_region: "us-east", failover_regions: ["us-west", "eu-west"]]
  ]

# Node 2 (eu-west) configuration
config :websockex_nova,
  clustering: [
    enabled: true,
    node_region: "eu-west",
    discovery_method: :libcluster,
    node_selector_tag: "region=eu-west"
  ],

  # Exchanges with prioritized regions
  exchanges: [
    lse: [primary_region: "eu-west", failover_regions: ["eu-central", "us-east"]],
    euronext: [primary_region: "eu-west", failover_regions: ["eu-central", "us-east"]]
  ]
```

### Using Clustering in Your Application

To leverage WebSockexNova's clustering capabilities:

```elixir
defmodule MyApp.Application do
  use Application

  def start(_type, _args) do
    children = [
      # Start the clustering supervisor
      {WebSockexNova.ClusterSupervisor, clustering_opts()},

      # Start your platform client with clustering awareness
      {WebSockexNova.Platform.Deribit.Client,
        url: "wss://www.deribit.com/ws/api/v2",
        name: :deribit_client,
        cluster_enabled: true,
        region_aware: true
      }

      # Other children...
    ]

    opts = [strategy: :one_for_one, name: MyApp.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp clustering_opts do
    [
      enabled: Application.get_env(:my_app, :clustering_enabled, true),
      node_region: Application.get_env(:my_app, :node_region, "default"),
      use_libcluster: true,
      sync_interval: 15_000
    ]
  end
end
```

With clustering enabled, your application will benefit from distributed subscription management, geo-aware connection routing, and improved resilience—essential features for high-performance financial applications operating across multiple regions.
