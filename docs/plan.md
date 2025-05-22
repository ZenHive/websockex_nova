# WebsockexNew: Using Gun as Transport Layer

This document outlines a comprehensive implementation plan for WebsockexNew to use [:gun](https://github.com/ninenines/gun) as the underlying WebSocket transport layer while building our behavior-based architecture on top.

## Why Use Gun?

[Gun](https://github.com/ninenines/gun) is a mature HTTP/WebSocket client for Erlang/OTP with several advantages:

1. **Maintained by the Cowboy Team**: Gun is developed by NineFX (formerly Nine Nines), the same team that maintains Cowboy, one of Erlang's most robust web servers
2. **Protocol Support**: HTTP/1.1, HTTP/2, WebSocket
3. **Connection Management**: Sophisticated connection management
4. **Automatic Reconnection**: Built-in reconnection capabilities
5. **TLS Support**: Modern TLS options
6. **Flexible Message Handling**: Support for both synchronous and asynchronous message processing
7. **Monitor-Based Error Handling**: Ability to use process monitors instead of links for more robust error handling

Using Gun allows us to focus on the application-specific aspects of WebsockexNew (behaviors, platform integrations) without reinventing the wheel for WebSocket protocol handling.

## Project Overview

### Key Components

```
lib/
├── websockex_new.ex                # Client API (uses Gun underneath)
├── websockex_new/
    ├── behaviors/                   # Behavior definitions
    │   ├── connection_handler.ex    # How to handle connection lifecycle
    │   ├── message_handler.ex       # How to process messages
    │   ├── error_handler.ex         # How to handle errors
    │   └── ...                      # Other behaviors
    │
    ├── gun/                         # Gun-specific implementation
    │   ├── connection_state.ex      # Connection state structure
    │   ├── connection_manager.ex    # Connection lifecycle state machine
    │   ├── connection_wrapper.ex    # Wrapper around Gun for WebSockets
    │   ├── connection_wrapper/
    │   │   └── message_handlers.ex  # Handlers for Gun messages
    │   └── helpers/                 # Helper modules
    │       ├── state_helpers.ex     # State mutation helpers
    │       └── state_tracer.ex      # State transition tracing
    │
    ├── transport/                   # Transport layer (Gun adapter)
    │   ├── gun_client.ex            # Wrapper around Gun for WebSockets
    │   └── reconnection.ex          # Reconnection strategies
    │
    ├── message/                     # Message handling
    │   ├── processor.ex             # Message processing pipeline
    │   └── subscription.ex          # Subscription management
    │
    ├── platform/                    # Platform-specific adapters
    │   ├── deribit/                 # Example exchange integration
    │   │   ├── adapter.ex           # Implements behaviors for Deribit
    │   │   ├── client.ex            # Platform-specific client
    │   │   └── ...
    │   └── ...                      # Other platform integrations
    │
    ├── macros.ex                    # Strategy macros
    ├── telemetry.ex                 # Enhanced telemetry
    └── types.ex                     # Type definitions
```

### Migration Strategy

1. **Add Gun Dependency**: Replace our own WebSocket protocol handling with Gun
2. **Create Gun Client Adapter**: Build a thin adapter between Gun and our behavior interfaces
3. **Implement Behavior-Based Architecture**: Focus on behavior interfaces for extensibility
4. **Port Valuable Code**: Salvage error handling and other utility code
5. **Build Platform Integrations**: Implement exchange-specific integrations

## Implementation Plan

### Phase 0: Gun Integration (1 week)

#### 0.1 Add Gun Dependency

```elixir
# mix.exs
defmodule WebsockexNew.MixProject do
  use Mix.Project

  # ...

  defp deps do
    [
      {:gun, "~> 2.0"},
      # ... other deps
    ]
  end
end
```

#### 0.2 Create Gun Client Adapter

Implement a robust Gun client adapter with the following features:

1. **Process Monitoring**: Use Process.monitor/1 instead of links for more reliable tracking

   - Create monitors for Gun processes to detect termination
   - Clean up monitors appropriately during ownership transfers
   - Use explicit monitor references with Gun's await functions

2. **Ownership Transfer**: Support reliable ownership transfer between processes

   - Implement transfer_ownership/2 and receive_ownership/2 functions
   - Ensure proper state transfer during ownership changes
   - Coordinate message handling during the transfer process

3. **Connection Lifecycle Management**: Implement a state machine for connection status

   - Track connection status with well-defined states
   - Handle reconnection with configurable strategies
   - Use gun:await_up/3 with monitor references for reliable connection establishment

4. **WebSocket Handling**: Provide simplified interface for WebSocket operations
   - Support for upgrading HTTP connections to WebSocket
   - Frame sending and receiving with proper error handling
   - Use gun:await/3 with monitor references for waiting on WebSocket upgrades

### Phase 1: Core Behaviors (2 weeks)

#### 1.1 Define Behavior Interfaces

Start by defining behavior interfaces with TDD:

# test/websockex_new/behaviors/connection_handler_test.exs

# lib/websockex_new/behaviors/connection_handler.ex

#### 1.2 Add Strategy Macros

- handle_disconnect
- should_reconnect
- backoff

### Phase 2: Core Infrastructure (2 weeks)

#### 2.1 Implement WebsockexNew Main Module

# lib/websockex_new.ex

#### 2.2 Message Processing

# lib/websockex_new/message/processor.ex

### Phase 3: Platform Integrations (3 weeks)

#### 3.1 Create Integration Generator

- deribit, binance, ethereum, etc

#### 3.2 Implement Example Platform Integration

# lib/websockex_new/platform/deribit/adapter.ex

### Phase 4: Observability and Testing (2 weeks)

#### 4.1 Enhanced Telemetry

# lib/websockex_new/telemetry.ex

#### 4.2 Integration Tests

# test/integration/deribit_test.exs

## Benefits of Using Gun

1. **Reduced Development Time**: No need to reimplement WebSocket protocol details
2. **Focus on Behavior Design**: More time to perfect the behavior-based architecture
3. **Maintained Dependencies**: Gun is actively maintained by NineFX
4. **Modern Features**: Benefit from Gun's HTTP/2 and modern TLS support
5. **Simplified Testing**: Easier to mock and test when using a standard interface
