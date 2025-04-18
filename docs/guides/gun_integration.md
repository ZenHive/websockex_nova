# Gun Integration Guide

This guide covers the integration of the [Gun](https://github.com/ninenines/gun) HTTP/WebSocket client in WebsockexNova, focusing on connection management, process monitoring, and ownership transfer.

## Table of Contents

- [Overview](#overview)
- [Process Monitoring vs. Linking](#process-monitoring-vs-linking)
- [Using Gun's Await Functions](#using-guns-await-functions)
- [Ownership Transfer](#ownership-transfer)
- [Best Practices](#best-practices)

## Overview

WebsockexNova uses Gun as its underlying transport layer for WebSocket connections. Gun, developed by the creators of Cowboy, provides robust HTTP and WebSocket protocol implementation with features like:

- HTTP/1.1, HTTP/2, and WebSocket support
- Automatic reconnection capabilities
- Comprehensive TLS options
- Message streaming and multiplexing

The `WebsockexNova.Gun.ConnectionWrapper` module encapsulates Gun's functionality, providing a simplified interface while handling the complexities of connection management, message routing, and process lifecycle.

## Process Monitoring vs. Linking

Gun gives developers the choice between using process links and monitors for tracking connection processes:

### Why WebsockexNova Uses Monitors

WebsockexNova uses Erlang's process monitoring (`Process.monitor/1`) instead of process linking for tracking Gun connections for several reasons:

1. **Resilience**: If a Gun process crashes, the monitoring process receives a message rather than crashing itself
2. **Control**: More granular control over error handling and recovery
3. **Ownership Transfers**: Easier to manage process relationships during ownership changes

### Implementation Details

In our connection management code:

```elixir
# When establishing a new Gun connection
gun_pid = :gun.open(host_charlist, port, gun_opts)
gun_monitor_ref = Process.monitor(gun_pid)

# When the Gun process terminates, we receive a message:
def handle_info({:DOWN, ref, :process, pid, reason}, state) do
  if state.gun_monitor_ref == ref and state.gun_pid == pid do
    # Handle Gun process termination
    # ...
  end
end
```

## Using Gun's Await Functions

Gun provides "await" functions that synchronously wait for specific messages:

- `gun:await_up/2,3` - Wait for the connection to be established
- `gun:await/2,3` - Wait for a response to a specific request
- `gun:await_body/2,3` - Wait for the complete body of a response

These functions can potentially block indefinitely if the expected message never arrives. To prevent this, WebsockexNova always uses the versions that accept a monitor reference:

```elixir
# Creating a monitor for the Gun process
gun_monitor_ref = Process.monitor(gun_pid)

# Using the monitor with gun:await_up
case :gun.await_up(gun_pid, 5000, gun_monitor_ref) do
  {:ok, protocol} ->
    # Connection established

  {:error, reason} ->
    # Connection failed
end
```

This approach ensures that:

1. The await function will return if the Gun process terminates
2. The await function will respect the timeout parameter
3. We avoid potential deadlocks or hanging processes

## Ownership Transfer

Gun uses an owner-based message routing system. Only the "owner" process (typically the one that created the connection) receives messages from Gun.

### Transferring Ownership

In WebsockexNova, we implement a robust ownership transfer mechanism:

```elixir
# From the current owner process
def transfer_ownership(gun_pid, new_owner_pid) do
  # 1. Demonitor the current Gun process
  if gun_monitor_ref do
    Process.demonitor(gun_monitor_ref)
  end

  # 2. Create a new monitor for the Gun process
  gun_monitor_ref = Process.monitor(gun_pid)

  # 3. Transfer ownership using Gun's API
  case :gun.set_owner(gun_pid, new_owner_pid) do
    :ok ->
      # 4. Send connection info to the new owner
      send(new_owner_pid, {:gun_info, state_info})
      {:ok, gun_monitor_ref}

    {:error, reason} ->
      # If transfer failed, demonitor and return error
      Process.demonitor(gun_monitor_ref)
      {:error, reason}
  end
end

# In the new owner process
def receive_ownership(gun_pid) do
  # 1. Create a monitor for the Gun process
  gun_monitor_ref = Process.monitor(gun_pid)

  # 2. Wait for the gun_info message from the previous owner
  # This happens in handle_info/2
end

# Handle the gun_info message in the new owner
def handle_info({:gun_info, info}, state) do
  # Update state with the connection info
  updated_state =
    state
    |> update_gun_pid(info.gun_pid)
    |> update_status(info.status)
    # ...other state updates
end
```

### Key Considerations During Ownership Transfer

1. **Monitor Management**: Always clean up old monitors and create new ones
2. **State Synchronization**: Pass critical state information between processes
3. **Message Ordering**: Ensure proper sequencing of messages during transfer
4. **Error Handling**: Handle failed transfers gracefully

## Best Practices

When working with Gun connections in WebsockexNova:

1. **Always use monitors instead of links**

   - Creates a more resilient system
   - Gives better control over error handling

2. **Use gun:await\_\* functions with explicit monitor references**

   - Prevents indefinite blocking
   - Handles process termination gracefully

3. **Use ConnectionWrapper for Gun API interactions**

   - Provides a simpler interface
   - Handles ownership and monitoring correctly
   - Manages the connection lifecycle

4. **Handle ownership transfers with care**

   - Follow the transfer_ownership/receive_ownership pattern
   - Ensure state synchronization during transfers
   - Clean up monitors appropriately

5. **Test connection failures and recovery**
   - Verify that monitors detect Gun process termination
   - Ensure recovery mechanisms work as expected
   - Test ownership transfers during active connections

## Additional Resources

- [Gun Documentation](https://ninenines.eu/docs/en/gun/2.2/guide/)
- [Erlang Process Monitoring](https://www.erlang.org/doc/reference_manual/processes.html#monitors)
- [WebsockexNova Connection Management](../architecture.md#connection-state-management)
