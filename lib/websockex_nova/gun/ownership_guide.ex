defmodule WebsockexNova.Gun.OwnershipGuide do
  @moduledoc """
  # Gun Process Ownership Management Guide

  This guide explains how WebsockexNova manages Gun process ownership for WebSocket connections.

  ## Ownership Model

  In the Erlang VM, a process can be designated as the "owner" of a Gun connection.
  This owner process receives all messages from the Gun connection process, including:

  - Connection status messages (gun_up, gun_down)
  - WebSocket upgrade responses
  - WebSocket frames
  - Error notifications

  WebsockexNova implements a robust ownership model with the following features:

  1. **Default Ownership**: By default, the `ConnectionWrapper` GenServer is the owner
     of the Gun connection process.

  2. **Process Monitoring**: The `ConnectionWrapper` monitors the Gun process using
     `Process.monitor/1` to detect if the Gun process crashes or exits.

  3. **Ownership Transfer**: Ownership can be transferred to other processes when needed
     using the `ConnectionWrapper.transfer_ownership/2` function.

  ## Ownership Lifecycle

  1. **Establishment**: When a connection is opened, the Gun process is created and
     the `ConnectionWrapper` process is set as its owner.

  2. **Monitoring**: A monitor reference is created and stored in the connection state
     to track the Gun process lifecycle.

  3. **Message Routing**: All Gun messages are routed to the owner process. In the
     default setup, these are handled by the `ConnectionWrapper`.

  4. **Transfer (if needed)**: Ownership can be transferred to another process if
     required for advanced use cases.

  5. **Termination**: When the connection is closed or if the Gun process crashes,
     proper cleanup is performed.

  ## Transferring Ownership

  Ownership transfer is useful for advanced use cases where a different process needs
  to directly receive and handle Gun messages. To transfer ownership:

  ```elixir
  # Transfer Gun process ownership to another process
  ConnectionWrapper.transfer_ownership(wrapper_pid, new_owner_pid)
  ```

  After ownership transfer, the new owner will receive all Gun messages. The
  `ConnectionWrapper` will still maintain a monitor on the Gun process to detect if it
  crashes.

  ## Edge Cases

  1. **Gun Process Crashes**: If the Gun process crashes unexpectedly, the
     `ConnectionWrapper` will receive a `:DOWN` message and can handle the failure
     gracefully.

  2. **Owner Process Crashes**: If the owner process crashes, the Gun process will
     continue to run, but messages will be lost. This scenario should be handled by
     proper supervision structures.

  3. **Existing Ownership**: When transferring ownership, if the Gun process already
     has an owner different from the `ConnectionWrapper`, the operation may fail.

  ## Best Practices

  1. **Use ConnectionWrapper APIs**: Whenever possible, interact with Gun through the
     `ConnectionWrapper` API rather than directly.

  2. **Supervision**: Ensure proper supervision of both Gun and connection wrapper
     processes.

  3. **Transfer Ownership Carefully**: Only transfer ownership when necessary for
     advanced use cases, as it can make debugging more complex.

  4. **Monitor after Transfer**: If ownership is transferred, consider adding a
     monitor in the new owner process to detect if the Gun process terminates.

  ## Internal Implementation

  Internally, WebsockexNova manages Gun process ownership through:

  1. The `gun_pid` field in the `ConnectionState` struct, which holds the PID of the Gun process
  2. The `gun_monitor_ref` field, which holds the reference for the Process.monitor
  3. Handling of `:DOWN` messages in the `ConnectionWrapper` GenServer
  4. The `transfer_ownership/2` function for explicit ownership management
  """
end
