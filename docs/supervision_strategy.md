# WebsockexNew Supervision Strategy

## Overview

WebsockexNew provides built-in supervision for WebSocket client connections, ensuring resilience and automatic recovery from failures. This is critical for financial trading systems where connection stability directly impacts order execution and risk management.

## Architecture

```
Application Supervisor
    └── ClientSupervisor (DynamicSupervisor)
            ├── Client GenServer 1
            ├── Client GenServer 2
            └── Client GenServer N
```

## Key Components

### 1. Application Module (`WebsockexNew.Application`)
- Starts automatically when the application launches
- Supervises the ClientSupervisor
- Ensures supervisor is always available

### 2. ClientSupervisor (`WebsockexNew.ClientSupervisor`)
- DynamicSupervisor for managing client connections
- Restart strategy: `:one_for_one` (isolated failures)
- Maximum 10 restarts in 60 seconds (configurable)
- Each client runs independently

### 3. Client GenServer (`WebsockexNew.Client`)
- Manages individual WebSocket connections
- Handles Gun process ownership and message routing
- Integrated heartbeat handling
- Automatic reconnection on network failures

## Usage

### Starting a Supervised Client

```elixir
# Basic supervised connection
{:ok, client} = WebsockexNew.ClientSupervisor.start_client("wss://example.com")

# With configuration
{:ok, client} = WebsockexNew.ClientSupervisor.start_client("wss://example.com",
  retry_count: 10,
  heartbeat_config: %{type: :deribit, interval: 30_000}
)
```

### Direct Connection (Unsupervised)

```elixir
# For testing or short-lived connections
{:ok, client} = WebsockexNew.Client.connect("wss://example.com")
```

## Restart Behavior

### Transient Restart Strategy
- Clients are restarted only if they exit abnormally
- Normal shutdowns (via `Client.close/1`) don't trigger restart
- Crashes and connection failures trigger automatic restart

### Failure Scenarios

1. **Network Disconnection**
   - Client detects connection loss
   - Attempts internal reconnection (configurable retries)
   - If max retries exceeded, GenServer exits
   - Supervisor restarts the client

2. **Process Crash**
   - Supervisor immediately detects exit
   - Starts new client process
   - Connection re-established from scratch

3. **Heartbeat Failure**
   - Client tracks heartbeat failures
   - Closes connection after threshold
   - Supervisor restarts for fresh connection

## Production Considerations

### 1. Resource Management
- Each supervised client consumes:
  - 1 Erlang process (Client GenServer)
  - 1 Gun connection process
  - Associated memory for state and buffers

### 2. Restart Limits
- Default: 10 restarts in 60 seconds
- Prevents restart storms
- Adjust based on expected failure patterns

### 3. Monitoring
```elixir
# List all supervised clients
clients = WebsockexNew.ClientSupervisor.list_clients()

# Check client health
health = WebsockexNew.Client.get_heartbeat_health(client)
```

### 4. Graceful Shutdown
```elixir
# Stop a specific client
WebsockexNew.ClientSupervisor.stop_client(pid)

# Client won't be restarted (normal termination)
```

## Best Practices

1. **Use Supervision for Production**
   - Always use `ClientSupervisor.start_client/2` for production
   - Direct connections only for testing/development

2. **Configure Appropriate Timeouts**
   - Set heartbeat intervals based on exchange requirements
   - Configure retry counts for network conditions

3. **Monitor Client Health**
   - Implement health checks using `get_heartbeat_health/1`
   - Set up alerts for excessive restarts

4. **Handle Restart Events**
   - Subscriptions may need re-establishment
   - Authentication may need renewal
   - Order state should be reconciled

## Example: Production Deribit Connection

```elixir
defmodule TradingSystem.DeribitConnection do
  use GenServer
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def init(opts) do
    # Start supervised Deribit connection
    {:ok, adapter} = WebsockexNew.Examples.SupervisedClient.start_deribit_connection(
      client_id: opts[:client_id],
      client_secret: opts[:client_secret]
    )
    
    # Subscribe to required channels
    WebsockexNew.Examples.DeribitAdapter.subscribe(adapter, [
      "book.BTC-PERPETUAL.raw",
      "trades.BTC-PERPETUAL.raw",
      "user.orders.BTC-PERPETUAL.raw"
    ])
    
    # Start health monitoring
    WebsockexNew.Examples.SupervisedClient.monitor_health(adapter.client)
    
    {:ok, %{adapter: adapter}}
  end
  
  # Handle reconnection events
  def handle_info({:gun_down, _, _, _, _}, state) do
    # Log disconnection
    Logger.warn("Deribit connection lost, supervisor will restart")
    {:noreply, state}
  end
end
```

## Supervision Tree Visualization

```
YourApp.Supervisor
    ├── WebsockexNew.Application
    │   └── WebsockexNew.ClientSupervisor
    │       ├── Client_1 (Deribit Production)
    │       ├── Client_2 (Deribit Test)
    │       └── Client_3 (Binance)
    └── YourApp.TradingEngine
```

The supervision strategy ensures that WebSocket connections remain stable and automatically recover from failures, critical for 24/7 financial trading operations.