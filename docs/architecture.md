# WebsockexNew Architecture

WebsockexNew is a simplified WebSocket client library built on Gun transport layer.

## System Overview

The WebsockexNew system consists of 8 core modules providing a clean, minimal WebSocket client implementation:

```
WebsockexNew.Client         # Core client interface (5 functions)
WebsockexNew.Config         # Configuration management  
WebsockexNew.MessageHandler # Message processing
WebsockexNew.Reconnection   # Connection recovery
WebsockexNew.ConnectionRegistry # Connection tracking
WebsockexNew.ErrorHandler  # Error processing
WebsockexNew.Frame          # Frame handling
WebsockexNew.Examples.DeribitAdapter # Example adapter
```

## Core Architecture Principles

- **Simplicity First**: Minimal viable implementation with clean interfaces
- **Gun Transport**: Battle-tested WebSocket transport layer
- **Adapter Pattern**: Platform-specific customization through adapters
- **Error Resilience**: Automatic reconnection with subscription preservation

## Core Client Interface

The `WebsockexNew.Client` module provides 5 essential functions:

```elixir
# Establish WebSocket connection
@spec connect(String.t() | Config.t(), keyword()) :: {:ok, t()} | {:error, term()}

# Send text messages
@spec send_message(t(), binary()) :: :ok | {:error, term()}

# Close connection gracefully
@spec close(t()) :: :ok

# Subscribe to channels/topics
@spec subscribe(t(), list()) :: :ok | {:error, term()}

# Get current connection state
@spec get_state(t()) :: :connecting | :connected | :disconnected
```

## Connection Management

### Connection Lifecycle

1. **Connection Establishment**
   - Parse URL and configuration
   - Open Gun connection with process monitoring
   - Upgrade to WebSocket protocol
   - Wait for upgrade confirmation

2. **Message Handling**
   - Send text frames via Gun
   - Process incoming frames
   - Handle protocol-specific messages

3. **Error Recovery**
   - Monitor Gun process for crashes
   - Automatic reconnection on recoverable errors
   - Subscription preservation across reconnects

### State Management

The client maintains minimal state:
- `gun_pid`: Gun process identifier
- `stream_ref`: WebSocket stream reference  
- `state`: Connection status (`:connecting | :connected | :disconnected`)
- `url`: Original connection URL
- `monitor_ref`: Process monitor reference

## Adapter Pattern

Adapters customize WebsockexNew for specific platforms:

### DeribitAdapter Example

```elixir
defmodule WebsockexNew.Examples.DeribitAdapter do
  # Wraps WebsockexNew.Client with Deribit-specific functionality
  defstruct [:client, :authenticated, :subscriptions, :client_id, :client_secret]
  
  # Platform-specific methods
  def connect(opts)
  def authenticate(adapter)  
  def subscribe(adapter, channels)
  def handle_message(frame)
end
```

### Adapter Responsibilities

- **Authentication**: Platform-specific auth flows
- **Message Format**: Protocol-specific message handling
- **Subscription Management**: Channel/topic management
- **Error Handling**: Platform error codes and recovery

## Error Handling Strategy

### Error Categories

1. **Connection Errors**: Network failures, timeouts
2. **Protocol Errors**: WebSocket upgrade failures  
3. **Application Errors**: Platform-specific errors

### Recovery Strategy

- **Recoverable Errors**: Automatic reconnection with exponential backoff
- **Non-recoverable Errors**: Return error to caller
- **Process Monitoring**: Detect Gun process crashes

## Configuration System

`WebsockexNew.Config` provides connection configuration:

```elixir
defstruct [
  :url,                    # WebSocket URL (required)
  headers: [],             # HTTP headers for upgrade
  timeout: 5_000,          # Connection timeout (ms)
  retry_count: 3,          # Reconnection attempts
  retry_delay: 1_000,      # Delay between retries (ms)
  heartbeat_interval: 30_000 # Heartbeat frequency (ms)
]
```

## Module Responsibilities

### WebsockexNew.Client
- Core WebSocket operations
- Gun process management
- Connection state tracking

### WebsockexNew.Config  
- Configuration validation
- URL parsing and validation
- Default value management

### WebsockexNew.MessageHandler
- Frame processing
- Message routing
- Protocol abstraction

### WebsockexNew.Reconnection
- Automatic reconnection logic
- Backoff strategy implementation
- Subscription preservation

### WebsockexNew.ConnectionRegistry
- Connection ID mapping
- Process tracking
- Connection state coordination

### WebsockexNew.ErrorHandler
- Error classification
- Recovery decision logic
- Error transformation

### WebsockexNew.Frame
- WebSocket frame encoding/decoding
- Frame type handling
- Binary/text frame processing

## Design Goals

1. **Minimal Complexity**: 8 modules vs 56 in previous system
2. **Clear Interfaces**: Simple function signatures with clear types
3. **Gun Foundation**: Leverage proven WebSocket transport
4. **Adapter Extensibility**: Easy platform integration
5. **Error Resilience**: Graceful handling of network issues

## Usage Patterns

### Simple Connection
```elixir
{:ok, client} = WebsockexNew.Client.connect("wss://api.example.com/ws")
:ok = WebsockexNew.Client.send_message(client, "Hello")
```

### Platform Adapter
```elixir
{:ok, adapter} = WebsockexNew.Examples.DeribitAdapter.connect()
{:ok, adapter} = WebsockexNew.Examples.DeribitAdapter.authenticate(adapter)
{:ok, adapter} = WebsockexNew.Examples.DeribitAdapter.subscribe(adapter, ["ticker.BTC-USD"])
```

### Configuration
```elixir
config = WebsockexNew.Config.new!("wss://api.example.com/ws", timeout: 10_000)
{:ok, client} = WebsockexNew.Client.connect(config)
```