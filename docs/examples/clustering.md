# WebSockexNova Clustering Guide

This guide explains how to leverage WebSockexNova's clustering capabilities for high availability, geo-distribution, and fault tolerance in WebSocket applications.

## Clustering Overview

WebSockexNova supports clustered operation through Erlang's distributed capabilities, enhanced with additional features for WebSocket-specific concerns like subscription state sharing and geo-aware connection management.

### When to Use Clustering

Consider clustering for your WebSocket applications when you need:

1. **High Availability**: Maintain service continuity even if individual nodes fail
2. **Geographic Distribution**: Place nodes closer to exchanges or users to reduce latency
3. **Load Balancing**: Distribute connection and processing load across multiple servers
4. **Seamless Failover**: Transfer subscriptions and connections if a node becomes unavailable
5. **Coordinated Rate Limiting**: Manage API rate limits across multiple connection points

## Setting Up Clustering

### Prerequisites

1. Properly configured Erlang distribution
2. Network connectivity between nodes
3. Optional: `libcluster` for automatic node discovery

### Basic Configuration

```elixir
# config/config.exs
config :websockex_nova,
  clustering: [
    enabled: true,
    node_region: "us-east",     # Geographic identifier for this node
    sync_interval: 15_000,      # State sync interval in ms
    distributed_subscriptions: true,
    active_failover: true       # Proactively reconnect on node failure
  ]
```

### Setting Up Node Discovery with libcluster

```elixir
# Add libcluster to your dependencies in mix.exs
defp deps do
  [
    {:websockex_nova, "~> 1.0"},
    {:libcluster, "~> 3.3"}
  ]
end

# Configure libcluster in config/config.exs
config :libcluster,
  topologies: [
    websockex_example: [
      strategy: Cluster.Strategy.Kubernetes,
      config: [
        kubernetes_selector: "app=websockex-nova",
        kubernetes_node_basename: "websockex-nova"
      ]
    ]
  ]
```

### Starting the Cluster Supervisor

```elixir
# In your application.ex
defmodule MyApp.Application do
  use Application

  def start(_type, _args) do
    children = [
      # Other children...

      # Start the clustering supervisor
      {WebSockexNova.ClusterSupervisor, [
        use_libcluster: true,
        node_region: System.get_env("NODE_REGION", "default"),
        sync_interval: 15_000
      ]},

      # Start your WebSocket clients after clustering is initialized
      {MyApp.DeribitWebSocket, [
        name: :deribit_client,
        cluster_enabled: true,
        region_aware: true
      ]}
    ]

    opts = [strategy: :one_for_one, name: MyApp.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
```

## Clustering Components

WebSockexNova implements clustering through several key components:

### 1. ClusterSupervisor

Supervises all clustering-related processes:
- PubSub for inter-node communication
- Cluster manager for node coordination
- Subscription registry for distributed state

### 2. Cluster Manager

Manages node discovery, health monitoring, and region-aware routing:
```elixir
WebSockexNova.Cluster.get_cluster_status()
# => %{
#   nodes: [:"node1@10.0.0.1", :"node2@10.0.0.2"],
#   regions: %{"us-east" => [:"node1@10.0.0.1"], "eu-west" => [:"node2@10.0.0.2"]},
#   status: :ready
# }
```

### 3. Distributed Subscription Registry

Maintains subscription state across the cluster:
```elixir
# Register a subscription (automatically synchronized)
WebSockexNova.Cluster.SubscriptionRegistry.register(
  "sub_123", "price_updates", :deribit_client
)

# Query subscriptions across the cluster
WebSockexNova.Cluster.SubscriptionRegistry.list_subscriptions()
# => [
#   {"sub_123", "price_updates", :deribit_client},
#   {"sub_456", "order_updates", :deribit_client}
# ]
```

### 4. Distributed Rate Limiter

Coordinates rate limits for API calls across the cluster:
```elixir
# Check rate limit before operation
case WebSockexNova.Cluster.RateLimiter.check_rate_limit(:subscribe, :deribit_client) do
  {:ok, _} ->
    # Proceed with operation
    subscribe_to_channel()

  {:rate_limited, retry_after} ->
    # Handle rate limiting
    schedule_retry(retry_after)
end

# Update rate limit counter after operation
WebSockexNova.Cluster.RateLimiter.update_rate_limit(:subscribe, :deribit_client)
```

## Geo-Distribution Strategy

### Region Configuration

Configure regions for your nodes:

```elixir
# Node in US East region
config :websockex_nova,
  clustering: [
    enabled: true,
    node_region: "us-east"
  ]

# Node in EU West region
config :websockex_nova,
  clustering: [
    enabled: true,
    node_region: "eu-west"
  ]
```

### Exchange Region Mapping

Map exchanges to their physical regions for latency optimization:

```elixir
config :websockex_nova,
  exchanges: [
    nyse: [primary_region: "us-east", failover_regions: ["us-west"]],
    lse: [primary_region: "eu-west", failover_regions: ["eu-central"]],
    binance: [primary_region: "ap-east", failover_regions: ["us-east", "eu-west"]],
    deribit: [primary_region: "eu-west", failover_regions: ["us-east"]]
  ]
```

### Geo-Aware Connection Routing

The client API will automatically use geo-routing when configured:

```elixir
# Client with geo-awareness
WebSockexNova.Platform.Deribit.Client.start_link(
  name: :deribit_client,
  region_aware: true  # Will connect using optimal node for Deribit
)

# Override region for specific connection
WebSockexNova.Platform.Binance.Client.start_link(
  name: :binance_client,
  region_aware: true,
  preferred_region: "us-east"  # Force US East even if not optimal
)
```

## High Availability and Failover

### Subscription Persistence

WebSockexNova maintains subscription state across the cluster, allowing for seamless recovery if a node fails:

```elixir
# Original subscription on Node 1
{:ok, subscription_id} = WebSockexNova.Platform.Deribit.Subscription.subscribe(
  :deribit_client,
  ["BTC-PERPETUAL.trades"],
  persistent: true  # Mark as persistent across nodes
)

# If Node 1 fails, Node 2 can take over:
WebSockexNova.Cluster.FailoverManager.takeover_subscriptions(
  :deribit_client,
  source_node: :"node1@10.0.0.1"
)
```

### Connection Failover

Automatic failover when a node becomes unavailable:

```elixir
config :websockex_nova,
  failover: [
    enabled: true,
    strategy: :immediate,  # or :delayed
    delay: 2_000,          # ms to wait before failover
    max_attempts: 3        # maximum failover attempts
  ]
```

### Manual Failover

Trigger manual failover between nodes:

```elixir
WebSockexNova.Cluster.transfer_client(
  :deribit_client,
  target_node: :"node2@10.0.0.2"
)
```

## Monitoring Cluster Health

### Cluster Telemetry

WebSockexNova emits telemetry events specific to clustering operations:

```
[:websockex_nova, :cluster, :node, :joined]
[:websockex_nova, :cluster, :node, :left]
[:websockex_nova, :cluster, :subscription, :synchronized]
[:websockex_nova, :cluster, :failover, :started]
[:websockex_nova, :cluster, :failover, :completed]
```

### Health Check API

Check cluster status programmatically:

```elixir
# Basic health check
WebSockexNova.Cluster.healthy?()  # => true/false

# Detailed health information
WebSockexNova.Cluster.health_check()
# => %{
#   nodes_available: 3,
#   nodes_total: 3,
#   subscriptions_synced: true,
#   sync_lag_ms: 12,
#   partitions: false
# }
```

## Advanced Clustering Scenarios

### Cross-Region Load Balancing

For 24/7 trading applications, distribute load based on active market hours:

```elixir
config :websockex_nova,
  clustering: [
    enabled: true,
    load_balancing: [
      strategy: :market_hours,
      markets: [
        asian: [
          active_hours: [0..8],  # UTC hours
          primary_region: "ap-east"
        ],
        european: [
          active_hours: [7..16],
          primary_region: "eu-west"
        ],
        american: [
          active_hours: [13..22],
          primary_region: "us-east"
        ]
      ]
    ]
  ]
```

### Partial Cluster Operation

Run with only certain components in clustered mode:

```elixir
config :websockex_nova,
  clustering: [
    enabled: true,
    components: [
      subscriptions: true,    # Share subscription state
      rate_limits: true,      # Share rate limit counters
      telemetry: false,       # Don't distribute telemetry
      reconnection: false     # Don't coordinate reconnections
    ]
  ]
```

### Multi-Cluster Configuration

For very large deployments, create multiple clusters with bridges:

```elixir
config :websockex_nova,
  clustering: [
    enabled: true,
    cluster_name: "us-finance-cluster",
    bridge_clusters: ["eu-finance-cluster", "asia-finance-cluster"],
    bridge_mode: :subscriptions_only  # Only share subscription state
  ]
```

## Common Clustering Issues and Solutions

### Network Partitions

Problem: Nodes lose connectivity with each other but remain operational, leading to "split-brain" scenarios.

Solution:
```elixir
config :websockex_nova,
  clustering: [
    enabled: true,
    partition_handling: :pause_minority,  # or :pause_all
    quorum_size: 2  # Minimum nodes required for operation
  ]
```

### Subscription Inconsistency

Problem: Subscription state becomes inconsistent across nodes.

Solution: Force a subscription state synchronization:
```elixir
WebSockexNova.Cluster.SubscriptionRegistry.force_sync()
```

### Load Imbalance

Problem: Connections concentrate on specific nodes.

Solution: Enable active load balancing:
```elixir
config :websockex_nova,
  clustering: [
    enabled: true,
    load_balancing: [
      strategy: :least_connections,
      rebalance_interval: 60_000,  # ms
      max_imbalance: 0.2           # 20% tolerance
    ]
  ]
```

## Best Practices

### 1. Network Configuration

- Use low-latency, reliable network connections between nodes
- Configure firewalls to allow Erlang distribution ports
- Consider using encrypted Erlang distribution for security

### 2. Scaling Strategies

- **Vertical Scaling**: Add more resources to existing nodes
- **Horizontal Scaling**: Add more nodes to the cluster
- **Geographic Scaling**: Add nodes in different regions

### 3. Production Readiness Checklist

- [ ] Erlang distribution secured with cookies and potentially TLS
- [ ] Network configured for node communication
- [ ] Node discovery mechanism tested
- [ ] Failover scenarios tested
- [ ] Monitoring and alerts configured
- [ ] Subscription persistence verified
- [ ] Rate limiting tested across cluster

### 4. Troubleshooting Commands

```elixir
# List all nodes in the cluster
Node.list()

# Check if a specific node is connected
Node.connect(:"node2@10.0.0.2")

# Verify distributed registry
:ets.tab2list(:websockex_nova_subscriptions)

# Check Erlang distribution status
:net_kernel.get_status()
```

## Clustering with Kubernetes

For Kubernetes deployments, use StatefulSets and the Kubernetes libcluster strategy:

```yaml
# Example Kubernetes StatefulSet
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: websockex-nova
spec:
  serviceName: websockex-nova
  replicas: 3
  selector:
    matchLabels:
      app: websockex-nova
  template:
    metadata:
      labels:
        app: websockex-nova
    spec:
      containers:
      - name: websockex-nova
        image: your-registry/websockex-nova:latest
        env:
        - name: NODE_NAME
          valueFrom:
            fieldRef:
              fieldPath: metadata.name
        - name: POD_IP
          valueFrom:
            fieldRef:
              fieldPath: status.podIP
        - name: RELEASE_COOKIE
          valueFrom:
            secretKeyRef:
              name: erlang-cookie
              key: cookie
        # Region can be set via node selectors or explicit env var
        - name: NODE_REGION
          value: "us-east"
```

## Conclusion

WebSockexNova's clustering capabilities provide robust support for high-availability, geo-distributed WebSocket applications. By leveraging the power of Erlang distribution along with WebSockexNova's specialized clustering components, you can build WebSocket systems that are resilient to failures, optimize for geographic proximity, and efficiently distribute load across multiple nodes.

For specific platform integration examples with clustering, refer to the examples directory.
