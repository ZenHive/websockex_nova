# WebSockexNova Architecture Overview

> **Note:** This document provides a high-level architectural overview of WebSockexNova. For implementation details and comprehensive examples, please refer to the API documentation and guides in the `docs/guides/` directory.

## Transport Layer: Gun Integration

WebSockexNova uses [Gun](https://github.com/ninenines/gun) as its underlying WebSocket transport layer. Gun is a mature HTTP/WebSocket client for Erlang/OTP maintained by the Cowboy team, offering:

1. **Battle-tested implementation**: Robust WebSocket protocol handling
2. **Connection Management**: Built-in connection pooling and management
3. **Protocol Support**: HTTP/1.1, HTTP/2, and WebSocket protocols
4. **Modern TLS**: Comprehensive TLS options and security features

### Gun Adapter

WebSockexNova wraps Gun with a thin adapter layer that translates between the Gun API and WebSockexNova's behavior interfaces.

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

```
websockex_nova/platform/deribit/
  lib/
    adapter.ex         # Implements platform behaviors
    client.ex          # WebSocket client implementation
    message.ex         # Message processing
    subscription.ex    # Subscription management
    types.ex           # Platform-specific types
```

#### Protocol Integrations

```
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

### 2. Core Behaviors and Modules Overview

WebSockexNova defines a set of behaviors that establish contracts for different aspects of WebSocket communication. Each behavior serves a specific purpose and can be customized based on application requirements.

#### 2.1 ConnectionHandler Behavior

Manages WebSocket connection lifecycles. Key callbacks include:
- `init/1`: Initialize connection state
- `handle_connect/2`: Handle successful connections
- `handle_disconnect/2`: Handle disconnection events
- `handle_frame/3`: Process WebSocket frames

#### 2.2 MessageHandler Behavior

Handles message parsing, validation, and routing with callbacks:
- `handle_message/2`: Process incoming messages
- `validate_message/1`: Validate message formats
- `message_type/1`: Determine message type/category
- `encode_message/2`: Encode messages for sending

#### 2.3 SubscriptionHandler Behavior

Manages channel/topic subscriptions with callbacks:
- `subscribe/3`: Subscribe to channels/topics
- `unsubscribe/2`: Unsubscribe from channels/topics
- `handle_subscription_response/2`: Process subscription responses

#### 2.4 ErrorHandler Behavior

Manages error handling and recovery with callbacks:
- `handle_error/3`: Process errors during message handling
- `should_reconnect?/3`: Determine reconnection strategy
- `log_error/3`: Log errors with appropriate context

#### 2.5 AuthHandler Behavior

Handles authentication flows with callbacks:
- `generate_auth_data/1`: Generate authentication data
- `handle_auth_response/2`: Process authentication responses
- `needs_reauthentication?/1`: Check if reauthentication is needed

> **Note:** The specific implementations of these behaviors depend on the platform being integrated. Each platform may require different authentication mechanisms, reconnection strategies, and message formats.

> **For Complete API Documentation:** See `docs/api/` for full behavior specifications and callback signatures.

### 3. Behavior Completeness and Extensibility

While the core behaviors provide a solid foundation for most WebSocket interactions, they can be extended to address specific use cases or advanced scenarios.

#### 3.1 Potential Extensions

The current behavior set may benefit from these additional capabilities:

1. **Advanced Error Recovery**
   - **Transient vs. Persistent Error Distinction**: Add specialized callbacks to handle different error types
   - **Circuit Breaker Pattern**: Add support for temporarily disabling connections after repeated failures
   - **Custom Recovery Strategies**: Allow platform-specific recovery procedures

2. **Clustering-Aware Callbacks**
   - **Distributed State Synchronization**: Add callbacks to react to state changes from other nodes
   - `handle_cluster_update/2`: Process state updates from other cluster nodes
   - `handle_node_transition/3`: React to node joins/leaves in the cluster

3. **Extended Telemetry Hooks**
   - **Custom Metric Collection**: Allow platform-specific performance metrics
   - **Event Filtering**: Provide mechanisms to control telemetry verbosity

#### 3.2 Behavior Evolution Strategy

As the library evolves, new behaviors and callbacks will be added judiciously:

1. **Versioning Approach**:
   - Optional callbacks will be added with default implementations
   - Breaking changes will be clearly documented and follow semantic versioning

2. **Extension Mechanisms**:
   - Protocol extensions through behavior composition
   - Platform-specific behaviors implemented as separate modules
   - Configuration-driven behavior selection

## Telemetry and Observability

WebSockexNova implements standardized telemetry events for monitoring performance, reliability, and behavior.

### Core Telemetry Events

The library emits telemetry events for key operations:

- **Connection Events**: Track connection lifecycle (start, complete, disconnect)
- **Subscription Events**: Monitor subscription operations (subscribe, unsubscribe)
- **Message Events**: Measure message throughput, size, and processing time
- **Error Events**: Capture error frequency and types
- **Reconnection Events**: Monitor reconnection attempts and success rates

> **Note:** See `docs/guides/telemetry.md` for complete details on available events and integration examples with common monitoring systems.

### Profile-Based Telemetry

Each implementation profile includes appropriate telemetry settings:

- **Financial Profile**: High-resolution metrics with detailed message tracking
- **Standard Profile**: Balanced metrics focused on connection stability
- **Lightweight Profile**: Minimal metrics for essential monitoring

## Clustering Support

For applications requiring high availability and geo-distribution, WebSockexNova provides clustering capabilities.

### Key Clustering Features

- **Node Discovery**: Automatic detection of cluster nodes (optional libcluster integration)
- **Distributed Subscriptions**: Subscription state shared across nodes
- **Geo-Aware Routing**: Connect via the node with closest proximity to target service
- **Distributed Rate Limiting**: Coordinate rate limits across nodes
- **Node Failover**: Seamlessly transfer connections if a node becomes unavailable

> **Note:** See `docs/guides/clustering.md` for detailed clustering configuration and deployment patterns.

## Document Organization

To maintain clarity while providing complete information, WebSockexNova documentation is organized into several components:

1. **Architecture Overview** (this document): High-level design and concepts
2. **API Documentation** (`docs/api/`): Complete behavior specifications
3. **Implementation Guides** (`docs/guides/`):
   - Platform integration tutorials
   - Error handling patterns
   - Telemetry configuration
   - Clustering setup
4. **Examples** (`docs/examples/`):
   - Financial platform integration examples
   - Chat/messaging platform examples
   - Custom behavior implementations

## Implementation Profiles

WebSockexNova is designed to support different application profiles with varying requirements for performance, reliability, and complexity.

### 1. Financial Platform Profile

Optimized for high-frequency trading, market data, and financial applications requiring extreme reliability.

```elixir
# Example configuration for financial platforms
config :websockex_nova,
  profile: :financial,
  reconnection: [
    strategy: :exponential_backoff_with_jitter,
    max_attempts: :infinity,
    initial_delay: 100,  # milliseconds
    max_delay: 30_000,   # 30 seconds
    jitter_factor: 0.25
  ],
  connection: [
    timeout: 5_000,      # 5 seconds
    ping_interval: 15_000,
    pong_timeout: 5_000
  ],
  telemetry: [
    level: :detailed,    # More granular metrics
    connection_events: true,
    message_events: true,
    error_events: true
  ],
  clustering: [
    enabled: true,
    strategy: :geo_aware  # Route to closest node
  ]
```

**Key Characteristics:**
- Aggressive reconnection strategies
- Comprehensive error tracking and automatic recovery
- High-resolution telemetry
- Distributed rate limiting
- Subscription persistence across reconnects
- Support for geo-distribution and failover

### 2. Standard Platform Profile

Balanced approach for general-purpose WebSocket applications like chat, notifications, and general real-time data.

```elixir
# Example configuration for standard platforms
config :websockex_nova,
  profile: :standard,
  reconnection: [
    strategy: :linear_backoff,
    max_attempts: 10,
    initial_delay: 1_000,  # 1 second
    max_delay: 60_000      # 1 minute
  ],
  connection: [
    timeout: 10_000,       # 10 seconds
    ping_interval: 30_000,
    pong_timeout: 10_000
  ],
  telemetry: [
    level: :standard,
    connection_events: true,
    message_events: false,  # Less metric volume
    error_events: true
  ],
  clustering: [
    enabled: false         # Simpler single-node deployment
  ]
```

**Key Characteristics:**
- Reasonable reconnection attempts with escalation
- Standard error recovery for common failures
- Balanced telemetry with focus on critical events
- Local rate limiting
- Simplified deployment model

### 3. Lightweight Platform Profile

Minimalist approach for simple WebSocket integrations like webhooks, simple chat, or non-critical notifications.

```elixir
# Example configuration for lightweight platforms
config :websockex_nova,
  profile: :lightweight,
  reconnection: [
    strategy: :simple,
    max_attempts: 3,        # Limited retries
    initial_delay: 2_000,   # 2 seconds
    max_delay: 10_000       # 10 seconds
  ],
  connection: [
    timeout: 15_000,        # 15 seconds
    ping_interval: 60_000,  # Less frequent heartbeats
    pong_timeout: 15_000
  ],
  telemetry: [
    level: :minimal,        # Basic metrics only
    connection_events: true,
    message_events: false,
    error_events: true
  ],
  clustering: [
    enabled: false
  ]
```

**Key Characteristics:**
- Simple reconnection strategy with limited attempts
- Basic error handling with fail-fast approach
- Minimal telemetry focused on critical events
- No clustering requirements
- Lower resource utilization

### 4. Custom Profile

Applications can define custom profiles by overriding specific behaviors:

```elixir
defmodule MyApp.CustomConnectionHandler do
  @behaviour WebSockexNova.ConnectionHandler

  # Custom implementation optimized for specific use case
end

# Application configuration
config :my_app, :websocket,
  handler: MyApp.CustomConnectionHandler,
  # Other custom options
```

## Common Macros and Using Directives

WebSockexNova provides macros for common WebSocket client patterns through `__using__` directives:

```elixir
defmodule MyApp.WebSocket.DeribitClient do
  use WebSockexNova.Client,
    strategy: :always_reconnect,  # Reconnection strategy
    platform: :deribit,           # Platform-specific adapters
    profile: :financial           # Configuration profile

  # Custom implementation or overrides as needed
end
```

Available strategies include:
- `:always_reconnect` - Persistent connection with exponential backoff
- `:fail_fast` - Limited reconnection attempts
- `:log_and_continue` - Logs errors but continues reconnection attempts
- `:echo` - Simple echo client for testing

## Advanced Patterns

### 1. Error Handling Strategies

WebSockexNova provides multiple error handling approaches:

#### Financial-Grade Error Handling

```elixir
# This example is simplified - implementation details are in separate guides
defmodule MyApp.FinancialErrorHandler do
  @behaviour WebSockexNova.ErrorHandler

  def handle_error(error, context, state) do
    # Advanced error categorization
    case categorize_error(error) do
      :transient ->
        # Recoverable errors get exponential backoff with jitter
        delay = calculate_delay(state)
        {:retry, delay, Map.update(state, :retry_count, 1, &(&1 + 1))}

      :platform_error ->
        # Exchange-specific error handling
        handle_platform_error(error, context, state)

      :critical ->
        # Alert and fail for critical errors
        alert_operations_team(error, context)
        {:stop, error, state}
    end
  end

  def should_reconnect?(_error, attempt, state) when attempt > 20 do
    # Switch to longer delay after many attempts
    {true, :timer.minutes(1)}
  end

  def should_reconnect?(_error, _attempt, _state), do: {true, nil}

  # Private implementation details...
end
```

#### Lightweight Error Handling

```elixir
# This example is simplified - implementation details are in separate guides
defmodule MyApp.LightweightErrorHandler do
  @behaviour WebSockexNova.ErrorHandler

  def handle_error(error, context, state) do
    # Simple logging
    Logger.error("WebSocket error: #{inspect(error)}")

    # Limited retries
    if Map.get(state, :retry_count, 0) < 3 do
      {:retry, 2000, Map.update(state, :retry_count, 1, &(&1 + 1))}
    else
      {:stop, error, state}
    end
  end

  def should_reconnect?(_error, attempt, _state) when attempt > 3, do: {false, nil}
  def should_reconnect?(_error, _attempt, _state), do: {true, 2000}

  # Other callback implementations...
end
```

### 2. Custom Use Cases

#### High-Frequency Trading Integration

For applications requiring extremely low latency and high reliability:

1. **Connection Optimization**:
   - Multiple redundant connections
   - Geo-optimized routing
   - Aggressive heartbeat monitoring

2. **Message Processing Pipeline**:
   - Specialized message prioritization
   - Custom binary encoding/decoding
   - Fast-path message routing

#### Simple Chat Platform Integration

For applications with simpler requirements:

1. **Connection Management**:
   - Basic reconnection
   - Standard ping/pong handling
   - Simplified authentication

2. **Message Processing**:
   - JSON-based messages
   - Simple text processing
   - Minimal subscription management

## Best Practices

### Choosing the Right Profile

When implementing WebSockexNova for your application:

1. **Assess Your Requirements**:
   - Is your application financial or time-critical? → Financial Profile
   - Is it a general messaging or notification system? → Standard Profile
   - Is it a simple integration with minimal requirements? → Lightweight Profile

2. **Consider Customization Points**:
   - Connection management (reconnection strategies, authentication)
   - Message processing (encoding/decoding, validation)
   - Error handling (recovery strategies, logging)
   - Telemetry (metrics collection, alerting)

3. **Follow Platform-Specific Guidelines**:
   - Financial platforms: Implement robust error recovery and failover
   - Standard platforms: Balance reliability with resource utilization
   - Simple platforms: Minimize complexity with appropriate error handling

### Implementation Approach

1. **Start with Existing Adapters**:
   - Use built-in platform adapters when available
   - Copy and modify similar adapters for new platforms

2. **Test Thoroughly**:
   - Simulate connection failures and recovery
   - Test subscription persistence across reconnects
   - Verify authentication refresh flows

3. **Monitor in Production**:
   - Track connection stability metrics
   - Monitor message throughput and latency
   - Alert on abnormal reconnection patterns

## Conclusion

WebSockexNova's behavior-based architecture provides a flexible, extensible foundation for WebSocket interactions across various platforms. By separating core behaviors and offering implementation profiles, the library supports applications ranging from high-frequency trading to simple messaging systems.

The use of Gun as the transport layer ensures a reliable foundation, while the behavior interfaces enable custom implementations tailored to specific requirements.

For implementation details and examples, please refer to the additional documentation in the `docs` directory.
