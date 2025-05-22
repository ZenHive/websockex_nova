# Testing Custom Behaviors

This guide covers comprehensive testing strategies for WebsockexNew behaviors, ensuring reliable and maintainable custom implementations.

## Table of Contents
1. [Testing Fundamentals](#testing-fundamentals)
2. [Unit Testing Behaviors](#unit-testing-behaviors)
3. [Integration Testing](#integration-testing)
4. [Mock Strategies](#mock-strategies)
5. [Property-Based Testing](#property-based-testing)
6. [Behavior Contract Testing](#behavior-contract-testing)
7. [Performance Testing](#performance-testing)
8. [Common Testing Patterns](#common-testing-patterns)

## Testing Fundamentals

### Test Structure for Behaviors

Set up a consistent testing structure:

```elixir
defmodule MyApp.CustomMessageHandlerTest do
  use ExUnit.Case, async: true
  
  alias MyApp.CustomMessageHandler
  alias WebsockexNew.ClientConn
  
  # Test fixtures
  @valid_message ~s({"type": "heartbeat", "timestamp": 123456})
  @invalid_message "not json"
  
  setup do
    # Create test state
    state = %{
      conn: %ClientConn{
        id: "test-conn-#{:rand.uniform(1000)}",
        adapter: MyApp.TestAdapter,
        state: %{}
      },
      buffer: "",
      subscriptions: %{}
    }
    
    {:ok, state: state}
  end
  
  describe "handle_text_frame/2" do
    test "processes valid JSON messages", %{state: state} do
      assert {:ok, new_state} = CustomMessageHandler.handle_text_frame(@valid_message, state)
      assert new_state.last_heartbeat == 123456
    end
    
    test "handles invalid JSON gracefully", %{state: state} do
      assert {:error, :invalid_json} = CustomMessageHandler.handle_text_frame(@invalid_message, state)
    end
  end
end
```

### Testing Behavior Callbacks

Ensure all callbacks are properly tested:

```elixir
defmodule MyApp.BehaviorCallbackTest do
  use ExUnit.Case
  
  # Define test behavior implementation
  defmodule TestImplementation do
    use MyApp.CustomAuthHandler
    
    @impl true
    def validate_credentials(%{token: "valid"}), do: {:ok, %{user_id: "123"}}
    def validate_credentials(_), do: {:error, :invalid_credentials}
    
    @impl true
    def build_auth_message(creds) do
      %{type: "auth", credentials: creds}
    end
  end
  
  test "behavior callbacks are implemented" do
    # Verify all required callbacks exist
    assert function_exported?(TestImplementation, :validate_credentials, 1)
    assert function_exported?(TestImplementation, :build_auth_message, 1)
    assert function_exported?(TestImplementation, :handle_auth, 2)
  end
  
  test "validates credentials correctly" do
    assert {:ok, _} = TestImplementation.validate_credentials(%{token: "valid"})
    assert {:error, _} = TestImplementation.validate_credentials(%{token: "invalid"})
  end
end
```

## Unit Testing Behaviors

### Isolated Behavior Testing

Test behaviors in isolation from the rest of the system:

```elixir
defmodule MyApp.IsolatedBehaviorTest do
  use ExUnit.Case
  
  defmodule MessageParser do
    @behaviour WebsockexNew.Behaviors.MessageHandler
    
    @impl true
    def handle_text_frame(text, state) do
      case Jason.decode(text) do
        {:ok, %{"type" => type} = message} ->
          handle_message_type(type, message, state)
        {:error, _} ->
          {:error, :invalid_json}
      end
    end
    
    defp handle_message_type("ping", _message, state) do
      {:reply, ~s({"type":"pong"}), state}
    end
    
    defp handle_message_type("data", message, state) do
      updated_state = Map.put(state, :last_data, message["payload"])
      {:ok, updated_state}
    end
    
    defp handle_message_type(_, _, state) do
      {:ok, state}
    end
  end
  
  test "handles ping messages" do
    state = %{}
    assert {:reply, pong, ^state} = MessageParser.handle_text_frame(~s({"type":"ping"}), state)
    assert pong == ~s({"type":"pong"})
  end
  
  test "stores data messages in state" do
    state = %{}
    data_message = ~s({"type":"data","payload":{"value":42}})
    
    assert {:ok, new_state} = MessageParser.handle_text_frame(data_message, state)
    assert new_state.last_data == %{"value" => 42}
  end
end
```

### State Transition Testing

Test how behaviors modify state:

```elixir
defmodule MyApp.StateTransitionTest do
  use ExUnit.Case
  
  defmodule StatefulHandler do
    use WebsockexNew.Behaviors.ConnectionHandler
    
    @impl true
    def handle_connect(state, conn, _headers, _options) do
      new_state = state
        |> Map.put(:status, :connected)
        |> Map.put(:connected_at, DateTime.utc_now())
        |> Map.put(:retry_count, 0)
      
      {:ok, new_state}
    end
    
    @impl true
    def handle_disconnect(state, reason) do
      new_state = state
        |> Map.put(:status, :disconnected)
        |> Map.put(:disconnect_reason, reason)
        |> Map.update(:retry_count, 0, &(&1 + 1))
      
      if new_state.retry_count < 3 do
        {:reconnect, new_state}
      else
        {:stop, new_state}
      end
    end
  end
  
  describe "state transitions" do
    test "connect updates state correctly" do
      initial_state = %{status: :init}
      conn = %ClientConn{id: "test"}
      
      assert {:ok, state} = StatefulHandler.handle_connect(initial_state, conn, [], %{})
      assert state.status == :connected
      assert state.retry_count == 0
      assert %DateTime{} = state.connected_at
    end
    
    test "disconnect with retries" do
      state = %{status: :connected, retry_count: 1}
      
      assert {:reconnect, new_state} = StatefulHandler.handle_disconnect(state, :timeout)
      assert new_state.status == :disconnected
      assert new_state.retry_count == 2
    end
    
    test "disconnect stops after max retries" do
      state = %{status: :connected, retry_count: 2}
      
      assert {:stop, new_state} = StatefulHandler.handle_disconnect(state, :error)
      assert new_state.retry_count == 3
    end
  end
end
```

## Integration Testing

### Testing Behavior Composition

Test how multiple behaviors work together:

```elixir
defmodule MyApp.BehaviorIntegrationTest do
  use ExUnit.Case
  
  defmodule ComposedAdapter do
    use WebsockexNew.Adapter
    use MyApp.LoggingBehavior
    use MyApp.RateLimitBehavior
    use MyApp.CachingBehavior
    
    @impl WebsockexNew.Behaviors.MessageHandler
    def handle_text_frame(text, state) do
      # This will go through logging, rate limiting, and caching
      process_message(text, state)
    end
  end
  
  setup do
    # Start any required processes
    {:ok, _} = MyApp.Cache.start_link()
    {:ok, _} = MyApp.RateLimiter.start_link()
    :ok
  end
  
  test "composed behaviors work together" do
    state = %{adapter: ComposedAdapter}
    
    # First message should pass through all layers
    assert {:ok, _} = ComposedAdapter.handle_text_frame("test1", state)
    
    # Second identical message should be cached
    assert {:cached, _} = ComposedAdapter.handle_text_frame("test1", state)
    
    # Rapid messages should trigger rate limiting
    for i <- 1..100 do
      ComposedAdapter.handle_text_frame("test#{i}", state)
    end
    
    assert {:error, :rate_limited} = ComposedAdapter.handle_text_frame("test101", state)
  end
end
```

### End-to-End Behavior Testing

Test behaviors in a real connection scenario:

```elixir
defmodule MyApp.EndToEndBehaviorTest do
  use ExUnit.Case
  
  alias WebsockexNew.Client
  
  setup do
    # Start test server
    {:ok, server} = MockWebSocketServer.start_link()
    port = MockWebSocketServer.get_port(server)
    
    on_exit(fn ->
      MockWebSocketServer.stop(server)
    end)
    
    {:ok, port: port}
  end
  
  test "custom behaviors work in real connection", %{port: port} do
    # Connect with custom adapter
    {:ok, conn} = Client.connect(MyApp.CustomAdapter, %{
      host: "localhost",
      port: port,
      path: "/test"
    })
    
    # Test authentication behavior
    assert {:ok, _} = Client.authenticate(conn, %{token: "test-token"})
    
    # Test message handling behavior
    assert {:ok, _} = Client.send_json(conn, %{type: "subscribe", channel: "test"})
    
    # Wait for and verify response
    assert_receive {:websocket_message, %{type: "subscribed"}}, 1000
  end
end
```

## Mock Strategies

### Behavior Mocking

Create mocks for testing behavior interactions:

```elixir
defmodule MyApp.BehaviorMocks do
  defmodule MockMessageHandler do
    use WebsockexNew.Behaviors.MessageHandler
    
    def handle_text_frame(text, state) do
      send(self(), {:mock_received, text})
      {:ok, state}
    end
    
    def handle_binary_frame(binary, state) do
      send(self(), {:mock_binary, binary})
      {:ok, state}
    end
  end
  
  defmodule MockAuthHandler do
    use WebsockexNew.Behaviors.AuthHandler
    
    def handle_auth(state, %{token: "valid"} = credentials) do
      send(self(), {:auth_attempt, credentials})
      {:ok, Map.put(state, :authenticated, true)}
    end
    
    def handle_auth(state, credentials) do
      send(self(), {:auth_failed, credentials})
      {:error, :invalid_credentials}
    end
  end
end
```

### Using Mox for Behaviors

Set up behavior mocks with Mox:

```elixir
# In test_helper.exs
Mox.defmock(MyApp.MockMessageHandler, for: WebsockexNew.Behaviors.MessageHandler)
Mox.defmock(MyApp.MockAuthHandler, for: WebsockexNew.Behaviors.AuthHandler)

# In tests
defmodule MyApp.MoxBehaviorTest do
  use ExUnit.Case
  import Mox
  
  setup :verify_on_exit!
  
  test "message handler behavior with mox" do
    state = %{handler: MyApp.MockMessageHandler}
    
    expect(MyApp.MockMessageHandler, :handle_text_frame, fn text, state ->
      assert text == "test message"
      {:ok, Map.put(state, :processed, true)}
    end)
    
    result = state.handler.handle_text_frame("test message", state)
    assert {:ok, %{processed: true}} = result
  end
end
```

## Property-Based Testing

### Testing Behavior Properties

Use property-based testing for behaviors:

```elixir
defmodule MyApp.PropertyBasedBehaviorTest do
  use ExUnit.Case
  use ExUnitProperties
  
  property "message handler always returns valid result" do
    check all text <- string(:ascii),
              state <- map_of(atom(:ascii), term()) do
      
      result = MyApp.CustomMessageHandler.handle_text_frame(text, state)
      
      assert match?(
        {:ok, _} | {:error, _} | {:reply, _, _},
        result
      )
    end
  end
  
  property "auth handler maintains state consistency" do
    check all credentials <- map_of(string(:ascii), string(:ascii)),
              initial_state <- map_of(atom(:ascii), term()) do
      
      case MyApp.AuthHandler.handle_auth(initial_state, credentials) do
        {:ok, new_state} ->
          # Authenticated state should be set
          assert new_state[:authenticated] == true
          
        {:error, _reason} ->
          # State should not indicate authentication
          assert initial_state[:authenticated] != true
      end
    end
  end
end
```

### Stateful Property Testing

Test stateful behavior properties:

```elixir
defmodule MyApp.StatefulPropertyTest do
  use ExUnit.Case
  use ExUnitProperties
  
  defmodule StateMachine do
    defstruct [:state, :handler]
    
    def new(handler) do
      %__MODULE__{state: %{}, handler: handler}
    end
    
    def apply_message(machine, message) do
      case machine.handler.handle_text_frame(message, machine.state) do
        {:ok, new_state} ->
          %{machine | state: new_state}
        {:error, _} ->
          machine
      end
    end
  end
  
  property "subscription handler maintains subscription count" do
    check all messages <- list_of(subscription_message()) do
      machine = StateMachine.new(MyApp.SubscriptionHandler)
      
      final_machine = Enum.reduce(messages, machine, fn msg, acc ->
        StateMachine.apply_message(acc, msg)
      end)
      
      subscription_count = map_size(final_machine.state.subscriptions || %{})
      unique_channels = messages
        |> Enum.filter(&(&1["type"] == "subscribe"))
        |> Enum.map(&(&1["channel"]))
        |> Enum.uniq()
        |> length()
      
      assert subscription_count == unique_channels
    end
  end
  
  defp subscription_message do
    gen all type <- member_of(["subscribe", "unsubscribe"]),
            channel <- string(:ascii, min_length: 1) do
      %{
        "type" => type,
        "channel" => channel
      }
      |> Jason.encode!()
    end
  end
end
```

## Behavior Contract Testing

### Contract Verification

Ensure behaviors meet their contracts:

```elixir
defmodule MyApp.BehaviorContractTest do
  use ExUnit.Case
  
  defmacrop assert_implements_behavior(module, behavior) do
    quote do
      callbacks = unquote(behavior).behaviour_info(:callbacks)
      
      Enum.each(callbacks, fn {func, arity} ->
        assert function_exported?(unquote(module), func, arity),
          "#{unquote(module)} must implement #{func}/#{arity}"
      end)
    end
  end
  
  test "custom handlers implement required behaviors" do
    assert_implements_behavior(MyApp.CustomMessageHandler, WebsockexNew.Behaviors.MessageHandler)
    assert_implements_behavior(MyApp.CustomAuthHandler, WebsockexNew.Behaviors.AuthHandler)
    assert_implements_behavior(MyApp.CustomErrorHandler, WebsockexNew.Behaviors.ErrorHandler)
  end
  
  test "behavior callbacks have correct signatures" do
    # Test that callbacks accept and return expected types
    state = %{}
    text = "test"
    
    result = MyApp.CustomMessageHandler.handle_text_frame(text, state)
    assert match?({:ok, _} | {:error, _} | {:reply, _, _}, result)
  end
end
```

### Behavior Compatibility Testing

Test behavior compatibility across versions:

```elixir
defmodule MyApp.BehaviorCompatibilityTest do
  use ExUnit.Case
  
  # Test that old behavior implementations still work
  defmodule LegacyHandler do
    # Old implementation without new optional callbacks
    def handle_text_frame(text, state) do
      {:ok, state}
    end
    
    def handle_binary_frame(binary, state) do
      {:ok, state}
    end
  end
  
  test "legacy handlers still work with new behavior definitions" do
    # Ensure backward compatibility
    state = %{}
    assert {:ok, ^state} = LegacyHandler.handle_text_frame("test", state)
  end
  
  test "new optional callbacks have defaults" do
    # Test that behaviors provide sensible defaults
    state = %{}
    handler = MyApp.CustomMessageHandler
    
    # If handle_ping is optional with a default
    if function_exported?(handler, :handle_ping, 2) do
      assert {:pong, ^state} = handler.handle_ping("ping", state)
    end
  end
end
```

## Performance Testing

### Behavior Benchmarking

Benchmark behavior performance:

```elixir
defmodule MyApp.BehaviorBenchmark do
  use ExUnit.Case
  
  @tag :benchmark
  test "message processing performance" do
    Benchee.run(%{
      "default_handler" => fn input ->
        WebsockexNew.Defaults.MessageHandler.handle_text_frame(input, %{})
      end,
      "custom_handler" => fn input ->
        MyApp.OptimizedMessageHandler.handle_text_frame(input, %{})
      end,
      "cached_handler" => fn input ->
        MyApp.CachedMessageHandler.handle_text_frame(input, %{})
      end
    }, inputs: %{
      "small_message" => ~s({"type":"ping"}),
      "medium_message" => generate_json_message(100),
      "large_message" => generate_json_message(10_000)
    })
  end
  
  defp generate_json_message(size) do
    data = for i <- 1..size, into: %{}, do: {"key_#{i}", "value_#{i}"}
    Jason.encode!(%{type: "data", payload: data})
  end
end
```

### Load Testing Behaviors

Test behavior performance under load:

```elixir
defmodule MyApp.BehaviorLoadTest do
  use ExUnit.Case
  
  @tag :load_test
  test "behavior handles concurrent messages" do
    state = %{counter: :counters.new(1, [:atomics])}
    message_count = 100_000
    concurrency = 100
    
    # Generate test messages
    messages = for i <- 1..message_count do
      ~s({"id":#{i},"type":"test"})
    end
    
    # Process messages concurrently
    task_supervisor = start_supervised!(Task.Supervisor)
    
    start_time = System.monotonic_time(:millisecond)
    
    tasks = Enum.chunk_every(messages, div(message_count, concurrency))
    |> Enum.map(fn chunk ->
      Task.Supervisor.async(task_supervisor, fn ->
        Enum.each(chunk, fn msg ->
          MyApp.ConcurrentHandler.handle_text_frame(msg, state)
          :counters.add(state.counter, 1, 1)
        end)
      end)
    end)
    
    # Wait for completion
    Enum.each(tasks, &Task.await(&1, :infinity))
    
    end_time = System.monotonic_time(:millisecond)
    duration = end_time - start_time
    
    processed = :counters.get(state.counter, 1)
    rate = processed / (duration / 1000)
    
    IO.puts("Processed #{processed} messages in #{duration}ms (#{rate} msg/sec)")
    assert processed == message_count
  end
end
```

## Common Testing Patterns

### Behavior Test Helpers

Create reusable test helpers:

```elixir
defmodule MyApp.BehaviorTestHelpers do
  @doc """
  Creates a test state with common defaults
  """
  def create_test_state(overrides \\ %{}) do
    %{
      conn: %ClientConn{
        id: "test-#{:rand.uniform(1000)}",
        adapter: MyApp.TestAdapter,
        state: %{}
      },
      buffer: "",
      subscriptions: %{},
      authenticated: false
    }
    |> Map.merge(overrides)
  end
  
  @doc """
  Simulates receiving a message through the behavior
  """
  def receive_message(behavior, message, state) do
    behavior.handle_text_frame(message, state)
  end
  
  @doc """
  Asserts that a behavior properly handles a message
  """
  defmacro assert_message_handled(behavior, message, state) do
    quote do
      result = unquote(behavior).handle_text_frame(unquote(message), unquote(state))
      assert match?({:ok, _} | {:reply, _, _}, result),
        "Expected successful handling, got: #{inspect(result)}"
      result
    end
  end
end
```

### Behavior Testing DSL

Create a DSL for behavior testing:

```elixir
defmodule MyApp.BehaviorTestDSL do
  defmacro __using__(_opts) do
    quote do
      import MyApp.BehaviorTestDSL
      
      def behavior_under_test, do: @behaviour_module
      
      setup do
        state = MyApp.BehaviorTestHelpers.create_test_state()
        {:ok, state: state}
      end
    end
  end
  
  defmacro test_behavior(description, module, do: block) do
    quote do
      describe unquote(description) do
        @behaviour_module unquote(module)
        unquote(block)
      end
    end
  end
  
  defmacro should(description, do: block) do
    quote do
      test unquote(description), %{state: state} do
        unquote(block)
      end
    end
  end
end

# Usage
defmodule MyApp.MessageHandlerBehaviorTest do
  use ExUnit.Case
  use MyApp.BehaviorTestDSL
  
  test_behavior "CustomMessageHandler", MyApp.CustomMessageHandler do
    should "handle valid JSON messages" do
      assert {:ok, _} = behavior_under_test().handle_text_frame(~s({"test":1}), state)
    end
    
    should "reject invalid JSON" do
      assert {:error, _} = behavior_under_test().handle_text_frame("invalid", state)
    end
  end
end
```

## Best Practices

1. **Test All Callbacks**: Ensure every behavior callback is tested
2. **Test Error Cases**: Don't just test happy paths
3. **Test State Transitions**: Verify state changes are correct
4. **Use Property Testing**: For complex state machines
5. **Test Composition**: Verify behaviors work together
6. **Benchmark Critical Paths**: Ensure performance requirements are met
7. **Mock External Dependencies**: Keep tests fast and isolated
8. **Test Contracts**: Verify behavior contracts are maintained

## Next Steps

- Explore [Performance Tuning](performance_tuning.md)
- Learn about [Architectural Patterns](architectural_patterns.md)
- Review [Troubleshooting Guide](troubleshooting.md)