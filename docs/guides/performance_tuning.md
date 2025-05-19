# Performance Tuning Guide for Behaviors

This guide covers optimization techniques for WebsockexNova behaviors to achieve maximum performance in production systems.

## Table of Contents
1. [Performance Fundamentals](#performance-fundamentals)
2. [Message Processing Optimization](#message-processing-optimization)
3. [State Management](#state-management)
4. [Concurrency Patterns](#concurrency-patterns)
5. [Memory Optimization](#memory-optimization)
6. [Network Optimization](#network-optimization)
7. [Profiling and Benchmarking](#profiling-and-benchmarking)
8. [Real-World Optimizations](#real-world-optimizations)

## Performance Fundamentals

### Understanding Performance Bottlenecks

Common bottlenecks in WebSocket behaviors:

```elixir
defmodule MyApp.PerformanceAnalyzer do
  @moduledoc """
  Identifies performance bottlenecks in behaviors
  """
  
  defmacro analyze_behavior(module) do
    quote do
      # Measure function execution times
      :timer.tc(fn ->
        unquote(module).handle_text_frame("test", %{})
      end)
      |> elem(0)
      |> then(&IO.puts("Execution time: #{&1}µs"))
      
      # Profile memory usage
      :erlang.memory()
      |> Keyword.get(:total)
      |> then(&IO.puts("Memory usage: #{&1} bytes"))
    end
  end
end
```

### Performance Metrics

Key metrics to monitor:

```elixir
defmodule MyApp.PerformanceMetrics do
  @metrics %{
    message_processing_time: "Time to process a single message",
    throughput: "Messages processed per second",
    memory_per_connection: "Memory usage per WebSocket connection",
    cpu_utilization: "CPU usage under load",
    garbage_collection_time: "Time spent in GC"
  }
  
  def start_monitoring do
    :telemetry.attach_many(
      "performance-metrics",
      [
        [:websockex_nova, :message, :processed],
        [:websockex_nova, :connection, :established],
        [:vm, :memory],
        [:vm, :system_counts]
      ],
      &handle_event/4,
      nil
    )
  end
  
  defp handle_event([:websockex_nova, :message, :processed], measurements, metadata, _) do
    # Track message processing performance
    :prometheus_histogram.observe(
      :message_processing_duration_microseconds,
      measurements.duration
    )
  end
end
```

## Message Processing Optimization

### Fast JSON Parsing

Optimize JSON parsing for better performance:

```elixir
defmodule MyApp.OptimizedJsonHandler do
  use WebsockexNova.Behaviors.MessageHandler
  
  # Pre-compile JSON decoder options
  @decoder_opts [keys: :atoms]
  
  # Use faster JSON library (Jason is generally fastest)
  @impl true
  def handle_text_frame(text, state) do
    case Jason.decode(text, @decoder_opts) do
      {:ok, %{type: type} = msg} ->
        handle_by_type(type, msg, state)
      {:error, _} ->
        {:error, :invalid_json}
    end
  end
  
  # Pattern match for common message types
  defp handle_by_type("ping", _, state) do
    {:reply, ~s({"type":"pong"}), state}
  end
  
  defp handle_by_type("data", %{payload: payload}, state) do
    # Process data without intermediate transformations
    process_data_directly(payload, state)
  end
  
  defp handle_by_type(_, _, state) do
    {:ok, state}
  end
end
```

### Binary Message Optimization

Handle binary data efficiently:

```elixir
defmodule MyApp.BinaryOptimizedHandler do
  use WebsockexNova.Behaviors.MessageHandler
  
  @impl true
  def handle_binary_frame(<<
    message_type::8,
    payload_size::32,
    payload::binary-size(payload_size),
    _rest::binary
  >>, state) do
    case message_type do
      1 -> handle_market_data(payload, state)
      2 -> handle_order_update(payload, state)
      3 -> handle_account_update(payload, state)
      _ -> {:ok, state}
    end
  end
  
  defp handle_market_data(<<
    timestamp::64,
    symbol_length::8,
    symbol::binary-size(symbol_length),
    price::float-64,
    volume::float-64
  >>, state) do
    # Direct binary parsing without intermediate steps
    update = %{
      timestamp: timestamp,
      symbol: symbol,
      price: price,
      volume: volume
    }
    
    {:ok, update_market_state(state, update)}
  end
end
```

### Message Batching

Process messages in batches for better throughput:

```elixir
defmodule MyApp.BatchingHandler do
  use WebsockexNova.Behaviors.MessageHandler
  
  @batch_size 100
  @batch_timeout 50  # milliseconds
  
  @impl true
  def handle_text_frame(text, state) do
    state = update_batch(state, text)
    
    cond do
      length(state.batch) >= @batch_size ->
        process_batch(state)
      
      should_flush_batch?(state) ->
        process_batch(state)
      
      true ->
        {:ok, state}
    end
  end
  
  defp update_batch(state, text) do
    batch = Map.get(state, :batch, [])
    last_batch_time = Map.get(state, :last_batch_time, System.monotonic_time())
    
    state
    |> Map.put(:batch, [text | batch])
    |> Map.put(:last_batch_time, last_batch_time)
  end
  
  defp should_flush_batch?(state) do
    last_time = Map.get(state, :last_batch_time, 0)
    current_time = System.monotonic_time(:millisecond)
    
    current_time - last_time > @batch_timeout
  end
  
  defp process_batch(state) do
    messages = Enum.reverse(state.batch)
    
    # Process all messages at once
    results = Parallel.pmap(messages, &process_single_message/1)
    
    new_state = state
      |> Map.put(:batch, [])
      |> Map.put(:last_batch_time, System.monotonic_time(:millisecond))
      |> apply_results(results)
    
    {:ok, new_state}
  end
end
```

## State Management

### Efficient State Storage

Use efficient data structures for state:

```elixir
defmodule MyApp.EfficientStateHandler do
  use WebsockexNova.Behaviors.ConnectionHandler
  
  # Use ETS for large state data
  @impl true
  def handle_connect(state, conn, _headers, _options) do
    table_name = :"conn_state_#{conn.id}"
    :ets.new(table_name, [:named_table, :public, :ordered_set])
    
    new_state = Map.put(state, :state_table, table_name)
    {:ok, new_state}
  end
  
  # Use references instead of copying data
  def store_subscription(state, channel, data) do
    ref = make_ref()
    :ets.insert(state.state_table, {ref, channel, data})
    
    # Store only reference in state
    subscriptions = Map.get(state, :subscriptions, %{})
    Map.put(state, :subscriptions, Map.put(subscriptions, channel, ref))
  end
  
  def get_subscription(state, channel) do
    case Map.get(state.subscriptions, channel) do
      nil -> nil
      ref ->
        case :ets.lookup(state.state_table, ref) do
          [{^ref, ^channel, data}] -> data
          [] -> nil
        end
    end
  end
end
```

### Immutable State Optimization

Optimize immutable state updates:

```elixir
defmodule MyApp.ImmutableStateOptimizer do
  defmodule State do
    @enforce_keys [:id, :subscriptions, :buffer]
    defstruct [
      :id,
      subscriptions: %{},
      buffer: <<>>,
      metrics: %{},
      last_activity: nil
    ]
    
    # Batch multiple updates
    def batch_update(state, updates) do
      Enum.reduce(updates, state, fn
        {:add_subscription, channel, data}, acc ->
          %{acc | subscriptions: Map.put(acc.subscriptions, channel, data)}
        
        {:update_buffer, data}, acc ->
          %{acc | buffer: <<acc.buffer::binary, data::binary>>}
        
        {:update_metrics, metrics}, acc ->
          %{acc | metrics: Map.merge(acc.metrics, metrics)}
        
        {:touch_activity}, acc ->
          %{acc | last_activity: System.monotonic_time()}
      end)
    end
  end
  
  @impl WebsockexNova.Behaviors.MessageHandler
  def handle_text_frame(text, %State{} = state) do
    updates = [
      {:touch_activity},
      {:update_metrics, %{messages_received: 1}},
      parse_subscription_update(text)
    ]
    |> Enum.filter(&(&1 != nil))
    
    new_state = State.batch_update(state, updates)
    {:ok, new_state}
  end
end
```

## Concurrency Patterns

### Parallel Message Processing

Process independent messages concurrently:

```elixir
defmodule MyApp.ParallelProcessor do
  use WebsockexNova.Behaviors.MessageHandler
  
  @impl true
  def handle_text_frame(text, state) do
    case Jason.decode(text) do
      {:ok, %{"batch" => messages}} when is_list(messages) ->
        handle_batch_parallel(messages, state)
      
      {:ok, message} ->
        handle_single_message(message, state)
      
      {:error, _} ->
        {:error, :invalid_json}
    end
  end
  
  defp handle_batch_parallel(messages, state) do
    # Group messages by type for efficient processing
    grouped = Enum.group_by(messages, & &1["type"])
    
    # Process each group in parallel
    tasks = Enum.map(grouped, fn {type, msgs} ->
      Task.async(fn ->
        process_message_group(type, msgs, state)
      end)
    end)
    
    # Collect results
    results = Task.await_many(tasks, 5000)
    
    # Merge state updates
    new_state = Enum.reduce(results, state, &merge_state_updates/2)
    
    {:ok, new_state}
  end
end
```

### Actor-Based Processing

Use actor model for concurrent processing:

```elixir
defmodule MyApp.ActorBasedHandler do
  use WebsockexNova.Behaviors.MessageHandler
  
  defmodule MessageProcessor do
    use GenServer
    
    def start_link(opts) do
      GenServer.start_link(__MODULE__, opts)
    end
    
    def process(pid, message, from) do
      GenServer.cast(pid, {:process, message, from})
    end
    
    @impl true
    def handle_cast({:process, message, from}, state) do
      result = process_message(message)
      send(from, {:processed, result})
      {:noreply, state}
    end
  end
  
  @impl true
  def handle_text_frame(text, state) do
    processor = ensure_processor(state)
    
    MessageProcessor.process(processor, text, self())
    
    # Continue immediately
    {:ok, state}
  end
  
  defp ensure_processor(state) do
    case Map.get(state, :processor) do
      nil ->
        {:ok, pid} = MessageProcessor.start_link([])
        pid
      
      pid ->
        pid
    end
  end
end
```

## Memory Optimization

### Reducing Memory Footprint

Minimize memory usage per connection:

```elixir
defmodule MyApp.MemoryOptimizedHandler do
  use WebsockexNova.Behaviors.ConnectionHandler
  
  # Use atoms for common strings
  @message_types %{
    "subscribe" => :subscribe,
    "unsubscribe" => :unsubscribe,
    "publish" => :publish
  }
  
  # Intern common values
  defmodule Interner do
    def start_link do
      :ets.new(:interned_values, [:named_table, :public, :set])
    end
    
    def intern(value) do
      case :ets.lookup(:interned_values, value) do
        [{^value, interned}] ->
          interned
        [] ->
          ref = make_ref()
          :ets.insert(:interned_values, {value, ref})
          :ets.insert(:interned_values, {ref, value})
          ref
      end
    end
    
    def get(ref) do
      case :ets.lookup(:interned_values, ref) do
        [{^ref, value}] -> value
        [] -> nil
      end
    end
  end
  
  @impl true
  def handle_text_frame(text, state) do
    case Jason.decode(text) do
      {:ok, %{"type" => type_string} = msg} ->
        # Use atoms for known types
        type = Map.get(@message_types, type_string, :unknown)
        
        # Intern channel names
        channel = case msg["channel"] do
          nil -> nil
          ch -> Interner.intern(ch)
        end
        
        handle_typed_message(type, channel, msg, state)
      
      _ ->
        {:error, :invalid_message}
    end
  end
end
```

### Garbage Collection Tuning

Optimize GC for WebSocket connections:

```elixir
defmodule MyApp.GCOptimizedClient do
  use WebsockexNova.ClientMacro, adapter: MyApp.Adapter
  
  def connect(opts \\ %{}) do
    # Tune GC for long-lived connections
    Process.flag(:fullsweep_after, 20)
    Process.flag(:min_heap_size, 4096)
    Process.flag(:min_bin_vheap_size, 10_000)
    
    super(opts)
  end
  
  # Force GC during idle periods
  def handle_idle(state) do
    # Trigger GC when connection is idle
    :erlang.garbage_collect()
    
    {:ok, state}
  end
end
```

## Network Optimization

### Connection Pooling

Implement connection pooling for better resource usage:

```elixir
defmodule MyApp.ConnectionPool do
  use WebsockexNova.Behaviors.ConnectionHandler
  
  defmodule PoolManager do
    use GenServer
    
    def start_link(opts) do
      GenServer.start_link(__MODULE__, opts, name: __MODULE__)
    end
    
    def checkout do
      GenServer.call(__MODULE__, :checkout)
    end
    
    def checkin(conn) do
      GenServer.cast(__MODULE__, {:checkin, conn})
    end
    
    @impl true
    def init(opts) do
      pool_size = Keyword.get(opts, :size, 10)
      
      connections = for _ <- 1..pool_size do
        {:ok, conn} = WebsockexNova.Client.connect(MyApp.Adapter, %{})
        conn
      end
      
      {:ok, %{available: connections, in_use: []}}
    end
    
    @impl true
    def handle_call(:checkout, _from, state) do
      case state.available do
        [conn | rest] ->
          new_state = %{
            available: rest,
            in_use: [conn | state.in_use]
          }
          {:reply, {:ok, conn}, new_state}
        
        [] ->
          {:reply, {:error, :no_connections}, state}
      end
    end
  end
end
```

### Frame Compression

Implement frame compression for bandwidth optimization:

```elixir
defmodule MyApp.CompressedFrameHandler do
  use WebsockexNova.Behaviors.MessageHandler
  
  @compression_threshold 1024  # Compress messages larger than 1KB
  
  @impl true
  def handle_send_frame({:text, text}, state) when byte_size(text) > @compression_threshold do
    compressed = :zlib.compress(text)
    
    # Send as binary frame with compression flag
    frame = <<1::8, compressed::binary>>
    {:binary, frame}
  end
  
  def handle_send_frame(frame, _state) do
    frame
  end
  
  @impl true
  def handle_binary_frame(<<1::8, compressed::binary>>, state) do
    decompressed = :zlib.uncompress(compressed)
    handle_text_frame(decompressed, state)
  end
  
  def handle_binary_frame(binary, state) do
    # Handle regular binary frames
    process_binary(binary, state)
  end
end
```

## Profiling and Benchmarking

### Behavior Profiling

Profile behavior performance:

```elixir
defmodule MyApp.BehaviorProfiler do
  def profile_behavior(behavior_module, sample_messages, state) do
    # CPU profiling
    :fprof.trace([start, {procs, self()}])
    
    Enum.each(sample_messages, fn msg ->
      behavior_module.handle_text_frame(msg, state)
    end)
    
    :fprof.trace(stop)
    :fprof.profile()
    :fprof.analyse([totals: true, details: true, sort: :time])
    
    # Memory profiling
    :recon_alloc.memory(:allocated)
    |> IO.inspect(label: "Memory allocated")
    
    # Process info
    :recon.info(self(), [:memory, :reductions, :message_queue_len])
    |> IO.inspect(label: "Process info")
  end
end
```

### Benchmarking Suite

Create comprehensive benchmarks:

```elixir
defmodule MyApp.BehaviorBenchmarks do
  use Benchee
  
  def run_benchmarks do
    state = %{subscriptions: %{}, buffer: ""}
    
    messages = %{
      "small_json" => ~s({"type":"ping"}),
      "medium_json" => generate_json(100),
      "large_json" => generate_json(10_000),
      "binary_small" => <<1::8, "test"::binary>>,
      "binary_large" => <<1::8, :crypto.strong_rand_bytes(10_000)::binary>>
    }
    
    Benchee.run(
      %{
        "default_handler" => fn {_name, msg} ->
          WebsockexNova.Defaults.MessageHandler.handle_text_frame(msg, state)
        end,
        "optimized_handler" => fn {_name, msg} ->
          MyApp.OptimizedHandler.handle_text_frame(msg, state)
        end,
        "cached_handler" => fn {_name, msg} ->
          MyApp.CachedHandler.handle_text_frame(msg, state)
        end
      },
      inputs: messages,
      memory_time: 2,
      reduction_time: 2,
      formatters: [
        {Benchee.Formatters.HTML, file: "benchmarks.html"},
        Benchee.Formatters.Console
      ]
    )
  end
  
  defp generate_json(size) do
    data = for i <- 1..size, into: %{} do
      {"field_#{i}", "value_#{i}"}
    end
    
    Jason.encode!(%{type: "data", payload: data})
  end
end
```

## Real-World Optimizations

### High-Frequency Trading Optimization

Optimize for financial trading systems:

```elixir
defmodule MyApp.HFTOptimizedHandler do
  use WebsockexNova.Behaviors.MessageHandler
  
  # Pre-allocate buffers
  @buffer_size 64 * 1024  # 64KB pre-allocated buffer
  
  # Use NIF for critical path operations
  @on_load :load_nif
  def load_nif do
    :erlang.load_nif('./priv/fast_parser', 0)
  end
  
  # Native implementation fallback
  def parse_market_data(_binary) do
    raise "NIF not loaded"
  end
  
  @impl true
  def handle_binary_frame(binary, state) do
    # Use NIF for ultra-fast parsing
    case parse_market_data(binary) do
      {:ok, market_data} ->
        process_market_data(market_data, state)
      
      {:error, _} ->
        {:error, :invalid_data}
    end
  end
  
  defp process_market_data(data, state) do
    # Update state without allocations
    state
    |> update_price_book(data)
    |> trigger_strategies(data)
    |> update_metrics(data)
  end
  
  # Zero-copy updates
  defp update_price_book(state, data) do
    %{state | 
      price_book: :array.set(
        data.symbol_index,
        data.price,
        state.price_book
      )
    }
  end
end
```

### IoT Device Optimization

Optimize for constrained IoT environments:

```elixir
defmodule MyApp.IoTOptimizedHandler do
  use WebsockexNova.Behaviors.MessageHandler
  
  # Minimal state for memory-constrained devices
  defstruct [
    device_id: nil,
    last_ping: 0,
    sequence: 0
  ]
  
  # Use binary protocols for efficiency
  @impl true
  def handle_binary_frame(<<
    cmd::8,
    seq::16,
    payload::binary
  >>, state) do
    
    case cmd do
      0x01 -> # PING
        reply = <<0x02::8, seq::16>>
        {:reply, {:binary, reply}, %{state | last_ping: seq}}
      
      0x10 -> # DATA
        handle_data(payload, %{state | sequence: seq})
      
      _ ->
        {:ok, state}
    end
  end
  
  # Compact data representation
  defp handle_data(<<
    temp::16-signed,
    humidity::8,
    pressure::16
  >>, state) do
    
    telemetry = %{
      temperature: temp / 100.0,
      humidity: humidity,
      pressure: pressure
    }
    
    # Store minimal state
    {:ok, Map.put(state, :last_telemetry, telemetry)}
  end
end
```

## Best Practices

1. **Profile First**: Always profile before optimizing
2. **Memory Over CPU**: Optimize memory usage in long-lived connections
3. **Batch Operations**: Process messages in batches when possible  
4. **Use Binary Matching**: Leverage Erlang's efficient binary pattern matching
5. **Avoid Atom Creation**: Don't create atoms dynamically
6. **Preallocate Resources**: Initialize resources during connection setup
7. **Monitor Metrics**: Use telemetry for production monitoring
8. **Test Under Load**: Always benchmark with realistic workloads

## Next Steps

- Explore [Architectural Patterns](architectural_patterns.md)
- Learn about [Troubleshooting](troubleshooting.md)
- Review [Migration Guide](migration_guide.md)