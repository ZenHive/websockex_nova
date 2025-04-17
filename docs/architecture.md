# WebsockexNova Architecture Overview

> **Maintainer Note:** This document provides a high-level architectural overview of WebsockexNova. For implementation details, concrete code examples, and comprehensive guides, please refer to the dedicated documentation in the `docs/guides/` and `docs/examples/` directories.

> **Note:** This document provides a high-level architectural overview of WebsockexNova. For implementation details and comprehensive examples, please refer to the API documentation and guides in the `docs/guides/` directory.

## Transport Layer: Gun Integration

WebsockexNova uses [Gun](https://github.com/ninenines/gun) as its underlying WebSocket transport layer. Gun is a mature HTTP/WebSocket client for Erlang/OTP maintained by the Cowboy team, offering:

1. **Battle-tested implementation**: Robust WebSocket protocol handling
2. **Connection Management**: Built-in connection pooling and management
3. **Protocol Support**: HTTP/1.1, HTTP/2, and WebSocket protocols
4. **Modern TLS**: Comprehensive TLS options and security features

### Gun Adapter

WebsockexNova wraps Gun with a thin adapter layer that translates between the Gun API and WebsockexNova's behavior interfaces.

### Gun Process Ownership and Message Routing

A critical aspect of Gun's design is its process-based message routing:

1. **Owner Process**: When a process calls `:gun.open/3`, it becomes the "owner" of the Gun connection
   - Only the owner process receives Gun messages (`:gun_up`, `:gun_down`, `:gun_ws`, etc.)
   - If the owner process terminates, Gun will automatically close the connection

2. **Explicit Ownership Transfer**: Ownership can be transferred to another process using `:gun.set_owner/2`
   - This is crucial for applications that separate connection establishment from message handling
   - WebsockexNova's ConnectionWrapper ensures proper ownership setup

3. **Message Handling Flow**: Gun messages follow this flow:
   - Gun process establishes network connection
   - Gun sends status messages (`:gun_up`, `:gun_down`) to the owner process
   - Owner process must implement `handle_info/2` callbacks to receive these messages
   - Messages can be forwarded to other processes if needed

> **Implementation Note**: When working with Gun connections, always ensure that:
> - The process intended to handle Gun messages is set as the owner
> - All necessary `handle_info/2` callbacks are implemented in the owner process
> - Or a proper message forwarding mechanism is in place

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

WebsockexNova provides structured organization for platform-specific adapters. Each platform integration follows a consistent pattern with adapter, client, message handling, and subscription management modules.

For detailed platform integration examples and directory structures, see `docs/examples/platform_integration.md`.

#### Protocol Integrations

Protocol integrations follow similar organization patterns but focus on protocol-specific behaviors and message formats.

For detailed protocol integration examples and directory structures, see `docs/examples/protocol_integration.md`.

## WebsockexNova Architecture

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
                       ┌─────────────────────┐     ┌───────────────────┐
                       │  HeartbeatHandler   │     │   StateHelpers    │
                       └─────────────────────┘     └───────────────────┘
                                 │                         │
                                 ▼                         ▼
                       ┌─────────────────────┐     ┌───────────────────┐
                       │   RateLimitHandler  │     │    StateTracer    │
                       └─────────────────────┘     └───────────────────┘
```

### 2. Core Behaviors and Modules Overview

WebsockexNova defines a set of behaviors that establish contracts for different aspects of WebSocket communication. Each behavior serves a specific purpose and can be customized based on application requirements.

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

#### 2.6 Clustering Behaviors

<!-- TODO: Verify that all clustering-related behaviors (especially ClusterAware callbacks like handle_node_transition, handle_cluster_update) are documented here as they are implemented -->

- **ClusterAware Behavior**: For components that need to respond to cluster state changes
  - `handle_node_transition/3`: React to node joins/leaves in the cluster
  - `handle_cluster_update/3`: Process state updates from other cluster nodes
  - `prepare_state_sync/1`: Prepare local state for synchronization to other nodes

#### 2.7 Connection State Management

The connection state management system provides robust tracking and management of WebSocket connection lifecycle:

**ConnectionManager**: Core module that implements the state machine for connection transitions
  - State transitions with validation
  - Reconnection logic with configurable strategies
  - Terminal error detection and handling

**StateHelpers**: Provides consistent state operations and logging across the codebase
  - Standardized state update operations (`handle_connection_established`, `handle_disconnection`, etc.)
  - Consistent logging for state transitions
  - Centralized error handling

**StateTracer**: Advanced tracing for connection state with detailed history and statistics
  - Records all state transitions with timestamps
  - Tracks connection statistics (uptime, reconnection frequency)
  - Provides searchable history of connection events
  - Can export trace events to a file or monitoring system

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

WebsockexNova implements standardized telemetry events for monitoring performance, reliability, and behavior.

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

For applications requiring high availability and geo-distribution, WebsockexNova provides clustering capabilities.

### Key Clustering Features

- **Node Discovery**: Automatic detection of cluster nodes (optional libcluster integration)
- **Distributed Subscriptions**: Subscription state shared across nodes
- **Geo-Aware Routing**: Connect via the node with closest proximity to target service
- **Distributed Rate Limiting**: Coordinate rate limits across nodes
- **Node Failover**: Seamlessly transfer connections if a node becomes unavailable

> **Note:** See `docs/guides/clustering.md` for detailed clustering configuration and deployment patterns.

## Document Organization

To maintain clarity while providing complete information, WebsockexNova documentation is organized into several components:

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

WebsockexNova is designed to support different application profiles with varying requirements for performance, reliability, and complexity.

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

### 4. Chat/Messaging Platform Profile

Optimized for interactive messaging applications like Slack, Discord, or custom chat platforms with moderate reliability requirements.

```elixir
# Example configuration for chat/messaging platforms
config :websockex_nova,
  profile: :messaging,
  reconnection: [
    strategy: :exponential_backoff,
    max_attempts: 20,
    initial_delay: 1_000,   # 1 second
    max_delay: 30_000       # 30 seconds
  ],
  connection: [
    timeout: 8_000,         # 8 seconds
    ping_interval: 45_000,  # Less aggressive heartbeats than financial
    pong_timeout: 10_000
  ],
  telemetry: [
    level: :standard,       # Balanced metrics
    connection_events: true,
    message_events: true,   # Track message events for chat analytics
    error_events: true
  ],
  clustering: [
    enabled: true,
    strategy: :consistent_hash  # Route users consistently to nodes
  ]
```

**Key Characteristics:**
- Moderate reconnection strategy with reasonable persistence
- User presence tracking capabilities
- Message delivery guarantees with acknowledgments
- Connection state preservation across reconnects
- Support for client-side message queueing during disconnects
- Optional clustering for larger deployments

### 5. Custom Profile

Applications can define custom profiles by overriding specific behaviors:

```elixir
defmodule MyApp.CustomConnectionHandler do
  @behaviour WebsockexNova.ConnectionHandler

  # Custom implementation optimized for specific use case
end

# Application configuration
config :my_app, :websocket,
  handler: MyApp.CustomConnectionHandler,
  # Other custom options
```

## Common Macros and Using Directives

WebsockexNova provides macros for common WebSocket client patterns through `__using__` directives:

```elixir
defmodule MyApp.WebSocket.DeribitClient do
  use WebsockexNova.Client,
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

WebsockexNova provides multiple error handling approaches:

#### Financial-Grade Error Handling

```elixir
# This example is simplified - implementation details are in separate guides
defmodule MyApp.FinancialErrorHandler do
  @behaviour WebsockexNova.ErrorHandler

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
  @behaviour WebsockexNova.ErrorHandler

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

When implementing WebsockexNova for your application:

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

> **Maintainer Note:** As WebsockexNova profiles and behaviors evolve, revisit these best practice recommendations to ensure they remain aligned with the library's capabilities and recommended usage patterns.

## Conclusion

WebsockexNova's behavior-based architecture provides a flexible, extensible foundation for WebSocket interactions across various platforms. By separating core behaviors and offering implementation profiles, the library supports applications ranging from high-frequency trading to simple messaging systems.

The use of Gun as the transport layer ensures a reliable foundation, while the behavior interfaces enable custom implementations tailored to specific requirements.

For implementation details and examples, please refer to the additional documentation in the `docs` directory.

## Advanced Capabilities

WebsockexNova provides several advanced capabilities to support enterprise-grade WebSocket applications with sophisticated requirements:

### 1. Test Harness & Mocks

Testing WebSocket applications traditionally requires complex infrastructure or live connections. WebsockexNova provides comprehensive testing utilities:

- **Mock WebSocket Server**: In-memory WebSocket server for testing client behavior
- **Frame Sequence Simulator**: Pre-defined or programmatic frame sequences for testing
- **Failure Injection**: Simulate disconnects, errors, and reconnection scenarios
- **Latency Simulation**: Test behavior under various network conditions

```elixir
# Example test with WebsockexNova test harness
test "reconnects after disconnect" do
  test_scenario = WebsockexNova.TestHarness.Scenario.new()
    |> WebsockexNova.TestHarness.Scenario.connect_success()
    |> WebsockexNova.TestHarness.Scenario.send_frame(:text, ~s({"type":"welcome"}))
    |> WebsockexNova.TestHarness.Scenario.disconnect(code: 1000)
    |> WebsockexNova.TestHarness.Scenario.expect_reconnect()
    |> WebsockexNova.TestHarness.Scenario.connect_success()

  {:ok, _client} = WebsockexNova.TestHarness.start_supervised(
    MyApp.WebSocket.Client,
    scenario: test_scenario
  )

  # Assert client reconnected correctly
  assert_receive {:reconnect_complete}, 1000
end
```

> **Note:** See `docs/examples/testing.md` for complete examples of testing WebSocket clients.

### 2. Backpressure & Flow Control

WebsockexNova includes mechanisms for controlling message flow and handling high-volume streams without overwhelming consumers:

- **BackpressureHandler Behavior**: Callbacks for controlling message flow
- **Buffer Management**: Configurable message buffering with overflow strategies
- **Subscription Throttling**: Rate-limiting for high-volume subscription channels
- **Consumer-driven Flow Control**: Allow consumers to pause/resume message delivery

```elixir
# Configuration example for backpressure control
config :websockex_nova,
  backpressure: [
    buffer_size: 10_000,          # Maximum buffered messages
    overflow_strategy: :drop_old, # :drop_old, :drop_new, or :block
    warning_threshold: 0.8,       # Warning at 80% capacity
    throttle_threshold: 0.9       # Apply backpressure at 90% capacity
  ]
```

> **Note:** See `docs/examples/backpressure.md` for details on handling high-volume streams.

### 3. Pluggable Codecs & Binary Protocols

WebsockexNova supports multiple message encoding formats beyond JSON:

- **CodecHandler Behavior**: Pluggable encoding/decoding for various formats
- **Binary Frame Support**: First-class support for binary WebSocket frames
- **Compression**: Support for permessage-deflate and custom compression
- **Protocol Buffers**: Integration with Google Protocol Buffers
- **MessagePack**: Support for MessagePack binary serialization

```elixir
# Example client with custom codec
defmodule MyApp.ProtobufClient do
  use WebsockexNova.Client,
    codec: WebsockexNova.Codec.Protobuf,
    codec_options: [
      descriptor_module: MyApp.Protos,
      default_message_type: MyApp.Protos.MarketData
    ]
end
```

> **Note:** See `docs/examples/codecs.md` for details on implementing and using custom codecs.

### 4. Security & Secrets Management

WebsockexNova provides robust security features:

- **Credential Rotation**: Automatic API key rotation and refresh token handling
- **Vault Integration**: Built-in integration with HashiCorp Vault and AWS Secrets Manager
- **Encryption**: At-rest encryption for sensitive configuration
- **Audit Logging**: Security-focused logging for sensitive operations

```elixir
# Example configuration with vault integration
config :websockex_nova,
  secrets_manager: [
    adapter: WebsockexNova.SecretsManager.Vault,
    auto_rotate: true,             # Automatically rotate credentials
    rotation_frequency: :daily,    # :hourly, :daily, :weekly
    vault_path: "secret/my-app/ws-credentials"
  ]
```

> **Note:** See `docs/guides/security.md` for comprehensive security documentation.

### 5. HTTP Fallback & Protocol Negotiation

For environments where WebSockets may be blocked or unreliable:

- **Transport Negotiation**: Automatic selection of optimal transport
- **HTTP Polling Fallback**: RESTful polling when WebSockets aren't available
- **Seamless API**: Consistent interface regardless of transport
- **Upgrade/Downgrade**: Runtime switching between transport mechanisms

```elixir
# Configuration with transport fallback
config :websockex_nova,
  transport: [
    preferred: :websocket,
    fallbacks: [:http_polling, :sse],
    negotiation_timeout: 5000,     # Milliseconds to try negotiation
    polling_interval: 1000         # Poll interval for HTTP fallback
  ]
```

> **Note:** See `docs/examples/transport.md` for details on transport options.

### 6. Distributed Tracing & OpenTelemetry

WebsockexNova offers comprehensive observability:

- **OpenTelemetry Integration**: Native support for OpenTelemetry tracing
- **Span Context**: Automatic propagation of trace context
- **Custom Attributes**: Platform-specific span attributes
- **Baggage Propagation**: Cross-process context propagation

```elixir
# Enabling OpenTelemetry tracing
config :websockex_nova,
  telemetry: [
    # ...existing telemetry configuration...
    tracing: [
      enabled: true,
      tracer_name: "websockex_nova",
      span_prefix: "websocket.",
      include_message_spans: true  # Create spans for individual messages
    ]
  ]
```

> **Note:** See `docs/guides/tracing.md` for distributed tracing integration examples.

### 7. Dynamic Configuration & Hot Reload

WebsockexNova supports runtime configuration changes:

- **ConfigProvider Behavior**: Interface for configuration sources
- **Live Updates**: Change behavior parameters without restarts
- **Configuration Persistence**: Optional persistence of runtime config changes
- **Centralized Management**: Integration with config management systems

```elixir
# Example of runtime configuration update
WebsockexNova.configure(client,
  reconnection: [max_attempts: 20],
  rate_limit: [requests_per_second: 50]
)
```

> **Note:** See `docs/guides/dynamic_configuration.md` for runtime configuration guidance.

### 8. Release & CI Recommendations

To ensure code quality and simplify deployment, WebsockexNova provides:

- **GitHub Actions Workflows**: Ready-to-use CI workflows
- **Quality Checks**: Credo, Dialyzer, and test coverage configs
- **Release Process**: Documentation for hex publication
- **Compatibility Testing**: Multi-version Erlang/Elixir matrix tests

> **Note:** See `docs/guides/ci_cd.md` for continuous integration and delivery best practices.
