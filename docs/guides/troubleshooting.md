# Troubleshooting Guide

This guide helps diagnose and resolve common issues when working with WebsockexNova macros and behaviors.

## Table of Contents
1. [Common Issues](#common-issues)
2. [Debugging Techniques](#debugging-techniques)
3. [Performance Issues](#performance-issues)
4. [Connection Problems](#connection-problems)
5. [Behavior Issues](#behavior-issues)
6. [Macro Problems](#macro-problems)
7. [Production Issues](#production-issues)
8. [Diagnostic Tools](#diagnostic-tools)

## Common Issues

### Issue: "undefined function" errors when using macros

**Symptoms:**
```elixir
** (UndefinedFunctionError) function MyApp.Client.connect/1 is undefined or private
```

**Causes:**
1. Macro not properly included
2. Module not compiled
3. Wrong module name

**Solutions:**
```elixir
# Ensure you're using the macro correctly
defmodule MyApp.Client do
  use WebsockexNova.ClientMacro, adapter: MyApp.Adapter  # Check this line
  
  # Your code...
end

# Force recompilation
mix clean
mix compile

# Check module name in iex
iex> Code.ensure_loaded(MyApp.Client)
{:module, MyApp.Client}
```

### Issue: Behaviors not being invoked

**Symptoms:**
- Custom behavior callbacks not being called
- Default behavior executing instead

**Causes:**
1. Missing `@impl` attribute
2. Wrong callback signature
3. Behavior not properly registered

**Solutions:**
```elixir
defmodule MyApp.CustomHandler do
  use WebsockexNova.Behaviors.MessageHandler
  
  # WRONG - missing @impl
  def handle_text_frame(text, state) do
    # This won't be called!
  end
  
  # CORRECT
  @impl WebsockexNova.Behaviors.MessageHandler
  def handle_text_frame(text, state) do
    # This will be called
  end
end

# Verify behavior registration
defmodule MyApp.Adapter do
  use WebsockexNova.Adapter
  
  # Ensure behavior is specified
  def handlers do
    %{
      message: MyApp.CustomHandler,  # Check this mapping
      # ... other handlers
    }
  end
end
```

### Issue: State mutations not persisting

**Symptoms:**
- State changes lost between callbacks
- Unexpected state values

**Causes:**
1. Not returning updated state
2. State key conflicts
3. Async state updates

**Solutions:**
```elixir
defmodule MyApp.StatefulHandler do
  @impl WebsockexNova.Behaviors.MessageHandler
  def handle_text_frame(text, state) do
    # WRONG - state not returned
    Map.put(state, :last_message, text)
    {:ok, state}  # Returns original state!
    
    # CORRECT - return updated state
    new_state = Map.put(state, :last_message, text)
    {:ok, new_state}
    
    # ALSO CORRECT - pipeline style
    {:ok, Map.put(state, :last_message, text)}
  end
end
```

## Debugging Techniques

### Enable Debug Logging

Add debug logging to behaviors:

```elixir
defmodule MyApp.DebuggableHandler do
  require Logger
  
  @impl WebsockexNova.Behaviors.MessageHandler
  def handle_text_frame(text, state) do
    Logger.debug("Received: #{inspect(text)}")
    Logger.debug("Current state: #{inspect(state)}")
    
    result = process_message(text, state)
    
    Logger.debug("Result: #{inspect(result)}")
    result
  end
  
  # Add wrapper for debugging
  defp debug_wrap(name, fun) do
    Logger.debug("Entering #{name}")
    start_time = System.monotonic_time()
    
    result = fun.()
    
    duration = System.monotonic_time() - start_time
    Logger.debug("Exiting #{name} (#{duration}ns)")
    
    result
  end
end
```

### Use IEx for Interactive Debugging

```elixir
# Start IEx with your app
iex -S mix

# Set up pry breakpoints
require IEx

defmodule MyApp.DebugHandler do
  @impl WebsockexNova.Behaviors.MessageHandler
  def handle_text_frame(text, state) do
    IEx.pry()  # Execution will pause here
    
    # Examine variables in IEx:
    # iex> text
    # iex> state
    # iex> continue
    
    {:ok, state}
  end
end
```

### Trace Function Calls

Use Erlang tracing to debug behavior execution:

```elixir
# In IEx
:dbg.start()
:dbg.tracer()

# Trace all calls to a module
:dbg.tpl(MyApp.CustomHandler, :_, [])
:dbg.p(:all, :c)

# Execute some operations
{:ok, conn} = MyApp.Client.connect()
MyApp.Client.send_text(conn, "test")

# Stop tracing
:dbg.stop()
```

## Performance Issues

### Issue: High memory usage

**Symptoms:**
- Memory growing over time
- Process mailbox overflow
- OOM errors

**Diagnosis:**
```elixir
# Check process info
Process.info(self(), [:memory, :message_queue_len, :heap_size])

# Monitor memory over time
defmodule MemoryMonitor do
  def start do
    spawn(fn -> monitor_loop() end)
  end
  
  defp monitor_loop do
    memory = :erlang.memory()
    IO.inspect(memory, label: "Memory usage")
    Process.sleep(5000)
    monitor_loop()
  end
end

# Use observer
:observer.start()
```

**Solutions:**
```elixir
# 1. Limit state size
defmodule MyApp.BoundedStateHandler do
  @max_buffer_size 1_000_000  # 1MB
  
  @impl WebsockexNova.Behaviors.MessageHandler
  def handle_text_frame(text, state) do
    new_buffer = state.buffer <> text
    
    # Trim buffer if too large
    trimmed_buffer = if byte_size(new_buffer) > @max_buffer_size do
      binary_part(new_buffer, byte_size(new_buffer) - @max_buffer_size, @max_buffer_size)
    else
      new_buffer
    end
    
    {:ok, %{state | buffer: trimmed_buffer}}
  end
end

# 2. Use ETS for large data
defmodule MyApp.ETSBackedHandler do
  @impl WebsockexNova.Behaviors.ConnectionHandler
  def handle_connect(state, conn, _headers, _opts) do
    table = :ets.new(:conn_data, [:set, :public])
    {:ok, Map.put(state, :data_table, table)}
  end
  
  @impl WebsockexNova.Behaviors.MessageHandler
  def handle_text_frame(text, state) do
    # Store in ETS instead of state
    :ets.insert(state.data_table, {make_ref(), text})
    {:ok, state}
  end
end
```

### Issue: Slow message processing

**Symptoms:**
- High latency
- Message queue buildup
- Timeouts

**Diagnosis:**
```elixir
# Profile message handling
defmodule ProfilingHandler do
  @impl WebsockexNova.Behaviors.MessageHandler
  def handle_text_frame(text, state) do
    :timer.tc(fn ->
      actual_processing(text, state)
    end)
    |> tap(fn {time, _result} ->
      Logger.info("Processing took #{time}μs")
    end)
    |> elem(1)
  end
end

# Use fprof for detailed profiling
:fprof.start()
:fprof.trace([:start])
# Run your code
:fprof.trace([:stop])
:fprof.profile()
:fprof.analyse()
```

**Solutions:**
```elixir
# 1. Optimize JSON parsing
defmodule OptimizedJsonHandler do
  # Pre-compile JSON options
  @json_opts [keys: :atoms]
  
  @impl WebsockexNova.Behaviors.MessageHandler
  def handle_text_frame(text, state) do
    # Use faster JSON library settings
    case Jason.decode(text, @json_opts) do
      {:ok, data} -> process_data(data, state)
      {:error, _} -> {:error, :invalid_json}
    end
  end
end

# 2. Use async processing
defmodule AsyncHandler do
  @impl WebsockexNova.Behaviors.MessageHandler
  def handle_text_frame(text, state) do
    # Offload heavy processing
    Task.start(fn ->
      heavy_processing(text)
    end)
    
    # Return immediately
    {:ok, state}
  end
end
```

## Connection Problems

### Issue: Connection keeps dropping

**Symptoms:**
- Frequent reconnections
- "Connection closed" errors
- Unstable connections

**Diagnosis:**
```elixir
# Add connection monitoring
defmodule ConnectionMonitor do
  use WebsockexNova.Behaviors.ConnectionHandler
  
  @impl true
  def handle_connect(state, conn, headers, opts) do
    Logger.info("Connected: #{inspect(conn)}")
    Logger.debug("Headers: #{inspect(headers)}")
    Logger.debug("Options: #{inspect(opts)}")
    
    # Track connection time
    {:ok, Map.put(state, :connected_at, DateTime.utc_now())}
  end
  
  @impl true
  def handle_disconnect(state, reason) do
    duration = DateTime.diff(DateTime.utc_now(), state.connected_at)
    Logger.warn("Disconnected after #{duration}s: #{inspect(reason)}")
    
    # Log state for debugging
    Logger.debug("State at disconnect: #{inspect(state)}")
    
    {:reconnect, state}
  end
end
```

**Solutions:**
```elixir
# 1. Add keepalive/heartbeat
defmodule HeartbeatHandler do
  use WebsockexNova.Behaviors.MessageHandler
  
  @heartbeat_interval 30_000  # 30 seconds
  
  @impl true
  def handle_connect(state, _conn, _headers, _opts) do
    schedule_heartbeat()
    {:ok, Map.put(state, :last_heartbeat, System.monotonic_time())}
  end
  
  @impl true
  def handle_info(:send_heartbeat, state) do
    send_frame({:text, ~s({"type":"ping"})})
    schedule_heartbeat()
    {:ok, state}
  end
  
  defp schedule_heartbeat do
    Process.send_after(self(), :send_heartbeat, @heartbeat_interval)
  end
end

# 2. Configure connection options
defmodule RobustConnection do
  use WebsockexNova.ClientMacro, adapter: MyApp.Adapter
  
  def connect(overrides \\ %{}) do
    opts = Map.merge(%{
      tcp_opts: [
        keepalive: true,
        nodelay: true,
        send_timeout: 30_000,
        send_timeout_close: true
      ],
      timeout: 60_000,
      compress: true
    }, overrides)
    
    super(opts)
  end
end
```

### Issue: SSL/TLS connection failures

**Symptoms:**
- SSL handshake errors
- Certificate verification failures
- "Connection refused" on secure endpoints

**Solutions:**
```elixir
# Configure SSL options properly
defmodule SecureConnection do
  def connect(url) do
    ssl_opts = [
      verify: :verify_peer,
      cacerts: :certifi.cacerts(),
      depth: 2,
      customize_hostname_check: [
        match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
      ]
    ]
    
    WebsockexNova.Client.connect(MyApp.Adapter, %{
      url: url,
      transport_opts: %{
        tls_opts: ssl_opts
      }
    })
  end
  
  # For self-signed certificates (development only!)
  def connect_insecure(url) do
    WebsockexNova.Client.connect(MyApp.Adapter, %{
      url: url,
      transport_opts: %{
        tls_opts: [verify: :verify_none]
      }
    })
  end
end
```

## Behavior Issues

### Issue: Behavior callbacks not matching expected signatures

**Symptoms:**
- FunctionClauseError
- Pattern match failures
- Unexpected callback results

**Diagnosis:**
```elixir
# Check behavior definition
defmodule BehaviorChecker do
  def check_callbacks(module, behavior) do
    expected_callbacks = behavior.behaviour_info(:callbacks)
    
    Enum.map(expected_callbacks, fn {func, arity} ->
      if function_exported?(module, func, arity) do
        {:ok, {func, arity}}
      else
        {:missing, {func, arity}}
      end
    end)
  end
end

# Usage
BehaviorChecker.check_callbacks(MyApp.CustomHandler, WebsockexNova.Behaviors.MessageHandler)
```

**Solutions:**
```elixir
# Ensure correct callback signatures
defmodule CorrectHandler do
  use WebsockexNova.Behaviors.MessageHandler
  
  # WRONG - missing state parameter
  @impl true
  def handle_text_frame(text) do
    {:ok, %{}}
  end
  
  # CORRECT - proper signature
  @impl true
  def handle_text_frame(text, state) do
    {:ok, state}
  end
  
  # WRONG - wrong return format
  @impl true
  def handle_binary_frame(binary, state) do
    state  # Just returning state
  end
  
  # CORRECT - proper return tuple
  @impl true
  def handle_binary_frame(binary, state) do
    {:ok, state}
  end
end
```

### Issue: Behaviors not composing correctly

**Symptoms:**
- Only one behavior's callbacks executing
- Unexpected behavior interactions
- Lost functionality

**Solutions:**
```elixir
# Properly compose behaviors
defmodule ComposedAdapter do
  use WebsockexNova.Adapter
  
  # Order matters! Later uses can override earlier ones
  use WebsockexNova.Defaults.MessageHandler
  use MyApp.LoggingBehavior
  use MyApp.MetricsBehavior
  
  # Explicit implementation wins
  @impl WebsockexNova.Behaviors.MessageHandler
  def handle_text_frame(text, state) do
    # This overrides all previous implementations
    Logger.debug("Final handler: #{text}")
    {:ok, state}
  end
end

# Use delegation for composition
defmodule DelegatingHandler do
  use WebsockexNova.Behaviors.MessageHandler
  
  @impl true
  def handle_text_frame(text, state) do
    with {:ok, state} <- LoggingBehavior.handle_text_frame(text, state),
         {:ok, state} <- MetricsBehavior.handle_text_frame(text, state),
         {:ok, state} <- process_message(text, state) do
      {:ok, state}
    end
  end
end
```

## Macro Problems

### Issue: Macro expansion errors

**Symptoms:**
- Compilation errors in macro usage
- "undefined function" in macro context
- Unexpected code generation

**Debugging macro expansion:**
```elixir
# See what code the macro generates
defmodule MacroDebug do
  require WebsockexNova.ClientMacro
  
  # Capture macro expansion
  code = quote do
    use WebsockexNova.ClientMacro, adapter: MyApp.Adapter
  end
  
  expanded = Macro.expand(code, __ENV__)
  IO.puts(Macro.to_string(expanded))
end

# Debug macro step by step
defmodule DebuggableMacro do
  defmacro __using__(opts) do
    IO.inspect(opts, label: "Macro options")
    
    ast = quote do
      def generated_function do
        "Generated!"
      end
    end
    
    IO.puts("Generated AST:")
    IO.puts(Macro.to_string(ast))
    
    ast
  end
end
```

### Issue: Variable hygiene problems

**Symptoms:**
- Variable conflicts
- Unexpected variable values
- CompileError about undefined variables

**Solutions:**
```elixir
# Fix variable hygiene issues
defmodule HygienicMacro do
  defmacro __using__(_opts) do
    quote do
      # WRONG - unhygienic variable
      def process do
        result = compute()  # 'result' might conflict
        result
      end
      
      # CORRECT - hygienic variable
      def process do
        var!(result, __MODULE__) = compute()
        var!(result, __MODULE__)
      end
      
      # ALSO CORRECT - use unique names
      def process do
        __result__ = compute()
        __result__
      end
    end
  end
end
```

## Production Issues

### Issue: Memory leaks in production

**Diagnosis:**
```elixir
# Monitor production memory usage
defmodule ProductionMonitor do
  def start_monitoring do
    spawn(fn -> monitor_loop() end)
  end
  
  defp monitor_loop do
    stats = %{
      memory: :erlang.memory(),
      process_count: length(Process.list()),
      message_queues: check_message_queues()
    }
    
    Logger.info("System stats: #{inspect(stats)}")
    
    # Alert on issues
    if stats.memory[:total] > 1_000_000_000 do  # 1GB
      Logger.error("High memory usage: #{stats.memory[:total]}")
    end
    
    Process.sleep(60_000)  # Check every minute
    monitor_loop()
  end
  
  defp check_message_queues do
    Process.list()
    |> Enum.map(fn pid ->
      case Process.info(pid, [:message_queue_len, :registered_name]) do
        [{:message_queue_len, len}, {:registered_name, name}] when len > 1000 ->
          {name || pid, len}
        _ ->
          nil
      end
    end)
    |> Enum.filter(&(&1 != nil))
  end
end
```

**Solutions:**
```elixir
# Implement circuit breakers
defmodule ProductionCircuitBreaker do
  use GenServer
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def check_health do
    GenServer.call(__MODULE__, :check_health)
  end
  
  @impl true
  def init(opts) do
    state = %{
      failures: 0,
      threshold: opts[:threshold] || 5,
      status: :closed,
      reset_after: opts[:reset_after] || 60_000
    }
    
    schedule_health_check()
    {:ok, state}
  end
  
  @impl true
  def handle_info(:health_check, state) do
    new_state = perform_health_check(state)
    schedule_health_check()
    {:noreply, new_state}
  end
  
  defp perform_health_check(state) do
    case check_system_health() do
      :ok ->
        %{state | failures: 0, status: :closed}
      
      :error when state.failures >= state.threshold ->
        Logger.error("Circuit breaker opened!")
        Process.send_after(self(), :reset, state.reset_after)
        %{state | status: :open}
      
      :error ->
        %{state | failures: state.failures + 1}
    end
  end
end
```

### Issue: Performance degradation over time

**Solutions:**
```elixir
# Implement connection recycling
defmodule ConnectionRecycler do
  use GenServer
  
  @recycle_after :timer.hours(24)
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @impl true
  def init(opts) do
    schedule_recycle()
    {:ok, %{connections: %{}, opts: opts}}
  end
  
  @impl true
  def handle_info(:recycle_connections, state) do
    Logger.info("Recycling connections...")
    
    new_connections = Enum.reduce(state.connections, %{}, fn {id, conn}, acc ->
      # Close old connection
      WebsockexNova.Client.close(conn)
      
      # Create new connection
      {:ok, new_conn} = WebsockexNova.Client.connect(state.opts)
      Map.put(acc, id, new_conn)
    end)
    
    schedule_recycle()
    {:noreply, %{state | connections: new_connections}}
  end
  
  defp schedule_recycle do
    Process.send_after(self(), :recycle_connections, @recycle_after)
  end
end
```

## Diagnostic Tools

### Built-in Diagnostics

```elixir
defmodule WebsockexNova.Diagnostics do
  def check_system do
    %{
      behaviors_loaded: check_behaviors(),
      adapters_available: check_adapters(),
      connections_active: check_connections(),
      memory_usage: check_memory(),
      message_queues: check_queues()
    }
  end
  
  defp check_behaviors do
    [
      WebsockexNova.Behaviors.MessageHandler,
      WebsockexNova.Behaviors.ConnectionHandler,
      WebsockexNova.Behaviors.ErrorHandler,
      WebsockexNova.Behaviors.AuthHandler
    ]
    |> Enum.map(fn mod ->
      {mod, Code.ensure_loaded?(mod)}
    end)
    |> Enum.into(%{})
  end
  
  defp check_adapters do
    # List all modules implementing adapter behavior
    :code.all_loaded()
    |> Enum.filter(fn {mod, _} ->
      Code.ensure_loaded?(mod) and
      function_exported?(mod, :behaviour_info, 1) and
      mod.behaviour_info(:callbacks) == WebsockexNova.Adapter.behaviour_info(:callbacks)
    end)
    |> Enum.map(&elem(&1, 0))
  end
end
```

### Custom Health Checks

```elixir
defmodule MyApp.HealthCheck do
  def run_all_checks do
    checks = [
      {:connection_health, &check_connection_health/0},
      {:message_processing, &check_message_processing/0},
      {:memory_usage, &check_memory_usage/0},
      {:behavior_health, &check_behavior_health/0}
    ]
    
    Enum.map(checks, fn {name, check_fn} ->
      {name, safe_check(check_fn)}
    end)
    |> Enum.into(%{})
  end
  
  defp safe_check(check_fn) do
    try do
      check_fn.()
    rescue
      e -> {:error, Exception.format(:error, e)}
    end
  end
  
  defp check_connection_health do
    # Test connection establishment
    case WebsockexNova.Client.connect(MyApp.Adapter, %{url: "ws://localhost:4000/health"}) do
      {:ok, conn} ->
        WebsockexNova.Client.close(conn)
        :ok
      
      {:error, reason} ->
        {:error, reason}
    end
  end
end
```

## Best Practices

1. **Always Log Errors**: Use structured logging for easier debugging
2. **Add Telemetry**: Instrument your behaviors with telemetry events
3. **Test Error Paths**: Don't just test happy paths
4. **Monitor Production**: Set up proper monitoring and alerting
5. **Use Circuit Breakers**: Prevent cascading failures
6. **Profile Regularly**: Performance characteristics change over time
7. **Document Issues**: Keep a runbook of common problems and solutions
8. **Version Everything**: Track behavior and macro versions carefully

## Next Steps

- Review [Migration Guide](migration_guide.md)
- Explore [Performance Tuning](performance_tuning.md)
- Check [Testing Guide](testing_behaviors.md)