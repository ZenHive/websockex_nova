# Behavior Composition Patterns

This guide explores advanced patterns for composing behaviors in WebsockexNova to create flexible, maintainable WebSocket clients.

## Table of Contents
1. [Understanding Behavior Composition](#understanding-behavior-composition)
2. [Core Behavior Patterns](#core-behavior-patterns)
3. [Mixing Behaviors](#mixing-behaviors)
4. [Delegation Patterns](#delegation-patterns)
5. [Pipeline Composition](#pipeline-composition)
6. [Error Handling Strategies](#error-handling-strategies)
7. [Advanced Patterns](#advanced-patterns)

## Understanding Behavior Composition

WebsockexNova's behavior system allows you to compose functionality from multiple sources:

```elixir
# Base structure of behavior composition
defmodule MyApp.ComposedAdapter do
  use WebsockexNova.Adapter
  
  # Use default behaviors
  use WebsockexNova.Defaults.ConnectionHandler
  use WebsockexNova.Defaults.MessageHandler
  
  # Mix in custom behaviors
  use MyApp.CustomAuthHandler
  use MyApp.EnhancedErrorHandler
  
  # Override specific callbacks
  @impl WebsockexNova.Behaviors.MessageHandler
  def handle_text_frame(text, state) do
    # Custom implementation with fallback
    case parse_message(text) do
      {:ok, parsed} -> handle_parsed_message(parsed, state)
      {:error, _} -> super(text, state)  # Fall back to default
    end
  end
end
```

## Core Behavior Patterns

### Behavior Stacking

Layer behaviors to build complex functionality from simple pieces:

```elixir
defmodule MyApp.LoggingBehavior do
  defmacro __using__(_opts) do
    quote do
      @impl WebsockexNova.Behaviors.MessageHandler
      def handle_text_frame(text, state) do
        Logger.debug("Received: #{inspect(text)}")
        super(text, state)
      end
      
      @impl WebsockexNova.Behaviors.MessageHandler
      def handle_binary_frame(binary, state) do
        Logger.debug("Received binary: #{byte_size(binary)} bytes")
        super(binary, state)
      end
    end
  end
end

defmodule MyApp.MetricsBehavior do
  defmacro __using__(_opts) do
    quote do
      @impl WebsockexNova.Behaviors.MessageHandler
      def handle_text_frame(text, state) do
        :telemetry.execute([:my_app, :message, :received], %{size: byte_size(text)})
        super(text, state)
      end
    end
  end
end

defmodule MyApp.InstrumentedAdapter do
  use WebsockexNova.Adapter
  use WebsockexNova.Defaults.MessageHandler
  use MyApp.LoggingBehavior  # Add logging layer
  use MyApp.MetricsBehavior  # Add metrics layer
  
  # Final implementation
  @impl WebsockexNova.Behaviors.MessageHandler
  def handle_text_frame(text, state) do
    # This will be called after logging and metrics
    process_message(text, state)
  end
end
```

### Behavior Inheritance

Create hierarchical behavior structures:

```elixir
defmodule MyApp.BaseAuthHandler do
  use WebsockexNova.Behaviors.AuthHandler
  
  @callback validate_credentials(map()) :: {:ok, map()} | {:error, term()}
  @callback build_auth_message(map()) :: map()
  
  @impl true
  def handle_auth(state, credentials) do
    with {:ok, validated} <- validate_credentials(credentials),
         auth_msg <- build_auth_message(validated),
         :ok <- send_auth_message(state, auth_msg) do
      {:ok, Map.put(state, :authenticated, true)}
    end
  end
  
  defp send_auth_message(state, message) do
    # Common sending logic
    WebsockexNova.Client.send_json(state.conn, message)
  end
end

defmodule MyApp.OAuth2Handler do
  use MyApp.BaseAuthHandler
  
  @impl true
  def validate_credentials(%{token: token} = creds) do
    # OAuth2-specific validation
    case verify_token(token) do
      {:ok, claims} -> {:ok, Map.put(creds, :claims, claims)}
      error -> error
    end
  end
  
  @impl true
  def build_auth_message(creds) do
    %{
      type: "auth",
      method: "oauth2",
      token: creds.token
    }
  end
end
```

## Mixing Behaviors

### Selective Behavior Inclusion

Include only the behaviors you need:

```elixir
defmodule MyApp.SelectiveAdapter do
  use WebsockexNova.Adapter
  
  # Only include specific default behaviors
  use WebsockexNova.Defaults.ConnectionHandler
  use WebsockexNova.Defaults.MessageHandler
  
  # Implement others from scratch
  @impl WebsockexNova.Behaviors.ErrorHandler
  def handle_error(error, state) do
    # Custom error handling without defaults
    case error do
      {:network_error, _} -> handle_network_error(error, state)
      {:protocol_error, _} -> handle_protocol_error(error, state)
      _ -> {:stop, error, state}
    end
  end
  
  @impl WebsockexNova.Behaviors.AuthHandler
  def handle_auth(state, credentials) do
    # Custom auth without defaults
    MyApp.AuthService.authenticate(credentials)
  end
end
```

### Conditional Behavior Composition

Choose behaviors based on configuration:

```elixir
defmodule MyApp.ConfigurableAdapter do
  defmacro __using__(opts) do
    rate_limiting? = Keyword.get(opts, :rate_limiting, false)
    caching? = Keyword.get(opts, :caching, false)
    
    quote do
      use WebsockexNova.Adapter
      use WebsockexNova.Defaults.ConnectionHandler
      use WebsockexNova.Defaults.MessageHandler
      
      # Conditionally include behaviors
      if unquote(rate_limiting?) do
        use MyApp.RateLimitingBehavior
      else
        use WebsockexNova.Defaults.RateLimitHandler
      end
      
      if unquote(caching?) do
        use MyApp.CachingBehavior
      end
      
      # Additional implementation
      @impl WebsockexNova.Behaviors.MessageHandler
      def handle_text_frame(text, state) do
        result = super(text, state)
        
        if unquote(caching?) do
          cache_result(text, result)
        end
        
        result
      end
    end
  end
end

# Usage
defmodule MyApp.ProductionAdapter do
  use MyApp.ConfigurableAdapter,
    rate_limiting: true,
    caching: true
end
```

## Delegation Patterns

### Behavior Delegation Chain

Create chains of delegating behaviors:

```elixir
defmodule MyApp.DelegatingBehavior do
  defmacro __using__(opts) do
    delegate_to = Keyword.fetch!(opts, :delegate_to)
    
    quote do
      @delegate_module unquote(delegate_to)
      
      @impl WebsockexNova.Behaviors.MessageHandler
      def handle_text_frame(text, state) do
        # Pre-processing
        modified_text = preprocess_text(text)
        
        # Delegate
        result = @delegate_module.handle_text_frame(modified_text, state)
        
        # Post-processing
        postprocess_result(result)
      end
      
      defp preprocess_text(text) do
        # Override in using module
        text
      end
      
      defp postprocess_result(result) do
        # Override in using module
        result
      end
      
      defoverridable [preprocess_text: 1, postprocess_result: 1]
    end
  end
end

defmodule MyApp.EncryptedMessageHandler do
  use MyApp.DelegatingBehavior,
    delegate_to: WebsockexNova.Defaults.MessageHandler
  
  defp preprocess_text(encrypted_text) do
    {:ok, decrypted} = MyApp.Crypto.decrypt(encrypted_text)
    decrypted
  end
  
  defp postprocess_result({:ok, response} = result) do
    encrypted_response = MyApp.Crypto.encrypt(response)
    {:ok, encrypted_response}
  end
  
  defp postprocess_result(result), do: result
end
```

### Dynamic Delegation

Select delegation targets at runtime:

```elixir
defmodule MyApp.DynamicDelegator do
  use WebsockexNova.Adapter
  
  @impl WebsockexNova.Behaviors.MessageHandler
  def handle_text_frame(text, state) do
    handler = select_handler(text, state)
    handler.handle_text_frame(text, state)
  end
  
  defp select_handler(text, state) do
    case Jason.decode(text) do
      {:ok, %{"type" => "market_data"}} -> MyApp.MarketDataHandler
      {:ok, %{"type" => "order"}} -> MyApp.OrderHandler
      {:ok, %{"type" => "account"}} -> MyApp.AccountHandler
      _ -> WebsockexNova.Defaults.MessageHandler
    end
  end
end
```

## Pipeline Composition

### Behavior Pipeline

Process messages through a pipeline of behaviors:

```elixir
defmodule MyApp.PipelineBehavior do
  defmacro __using__(opts) do
    pipeline = Keyword.get(opts, :pipeline, [])
    
    quote do
      @pipeline unquote(pipeline)
      
      @impl WebsockexNova.Behaviors.MessageHandler
      def handle_text_frame(text, state) do
        Enum.reduce(@pipeline, {:ok, text, state}, fn
          behavior, {:ok, current_text, current_state} ->
            behavior.process(current_text, current_state)
          
          _behavior, error ->
            error
        end)
      end
    end
  end
end

defmodule MyApp.ValidationBehavior do
  def process(text, state) do
    case validate_message(text) do
      :ok -> {:ok, text, state}
      error -> {:error, error}
    end
  end
end

defmodule MyApp.TransformBehavior do
  def process(text, state) do
    transformed = transform_message(text)
    {:ok, transformed, state}
  end
end

defmodule MyApp.PipelinedAdapter do
  use WebsockexNova.Adapter
  use MyApp.PipelineBehavior,
    pipeline: [
      MyApp.ValidationBehavior,
      MyApp.TransformBehavior,
      MyApp.RoutingBehavior
    ]
end
```

### Composable Middleware

Create middleware-style behavior composition:

```elixir
defmodule MyApp.Middleware do
  @callback call(request :: term(), next :: fun()) :: {:ok, term()} | {:error, term()}
end

defmodule MyApp.MiddlewareAdapter do
  use WebsockexNova.Adapter
  
  @middleware_stack [
    MyApp.LoggingMiddleware,
    MyApp.AuthMiddleware,
    MyApp.RateLimitMiddleware,
    MyApp.ProcessingMiddleware
  ]
  
  @impl WebsockexNova.Behaviors.MessageHandler
  def handle_text_frame(text, state) do
    request = %{text: text, state: state}
    
    run_middleware(@middleware_stack, request)
  end
  
  defp run_middleware([], request) do
    # End of chain - process the request
    process_final_request(request)
  end
  
  defp run_middleware([middleware | rest], request) do
    next = fn modified_request ->
      run_middleware(rest, modified_request)
    end
    
    middleware.call(request, next)
  end
end

defmodule MyApp.LoggingMiddleware do
  @behaviour MyApp.Middleware
  
  @impl true
  def call(request, next) do
    Logger.info("Processing: #{inspect(request.text)}")
    result = next.(request)
    Logger.info("Result: #{inspect(result)}")
    result
  end
end
```

## Error Handling Strategies

### Fallback Behaviors

Implement fallback strategies for error scenarios:

```elixir
defmodule MyApp.FallbackBehavior do
  defmacro __using__(_opts) do
    quote do
      @impl WebsockexNova.Behaviors.ErrorHandler
      def handle_error(error, state) do
        primary_result = handle_primary_error(error, state)
        
        case primary_result do
          {:error, :unhandled} ->
            handle_fallback_error(error, state)
          
          result ->
            result
        end
      end
      
      defp handle_primary_error(error, state) do
        # Override this in using module
        {:error, :unhandled}
      end
      
      defp handle_fallback_error(error, state) do
        # Default fallback
        Logger.error("Unhandled error: #{inspect(error)}")
        {:reconnect, state}
      end
      
      defoverridable [handle_primary_error: 2, handle_fallback_error: 2]
    end
  end
end

defmodule MyApp.ResilientAdapter do
  use WebsockexNova.Adapter
  use MyApp.FallbackBehavior
  
  defp handle_primary_error({:auth_failed, reason}, state) do
    # Try to re-authenticate
    case reauthenticate(state) do
      {:ok, new_state} -> {:ok, new_state}
      _ -> {:error, :unhandled}
    end
  end
  
  defp handle_primary_error(_, _) do
    {:error, :unhandled}
  end
end
```

### Error Recovery Chain

Chain multiple error recovery strategies:

```elixir
defmodule MyApp.RecoveryChain do
  defmodule Strategy do
    @callback can_handle?(error :: term()) :: boolean()
    @callback handle(error :: term(), state :: term()) :: {:ok, term()} | {:error, term()}
  end
  
  defmacro __using__(opts) do
    strategies = Keyword.get(opts, :strategies, [])
    
    quote do
      @recovery_strategies unquote(strategies)
      
      @impl WebsockexNova.Behaviors.ErrorHandler
      def handle_error(error, state) do
        Enum.find_value(@recovery_strategies, {:stop, error, state}, fn strategy ->
          if strategy.can_handle?(error) do
            case strategy.handle(error, state) do
              {:ok, new_state} -> {:ok, new_state}
              _ -> nil
            end
          end
        end)
      end
    end
  end
end

defmodule MyApp.NetworkErrorRecovery do
  @behaviour MyApp.RecoveryChain.Strategy
  
  @impl true
  def can_handle?({:network_error, _}), do: true
  def can_handle?(_), do: false
  
  @impl true
  def handle({:network_error, _reason}, state) do
    # Attempt reconnection with backoff
    {:ok, Map.put(state, :reconnect_attempts, 0)}
  end
end

defmodule MyApp.RobustAdapter do
  use WebsockexNova.Adapter
  use MyApp.RecoveryChain,
    strategies: [
      MyApp.NetworkErrorRecovery,
      MyApp.AuthErrorRecovery,
      MyApp.RateLimitRecovery
    ]
end
```

## Advanced Patterns

### Aspect-Oriented Behaviors

Implement cross-cutting concerns as aspects:

```elixir
defmodule MyApp.AspectBehavior do
  defmacro __before__(function_name, args, body) do
    quote do
      def unquote(function_name)(unquote_splicing(args)) do
        before_aspect(unquote(function_name), unquote(args))
        unquote(body)
      end
    end
  end
  
  defmacro __after__(function_name, args, body) do
    quote do
      def unquote(function_name)(unquote_splicing(args)) do
        result = unquote(body)
        after_aspect(unquote(function_name), unquote(args), result)
        result
      end
    end
  end
  
  defmacro __around__(function_name, args, body) do
    quote do
      def unquote(function_name)(unquote_splicing(args)) do
        around_aspect(unquote(function_name), unquote(args), fn ->
          unquote(body)
        end)
      end
    end
  end
end

defmodule MyApp.TracedAdapter do
  use WebsockexNova.Adapter
  use MyApp.AspectBehavior
  
  @before handle_text_frame(text, state) do
    start_time = System.monotonic_time()
    Process.put(:message_start_time, start_time)
  end
  
  @after handle_text_frame(text, state) do
    duration = System.monotonic_time() - Process.get(:message_start_time)
    :telemetry.execute([:my_app, :message, :duration], %{duration: duration})
  end
  
  @impl WebsockexNova.Behaviors.MessageHandler
  def handle_text_frame(text, state) do
    # Main implementation
    process_message(text, state)
  end
end
```

### Behavior Factories

Generate behaviors dynamically based on configuration:

```elixir
defmodule MyApp.BehaviorFactory do
  def create_handler(config) do
    Module.create(
      Module.concat([MyApp.Generated, "Handler#{:erlang.unique_integer([:positive])}"]),
      quote do
        use WebsockexNova.Behaviors.MessageHandler
        
        @config unquote(Macro.escape(config))
        
        @impl true
        def handle_text_frame(text, state) do
          # Use configuration to determine behavior
          if @config.validate do
            validate_and_process(text, state)
          else
            process_directly(text, state)
          end
        end
      end,
      Macro.Env.location(__ENV__)
    )
  end
end

# Usage
handler = MyApp.BehaviorFactory.create_handler(%{
  validate: true,
  transform: true,
  log_level: :debug
})

defmodule MyApp.DynamicAdapter do
  use WebsockexNova.Adapter
  @handler handler
  
  @impl WebsockexNova.Behaviors.MessageHandler
  defdelegate handle_text_frame(text, state), to: @handler
end
```

## Best Practices

1. **Single Responsibility**: Each behavior should have one clear purpose
2. **Composition over Inheritance**: Prefer composing behaviors over deep inheritance
3. **Explicit Dependencies**: Make behavior dependencies clear
4. **Testability**: Design behaviors to be easily testable in isolation
5. **Documentation**: Document behavior contracts and composition rules
6. **Performance**: Be mindful of the overhead of deeply nested behaviors
7. **Error Boundaries**: Implement clear error boundaries between behaviors

## Next Steps

- Explore [Testing Custom Behaviors](testing_behaviors.md)
- Learn about [Performance Tuning](performance_tuning.md)
- Review [Architectural Patterns](architectural_patterns.md)