# Real API Testing Infrastructure Design

## Overview

This document outlines the design for enhancing WebsockexNew's real API testing infrastructure. Building on the existing solid foundation (MockWebSockServer, real endpoint testing, integration tags), we'll add advanced testing scenarios and environment management.

## Current Foundation (Strengths)

✅ **Real API First Policy** - Tests against `test.deribit.com`  
✅ **Sophisticated Mock Server** - Cowboy + WebSockAdapter based  
✅ **Integration Test Separation** - `@moduletag :integration`  
✅ **Proper Test Helpers** - MockWebSockServer, CertificateHelper, GunMonitor  
✅ **Connection Lifecycle Testing** - Connect → Auth → Subscribe → Close  

## Enhancement Architecture

### 1. Test Environment Framework

```elixir
# test/support/test_environment.ex
defmodule WebsockexNew.TestEnvironment do
  @moduledoc """
  Manages test environments for real API testing.
  Supports multiple environments and automatic health checks.
  """
  
  @type environment :: :deribit_test | :custom_mock | :local_server
  @type config :: %{
    endpoint: String.t(),
    auth: keyword(),
    protocols: [String.t()],
    health_check: boolean()
  }
  
  @spec setup_environment(environment(), keyword()) :: {:ok, config()} | {:error, term()}
  def setup_environment(env, opts \\ [])
  
  @spec teardown_environment(config()) :: :ok
  def teardown_environment(config)
  
  @spec health_check(config()) :: :ok | {:error, term()}
  def health_check(config)
end
```

### 2. Advanced Test Server Infrastructure

```elixir
# test/support/configurable_test_server.ex
defmodule WebsockexNew.ConfigurableTestServer do
  @moduledoc """
  Enhanced test server with configurable behavior for testing
  various network conditions and server responses.
  """
  
  @type server_behavior :: %{
    latency: non_neg_integer(),           # Response delay in ms
    error_rate: float(),                  # 0.0 to 1.0
    disconnect_rate: float(),             # Random disconnection rate
    message_corruption: boolean(),        # Corrupt some messages
    protocol_violations: boolean()        # Send invalid WebSocket frames
  }
  
  @spec start_server(keyword()) :: {:ok, port()} | {:error, term()}
  def start_server(opts \\ [])
  
  @spec configure_behavior(port(), server_behavior()) :: :ok
  def configure_behavior(port, behavior)
  
  @spec inject_error(port(), atom()) :: :ok
  def inject_error(port, error_type)
end
```

### 3. Network Condition Simulation

```elixir
# test/support/network_simulator.ex
defmodule WebsockexNew.NetworkSimulator do
  @moduledoc """
  Simulates various network conditions for realistic testing.
  """
  
  @type condition :: :slow_connection | :packet_loss | :timeout | :intermittent
  
  @spec simulate_condition(pid(), condition(), keyword()) :: :ok
  def simulate_condition(connection_pid, condition, opts \\ [])
  
  @spec restore_normal_conditions(pid()) :: :ok
  def restore_normal_conditions(connection_pid)
end
```

### 4. Test Data Framework

```elixir
# test/support/test_data.ex
defmodule WebsockexNew.TestData do
  @moduledoc """
  Provides structured test data and message generators.
  """
  
  @spec auth_messages() :: %{valid: binary(), invalid: binary()}
  def auth_messages()
  
  @spec subscription_messages() :: [binary()]
  def subscription_messages()
  
  @spec generate_large_message(pos_integer()) :: binary()
  def generate_large_message(size_kb)
  
  @spec malformed_messages() :: [binary()]
  def malformed_messages()
end
```

### 5. Enhanced Test Patterns

```elixir
# test/support/api_test_helpers.ex
defmodule WebsockexNew.ApiTestHelpers do
  @moduledoc """
  Standardized patterns for real API testing.
  """
  
  @spec with_real_api(atom(), keyword(), (map() -> any())) :: any()
  def with_real_api(environment, opts \\ [], test_func)
  
  @spec assert_connection_lifecycle(pid()) :: :ok
  def assert_connection_lifecycle(client_pid)
  
  @spec measure_performance((() -> any())) :: {any(), pos_integer()}
  def measure_performance(test_func)
  
  @spec assert_resource_cleanup(pid()) :: :ok
  def assert_resource_cleanup(client_pid)
end
```

## Implementation Plan

### Phase 1: Environment Management
1. **TestEnvironment module** - Multi-environment support
2. **Health check utilities** - Automatic endpoint validation
3. **Configuration management** - Environment-specific settings
4. **Mix tasks** - `mix test.env.setup`, `mix test.env.health`

### Phase 2: Advanced Test Server
1. **ConfigurableTestServer** - Enhanced mock server
2. **Behavior injection** - Latency, errors, disconnections
3. **Protocol testing** - Multiple WebSocket subprotocols
4. **Stress testing support** - High connection counts

### Phase 3: Network Simulation
1. **NetworkSimulator** - Condition simulation
2. **Connection quality testing** - Slow, lossy networks
3. **Timeout scenarios** - Various timeout conditions
4. **Recovery testing** - Network restoration scenarios

### Phase 4: Test Data & Patterns
1. **TestData framework** - Structured test messages
2. **Message generators** - Realistic data patterns
3. **ApiTestHelpers** - Standardized test patterns
4. **Performance utilities** - Benchmarking and profiling

## Integration with Existing Infrastructure

### Mix Commands Enhancement
```bash
# Enhanced mix commands
mix test.api               # Run all real API tests
mix test.api.deribit      # Deribit-specific tests
mix test.api.performance  # Performance testing
mix test.api.stress       # Stress testing
mix test.env.health       # Check all environments
```

### Test Organization
```
test/
├── support/
│   ├── test_environment.ex        # NEW: Environment management
│   ├── configurable_test_server.ex # NEW: Advanced mock server
│   ├── network_simulator.ex       # NEW: Network simulation
│   ├── test_data.ex               # NEW: Test data framework
│   ├── api_test_helpers.ex        # NEW: Standardized patterns
│   ├── mock_websock_server.ex     # EXISTING: Enhanced
│   └── mock_websock_handler.ex    # EXISTING: Enhanced
├── integration/                   # NEW: Dedicated integration tests
│   ├── deribit_full_lifecycle_test.exs
│   ├── stress_test.exs
│   ├── network_conditions_test.exs
│   └── multi_environment_test.exs
└── websockex_new/                 # EXISTING: Enhanced
    ├── real_api_test.exs          # NEW: Comprehensive real API tests
    └── examples/
        └── deribit_adapter_test.exs # EXISTING: Enhanced
```

## Success Metrics

### Coverage Goals
- **Real API Coverage**: 90% of client functionality tested against real endpoints
- **Scenario Coverage**: 95% of error conditions and edge cases
- **Environment Coverage**: Tests pass on 3+ different WebSocket servers
- **Performance Coverage**: Latency and throughput benchmarks for all operations

### Quality Gates
- **Resource Leak Detection**: Zero connection/memory leaks
- **Performance Regression**: <5% latency increase between versions
- **Reliability**: 99.9% test pass rate across all environments
- **Recovery Testing**: All failure scenarios have recovery paths

## Benefits

1. **Realistic Testing** - Tests mirror production conditions
2. **Comprehensive Coverage** - All failure modes and edge cases
3. **Performance Assurance** - Continuous performance monitoring
4. **Environment Confidence** - Works across different WebSocket servers
5. **Developer Productivity** - Standardized patterns and utilities

This design enhances the existing solid foundation while maintaining the real API first philosophy and adding the advanced capabilities needed for comprehensive WebSocket client testing.