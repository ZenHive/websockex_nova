# HeartbeatManager Critical Infrastructure Architecture

## Executive Summary

HeartbeatManager is **critical financial infrastructure** for WebSocket connections to cryptocurrency exchanges. Failure to respond to heartbeat messages can result in immediate connection termination and automatic order cancellation, potentially causing significant financial losses.

**Risk Level**: CRITICAL - Connection failures during active trading can cancel open orders
**Response Time**: Sub-second required (typically 1-5 second API timeout)
**Uptime Requirement**: 24/7 during active trading sessions

## Core Requirements

### Functional Requirements
1. **Continuous Message Processing**: Handle heartbeat messages 24/7 during connection lifecycle
2. **Platform Agnostic**: Support different heartbeat patterns (Deribit test_request, Binance ping/pong, etc.)
3. **Automatic Response**: Send required responses without manual intervention
4. **Response Time Monitoring**: Track and alert on heartbeat response latencies
5. **Graceful Degradation**: Clean connection termination on heartbeat failure

### Non-Functional Requirements
1. **Reliability**: 99.99% uptime during active connections
2. **Performance**: Sub-second response to heartbeat requests
3. **Fault Tolerance**: Automatic recovery from process failures
4. **Monitoring**: Real-time visibility into heartbeat health
5. **Scalability**: Support multiple concurrent connections

## Architecture Design

### Component Overview
```
┌─────────────────────────────────────────────────────────────┐
│                    Client Connection                        │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────────┐    ┌──────────────────────────────────┐ │
│  │   Gun Process   │◄──►│        HeartbeatManager          │ │
│  │   (WebSocket)   │    │        (GenServer)               │ │
│  └─────────────────┘    └──────────────────────────────────┘ │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────────────────────────────────────────────────┐ │
│  │              Platform Adapter                           │ │
│  │  (Configures heartbeat patterns and responses)          │ │
│  └─────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

### HeartbeatManager GenServer State
```elixir
%HeartbeatManager.State{
  gun_pid: pid(),                    # WebSocket connection process
  stream_ref: reference(),           # WebSocket stream reference
  heartbeat_config: %HeartbeatConfig{}, # Platform-specific configuration
  last_heartbeat: timestamp(),       # Last received heartbeat
  response_times: [duration()],      # Rolling window of response times
  failure_count: integer(),          # Consecutive failures
  monitor_ref: reference()           # Monitor Gun process
}
```

### Platform Configuration System
```elixir
defmodule HeartbeatConfig do
  @type t :: %__MODULE__{
    detector: (message :: binary() -> {:heartbeat, data :: term()} | :not_heartbeat),
    responder: (data :: term() -> {:response, binary()} | :no_response),
    timeout_ms: pos_integer(),       # Maximum response time
    failure_threshold: pos_integer(), # Max consecutive failures before disconnect
    monitoring_enabled: boolean()
  }
end
```

## Platform Implementations

### Deribit Configuration
```elixir
%HeartbeatConfig{
  detector: fn message ->
    case Jason.decode(message) do
      {:ok, %{"method" => "heartbeat", "params" => %{"type" => "test_request"}}} ->
        {:heartbeat, :test_request}
      _ ->
        :not_heartbeat
    end
  end,
  responder: fn :test_request ->
    response = Jason.encode!(%{
      jsonrpc: "2.0",
      method: "public/test",
      params: %{}
    })
    {:response, response}
  end,
  timeout_ms: 3000,
  failure_threshold: 3,
  monitoring_enabled: true
}
```

### Standard WebSocket Ping/Pong Configuration
```elixir
%HeartbeatConfig{
  detector: fn frame ->
    case frame do
      {:ping, payload} -> {:heartbeat, payload}
      _ -> :not_heartbeat
    end
  end,
  responder: fn payload ->
    {:response, {:pong, payload}}
  end,
  timeout_ms: 1000,
  failure_threshold: 2,
  monitoring_enabled: true
}
```

## Process Architecture

### Supervision Strategy
```
Application Supervisor
└── ConnectionSupervisor (one_for_one)
    ├── Client Process
    └── HeartbeatManager (linked to Client)
```

### Process Lifecycle
1. **Startup**: HeartbeatManager started automatically with Client.connect/2
2. **Linking**: HeartbeatManager linked to Client process for coordinated lifecycle
3. **Monitoring**: HeartbeatManager monitors Gun process for connection health
4. **Message Flow**: All Gun messages routed through HeartbeatManager first
5. **Shutdown**: HeartbeatManager terminates with Client or connection loss

### Message Flow
```
Gun Process → HeartbeatManager → Platform Detector → Response Generator → Gun Process
                     ↓
                Application Message Handler (non-heartbeat messages)
```

## Error Handling and Recovery

### Failure Scenarios
1. **HeartbeatManager Process Crash**
   - **Detection**: Client monitors HeartbeatManager
   - **Response**: Restart HeartbeatManager, maintain connection if possible
   - **Fallback**: Close connection if restart fails

2. **Heartbeat Response Timeout**
   - **Detection**: No response sent within timeout_ms
   - **Response**: Log error, increment failure count
   - **Escalation**: Close connection after failure_threshold exceeded

3. **Gun Process Termination**
   - **Detection**: Monitor message from Gun process
   - **Response**: Terminate HeartbeatManager gracefully
   - **Cleanup**: Report connection loss to Client

4. **Response Send Failure**
   - **Detection**: Gun.ws_send/3 returns error
   - **Response**: Retry once immediately
   - **Escalation**: Close connection if retry fails

### Recovery Patterns
- **Exponential Backoff**: For transient failures
- **Circuit Breaker**: For persistent platform issues
- **Graceful Degradation**: Close connections cleanly to prevent phantom orders

## Performance Considerations

### Response Time Requirements
- **Target**: < 500ms response time
- **Warning**: > 1000ms response time
- **Critical**: > 2000ms response time (approaching API timeout)

### Memory Management
- **Response Time Buffer**: Rolling window of last 100 response times
- **Metric Cleanup**: Periodic cleanup of old metrics
- **Process Memory**: Monitor HeartbeatManager memory usage

### Monitoring and Telemetry
```elixir
# Telemetry Events
[:websockex_new, :heartbeat, :received]        # Heartbeat detected
[:websockex_new, :heartbeat, :responded]       # Response sent successfully
[:websockex_new, :heartbeat, :timeout]         # Response timeout
[:websockex_new, :heartbeat, :failure]         # Response send failure
[:websockex_new, :heartbeat_manager, :started] # Process started
[:websockex_new, :heartbeat_manager, :stopped] # Process stopped
```

## Testing Strategy

### Unit Tests
- HeartbeatManager GenServer state transitions
- Platform configuration validation
- Message detection and response generation
- Error handling scenarios

### Integration Tests
- Real API testing with test.deribit.com
- Multi-platform heartbeat pattern testing
- Connection lifecycle with heartbeat management
- Failure recovery scenarios

### Stress Tests
- 24-hour continuous heartbeat processing
- High-frequency heartbeat messages
- Concurrent connection heartbeat handling
- Memory leak detection under load

### Load Tests
- Multiple simultaneous connections
- Heartbeat response time under load
- System resource usage monitoring

## Implementation Phases

### Phase 1: Core Infrastructure (Week 1)
- [ ] HeartbeatManager GenServer implementation
- [ ] Basic heartbeat detection and response
- [ ] Integration with Client.connect/2
- [ ] Unit tests and basic integration tests

### Phase 2: Platform Integration (Week 1)
- [ ] HeartbeatConfig system implementation
- [ ] Deribit platform configuration
- [ ] DeribitAdapter integration with HeartbeatManager
- [ ] Real API testing with test.deribit.com

### Phase 3: Production Hardening (Week 2)
- [ ] Comprehensive error handling and recovery
- [ ] Performance monitoring and telemetry
- [ ] Supervision strategy implementation
- [ ] 24-hour stability testing

### Phase 4: Documentation and Examples (Week 2)
- [ ] Complete API documentation
- [ ] Platform adapter development guide
- [ ] Operational monitoring guide
- [ ] Performance tuning recommendations

## Risk Mitigation

### Development Risks
- **Complexity Creep**: Maintain strict simplicity principles
- **Platform Lock-in**: Ensure true platform agnosticism
- **Performance Degradation**: Continuous performance monitoring

### Operational Risks
- **Silent Failures**: Comprehensive monitoring and alerting
- **Resource Leaks**: Memory and process monitoring
- **Cascade Failures**: Proper isolation and circuit breakers

### Financial Risks
- **Order Cancellation**: Graceful degradation on heartbeat failure
- **Connection Loss**: Immediate cleanup and reconnection
- **Phantom Orders**: Clean connection termination protocols

## Success Metrics

### Reliability Metrics
- **Uptime**: 99.99% HeartbeatManager availability
- **Response Rate**: 99.9% successful heartbeat responses
- **Recovery Time**: < 10 seconds from failure to recovery

### Performance Metrics
- **Response Time**: < 500ms median, < 1000ms 99th percentile
- **Memory Usage**: < 10MB per HeartbeatManager process
- **CPU Usage**: < 1% CPU per active connection

### Operational Metrics
- **Alert Volume**: < 5 heartbeat-related alerts per day
- **Manual Intervention**: Zero manual interventions required
- **Financial Impact**: Zero order cancellations due to heartbeat failures

## Conclusion

HeartbeatManager represents critical infrastructure for financial trading operations. The architecture prioritizes reliability, performance, and operational simplicity while maintaining the flexibility to support multiple trading platforms.

The phased implementation approach ensures early validation with real APIs while building toward production-grade reliability requirements. Comprehensive testing and monitoring provide confidence in deployment to live trading environments.