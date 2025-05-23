# Gun Integration Guide

This guide covers the integration of the [Gun](https://github.com/ninenines/gun) HTTP/WebSocket client in WebsockexNew, focusing on connection management, process monitoring, and ownership transfer.

## Table of Contents
- [Overview](#overview)
- [Process Monitoring vs. Linking](#process-monitoring-vs-linking)
- [Using Gun's Await Functions](#using-guns-await-functions)
- [Ownership Transfer](#ownership-transfer)
- [Best Practices](#best-practices)

## Overview

WebsockexNew uses Gun as its underlying transport layer for WebSocket connections. Gun provides robust HTTP and WebSocket protocol implementation with features like:
- HTTP/1.1, HTTP/2, and WebSocket support
- Automatic reconnection capabilities
- Comprehensive TLS options
- Message streaming and multiplexing

The `WebsockexNew.Client` module will be refactored to a GenServer that owns the Gun connection and manages message routing.

## Process Monitoring vs. Linking

Gun gives developers the choice between using process links and monitors for tracking connection processes:

### Why WebsockexNew Uses Monitors

WebsockexNew uses Erlang's process monitoring (`Process.monitor/1`) instead of process linking for tracking Gun connections for several reasons:

1. **Resilience**: If a Gun process crashes, the monitoring process receives a message rather than crashing itself
2. **Control**: More granular control over error handling and recovery
3. **Ownership Transfers**: Easier to manage process relationships during ownership changes

### Current Implementation in Client

```elixir
# In WebsockexNew.Client.connect/2
{:ok, gun_pid} = :gun.open(host_charlist, port, gun_opts)
monitor_ref = Process.monitor(gun_pid)

%Client{
  gun_pid: gun_pid,
  monitor_ref: monitor_ref,
  state: :connecting,
  # ...
}
```

## Using Gun's Await Functions

Gun provides await functions for synchronous operations, but they require careful handling of the monitor reference.

### The Monitor Reference Requirement

Gun's await functions check that the calling process has a monitor on the Gun connection:

```elixir
# Current usage in WebsockexNew.Client
defp await_websocket_upgrade(gun_pid, stream_ref, timeout, monitor_ref) do
  case :gun.await(gun_pid, stream_ref, timeout, monitor_ref) do
    {:upgrade, [<<"websocket">>], _headers} -> :ok
    {:error, reason} -> {:error, reason}
  end
end
```

### Common Pitfalls

1. **Missing Monitor Reference**: Calling await without the monitor reference will fail
2. **Wrong Monitor Reference**: Using a monitor reference from a different connection
3. **Monitor After Connect**: The monitor must be established before calling await functions

## Ownership Transfer

One of Gun's most powerful features is the ability to transfer connection ownership between processes. This is crucial for WebsockexNew's upcoming architecture where the Client GenServer needs to own the connection for message routing.

### When to Transfer Ownership

Ownership transfer is useful when:
- Client GenServer needs to receive Gun messages for routing to HeartbeatManager
- Reconnection creates a new Gun process that needs proper ownership
- Moving connections between supervision trees

### Implementation for HeartbeatManager

```elixir
defmodule WebsockexNew.Client do
  use GenServer
  
  # Client GenServer owns the Gun connection
  def init(config) do
    {:ok, gun_pid} = :gun.open(host, port, opts)
    monitor_ref = Process.monitor(gun_pid)
    
    # Client GenServer (self()) owns the connection
    # All Gun messages come to this process
    
    state = %{
      gun_pid: gun_pid,
      monitor_ref: monitor_ref,
      heartbeat_manager: nil,
      # ...
    }
    
    {:ok, state}
  end
  
  # Route Gun messages to appropriate handlers
  def handle_info({:gun_ws, gun_pid, stream_ref, frame}, state) do
    case MessageHandler.parse(frame) do
      {:heartbeat, msg} ->
        # Forward to HeartbeatManager
        send(state.heartbeat_manager, {:heartbeat_message, msg})
      {:user_message, msg} ->
        # Forward to user handler
        send(state.user_handler, {:websocket_message, msg})
    end
    {:noreply, state}
  end
end
```

### Reconnection Flow with Ownership

```elixir
def handle_info({:DOWN, ref, :process, pid, reason}, state) do
  if state.monitor_ref == ref and state.gun_pid == pid do
    # Connection lost, trigger reconnection
    case Reconnection.reconnect(state.config) do
      {:ok, new_gun_pid} ->
        # Client GenServer already owns the new connection
        # because Reconnection was called from this process
        new_monitor_ref = Process.monitor(new_gun_pid)
        
        new_state = %{state | 
          gun_pid: new_gun_pid,
          monitor_ref: new_monitor_ref
        }
        
        # Notify HeartbeatManager of new connection
        send(state.heartbeat_manager, :connection_restored)
        
        {:noreply, new_state}
    end
  end
end
```

## Best Practices

### 1. Always Use Monitors

```elixir
# Good - WebsockexNew.Client pattern
{:ok, gun_pid} = :gun.open(host, port, opts)
monitor_ref = Process.monitor(gun_pid)

# Bad - no visibility into connection failures
{:ok, gun_pid} = :gun.open(host, port, opts)
```

### 2. Handle Monitor Messages

```elixir
# In Client GenServer
def handle_info({:DOWN, ref, :process, pid, reason}, state) do
  cond do
    ref == state.monitor_ref ->
      handle_connection_down(reason, state)
    true ->
      {:noreply, state}
  end
end
```

### 3. Client GenServer Owns Gun Connection

The Client GenServer must own the Gun connection to receive messages:

```elixir
defmodule WebsockexNew.Client do
  use GenServer
  
  # Gun messages come to the GenServer process
  def handle_info({:gun_ws, _, _, _} = msg, state) do
    route_message(msg, state)
  end
  
  def handle_info({:gun_response, _, _, _} = msg, state) do
    route_message(msg, state)
  end
end
```

### 4. Clean Reconnection

```elixir
defp handle_reconnection(state) do
  # Old connection cleanup
  Process.demonitor(state.monitor_ref, [:flush])
  
  # Create new connection (Client GenServer owns it)
  case establish_new_connection(state.config) do
    {:ok, gun_pid} ->
      monitor_ref = Process.monitor(gun_pid)
      %{state | gun_pid: gun_pid, monitor_ref: monitor_ref}
  end
end
```

### 5. Test Connection Failures

Always test how your application handles:
- Gun process crashes during active trading
- Network disconnections during heartbeat sequences
- Reconnection with subscription restoration
- Message routing after reconnection

## Summary

Gun's process monitoring and ownership features are critical for WebsockexNew's architecture. By having the Client GenServer own the Gun connection, we enable:
- Message routing to HeartbeatManager and user handlers
- Seamless reconnection with state preservation
- Reliable heartbeat handling for financial trading
- Clean separation of concerns between modules

The key insight is that Gun sends messages to the process that owns the connection, making the Client GenServer refactor essential for production-grade WebSocket handling.