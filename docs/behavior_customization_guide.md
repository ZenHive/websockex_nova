# WebsockexNova Behavior Customization Guide

## Quickstart: Ergonomic Connection Flow

WebsockexNova now provides a simple, ergonomic API for connecting and sending messages:

```elixir
{:ok, conn} = WebsockexNova.Connection.start_link(adapter: WebsockexNova.Platform.Echo.Adapter)
WebsockexNova.Client.send_text(conn, "Hello")
```

- `conn` is a `%WebsockexNova.ClientConn{}` struct, ready for use with all client functions.
- No manual WebSocket upgrade or struct building required.

**Advanced users:** If you need full control, use `WebsockexNova.Connection.start_link_raw/1` to get the raw process pid and manage upgrades yourself.

---

## Adapter Macro: Fast, Consistent Adapter Authoring

To make building adapters as easy and consistent as possible, WebsockexNova provides a macro: `use WebsockexNova.Adapter`.

### What does it do?

- Injects all core `@behaviour` declarations for connection, message, subscription, auth, error, rate limit, logging, and metrics handlers.
- Provides safe, no-op default implementations for all optional callbacks.
- Lets you override only what you need—implement just the required callbacks for your use case.
- Ensures your adapter is always up-to-date with the latest handler contracts.

### How to use it

```elixir
defmodule MyApp.Platform.MyAdapter do
  use WebsockexNova.Adapter

  @impl WebsockexNova.Behaviors.ConnectionHandler
  def handle_connect(conn_info, state), do: {:ok, state}

  @impl WebsockexNova.Behaviors.SubscriptionHandler
  def subscribe(channel, params, state), do: {:subscribed, channel, params, state}

  # ...implement only the callbacks you need...
end
```

**Tip:** You only need to implement the required callbacks for your adapter. All optional callbacks have safe defaults, so you can focus on your platform logic.

**Recommended:** Start every new adapter with `use WebsockexNova.Adapter` for maximum maintainability and minimal boilerplate.

---

This guide provides a comprehensive overview of how to implement custom behaviors in WebsockexNova,
allowing you to tailor WebSocket communication to your specific needs.

## Behavior Architecture Overview

WebsockexNova uses a behavior-based architecture that separates different concerns:

1. **Connection Handling**: Managing WebSocket connection lifecycle
2. **Message Processing**: Handling incoming messages
3. **Subscription Management**: Tracking and managing channel subscriptions
4. **Authentication**: Handling credentials and authentication flows
5. **Error Handling**: Processing and recovering from errors
6. **Rate Limiting**: Controlling the flow of messages
7. **Logging**: Providing visibility into WebSocket operations
8. **Metrics Collection**: Gathering performance and usage data

Each behavior has a default implementation in the `WebsockexNova.Defaults` namespace, but you can
replace any of them with your own implementation.

## Available Behaviors

### ConnectionHandler

Responsible for handling WebSocket connection lifecycle events.

```elixir
defmodule MyApp.CustomConnectionHandler do
  @behaviour WebsockexNova.Behaviors.ConnectionHandler

  @impl true
  def init(opts) do
    # Initialize state
    {:ok, %{
      reconnect_attempts: 0,
      max_reconnect_attempts: Keyword.get(opts, :max_reconnect_attempts, 5),
      connection_stats: %{connects: 0, disconnects: 0}
    }}
  end

  @impl true
  def handle_connect(conn_info, state) do
    # Called when the WebSocket connection is established
    IO.puts("Connected to #{conn_info.host}:#{conn_info.port}")

    updated_state = update_in(state.connection_stats.connects, &(&1 + 1))

    # Return updated state
    {:ok, updated_state}
  end

  @impl true
  def handle_disconnect({:remote, code, reason}, state) do
    # Called when the server closes the connection
    IO.puts("Server closed connection: #{code} - #{reason}")

    updated_state = update_in(state.connection_stats.disconnects, &(&1 + 1))

    # Implement reconnection logic
    if state.reconnect_attempts < state.max_reconnect_attempts do
      {:reconnect, %{updated_state | reconnect_attempts: state.reconnect_attempts + 1}}
    else
      {:stop, :max_reconnect_attempts_reached, updated_state}
    end
  end

  def handle_disconnect({:local, _code, _reason}, state) do
    # Called when the client closes the connection
    # No reconnection for client-initiated disconnections
    {:ok, state}
  end

  @impl true
  def handle_frame(:ping, _data, state) do
    # Respond to ping with pong
    {:reply, :pong, "", state}
  end

  def handle_frame(:pong, _data, state) do
    # Process pong response
    {:ok, state}
  end

  def handle_frame(_type, _data, state) do
    # Handle other frame types
    {:ok, state}
  end

  @impl true
  def handle_timeout(state) do
    # Called when a connection timeout occurs
    if state.reconnect_attempts < state.max_reconnect_attempts do
      {:reconnect, %{state | reconnect_attempts: state.reconnect_attempts + 1}}
    else
      {:stop, :max_reconnect_attempts_reached, state}
    end
  end
end
```

### MessageHandler

Processes incoming WebSocket messages.

```elixir
defmodule MyApp.CustomMessageHandler do
  @behaviour WebsockexNova.Behaviors.MessageHandler

  require Logger

  @impl true
  def init(_opts) do
    {:ok, %{messages: []}}
  end

  @impl true
  def handle_message(:text, data, state) do
    # Process text message
    Logger.info("Received text message: #{data}")

    # Try to parse as JSON
    case Jason.decode(data) do
      {:ok, json} ->
        process_json(json, state)

      {:error, _} ->
        # Handle as plain text
        {:ok, %{state | messages: [{:text, data, DateTime.utc_now()} | state.messages]}}
    end
  end

  def handle_message(:binary, data, state) do
    # Process binary message
    Logger.info("Received binary message (#{byte_size(data)} bytes)")
    {:ok, %{state | messages: [{:binary, data, DateTime.utc_now()} | state.messages]}}
  end

  def handle_message(frame_type, data, state) do
    # Process other message types
    Logger.info("Received #{frame_type} message")
    {:ok, %{state | messages: [{frame_type, data, DateTime.utc_now()} | state.messages]}}
  end

  # Private helper
  defp process_json(%{"type" => "update", "data" => data}, state) do
    # Handle specific JSON message type
    Logger.info("Received update: #{inspect(data)}")
    {:ok, %{state | messages: [{:json, data, DateTime.utc_now()} | state.messages]}}
  end

  defp process_json(json, state) do
    # Handle general JSON
    {:ok, %{state | messages: [{:json, json, DateTime.utc_now()} | state.messages]}}
  end
end
```

### SubscriptionHandler

Manages channel subscriptions.

```elixir
defmodule MyApp.CustomSubscriptionHandler do
  @behaviour WebsockexNova.Behaviors.SubscriptionHandler

  require Logger

  @impl true
  def init(_opts) do
    {:ok, %{subscriptions: %{}}}
  end

  @impl true
  def handle_subscribe(channel, params, state) do
    # Process subscription request
    Logger.info("Subscribing to channel: #{channel}")

    # Update subscriptions map
    new_state = put_in(state.subscriptions[channel], params)

    # Return subscription request for the platform adapter
    {:subscribe, channel, params, new_state}
  end

  @impl true
  def handle_unsubscribe(channel, state) do
    # Process unsubscription request
    Logger.info("Unsubscribing from channel: #{channel}")

    # Update subscriptions map
    {_, new_subscriptions} = Map.pop(state.subscriptions, channel)
    new_state = %{state | subscriptions: new_subscriptions}

    # Return unsubscription request for the platform adapter
    {:unsubscribe, channel, new_state}
  end

  @impl true
  def handle_subscription_success(channel, result, state) do
    # Handle successful subscription
    Logger.info("Successfully subscribed to channel: #{channel}")

    # Update subscription with result info
    new_state = put_in(state.subscriptions[channel][:status], :active)
    new_state = put_in(new_state.subscriptions[channel][:result], result)

    {:ok, new_state}
  end

  @impl true
  def handle_subscription_error(channel, error, state) do
    # Handle subscription error
    Logger.error("Failed to subscribe to channel: #{channel}, error: #{inspect(error)}")

    # Update subscription with error info
    new_state = put_in(state.subscriptions[channel][:status], :error)
    new_state = put_in(new_state.subscriptions[channel][:error], error)

    # Decide whether to retry
    {:retry, new_state}
  end

  @impl true
  def handle_list_subscriptions(state) do
    # Return the list of active subscriptions
    {:reply, state.subscriptions, state}
  end
end
```

### AuthHandler

Manages authentication flows.

```elixir
defmodule MyApp.CustomAuthHandler do
  @behaviour WebsockexNova.Behaviors.AuthHandler

  require Logger

  @impl true
  def init(opts) do
    # Initialize state with auth config
    {:ok, %{
      credentials: Keyword.get(opts, :credentials),
      auto_auth: Keyword.get(opts, :auto_auth, false),
      auth_status: :unauthenticated,
      auth_result: nil,
      auth_error: nil,
      last_auth_time: nil
    }}
  end

  @impl true
  def handle_authenticate(credentials, state) do
    # Process authentication request
    Logger.info("Authenticating with credentials: #{inspect(credentials)}")

    # Update state
    new_state = %{
      state |
      credentials: credentials,
      last_auth_time: DateTime.utc_now()
    }

    # Return auth request for the platform adapter
    {:authenticate, credentials, new_state}
  end

  @impl true
  def handle_authentication_success(result, state) do
    # Handle successful authentication
    Logger.info("Authentication succeeded")

    # Update state
    new_state = %{
      state |
      auth_status: :authenticated,
      auth_result: result,
      auth_error: nil
    }

    {:ok, new_state}
  end

  @impl true
  def handle_authentication_error(error, state) do
    # Handle authentication error
    Logger.error("Authentication failed: #{inspect(error)}")

    # Update state
    new_state = %{
      state |
      auth_status: :error,
      auth_error: error
    }

    # Decide whether to retry
    {:retry, new_state}
  end

  @impl true
  def handle_authentication_status(state) do
    # Return current authentication status
    status = %{
      status: state.auth_status,
      last_auth_time: state.last_auth_time,
      result: state.auth_result,
      error: state.auth_error
    }

    {:reply, status, state}
  end
end
```

### ErrorHandler

Processes error scenarios.

```elixir
defmodule MyApp.CustomErrorHandler do
  @behaviour WebsockexNova.Behaviors.ErrorHandler

  require Logger

  @impl true
  def init(_opts) do
    {:ok, %{
      error_count: 0,
      error_history: []
    }}
  end

  @impl true
  def handle_error(:connection, error, state) do
    # Handle connection errors
    Logger.error("Connection error: #{inspect(error)}")

    # Update error history
    new_state = %{
      state |
      error_count: state.error_count + 1,
      error_history: [{:connection, error, DateTime.utc_now()} | state.error_history]
    }

    # Determine if the error is recoverable
    case categorize_error(error) do
      :temporary -> {:retry, new_state}
      :persistent -> {:error, new_state}
    end
  end

  @impl true
  def handle_error(:message, error, state) do
    # Handle message processing errors
    Logger.error("Message error: #{inspect(error)}")

    # Update error history
    new_state = %{
      state |
      error_count: state.error_count + 1,
      error_history: [{:message, error, DateTime.utc_now()} | state.error_history]
    }

    # Message errors are typically non-fatal
    {:continue, new_state}
  end

  @impl true
  def handle_error(:subscription, error, state) do
    # Handle subscription errors
    Logger.error("Subscription error: #{inspect(error)}")

    # Update error history
    new_state = %{
      state |
      error_count: state.error_count + 1,
      error_history: [{:subscription, error, DateTime.utc_now()} | state.error_history]
    }

    # Subscription errors often warrant retry
    {:retry, new_state}
  end

  @impl true
  def handle_error(error_type, error, state) do
    # Handle other error types
    Logger.error("#{error_type} error: #{inspect(error)}")

    # Update error history
    new_state = %{
      state |
      error_count: state.error_count + 1,
      error_history: [{error_type, error, DateTime.utc_now()} | state.error_history]
    }

    # Default handling
    {:continue, new_state}
  end

  # Helper function to categorize errors
  defp categorize_error(error) do
    cond do
      # Network errors are typically temporary
      is_map(error) and Map.has_key?(error, :reason) and error.reason in [:timeout, :closed] ->
        :temporary

      # Authentication errors are persistent
      is_map(error) and Map.has_key?(error, :code) and error.code in [401, 403] ->
        :persistent

      # Default to treating as temporary
      true ->
        :temporary
    end
  end
end
```

### RateLimitHandler

Controls message flow.

```elixir
defmodule MyApp.CustomRateLimitHandler do
  @behaviour WebsockexNova.Behaviors.RateLimitHandler

  require Logger

  @impl true
  def init(opts) do
    # Initialize with rate limit configuration
    {:ok, %{
      # Messages per second
      rate_limit: Keyword.get(opts, :rate_limit, 10),
      # Burst allowed
      burst_limit: Keyword.get(opts, :burst_limit, 20),
      # Track message timestamps
      message_timestamps: [],
      # Track exceeded attempts
      exceeded_count: 0
    }}
  end

  @impl true
  def handle_outgoing_message(message, state) do
    # Check if sending would exceed rate limit
    now = System.monotonic_time(:millisecond)

    # Remove timestamps older than 1 second
    recent_msgs = Enum.filter(
      state.message_timestamps,
      fn ts -> now - ts < 1000 end
    )

    # Check if we've hit the limit
    if length(recent_msgs) >= state.rate_limit do
      # Rate limit exceeded
      Logger.warning("Rate limit exceeded (#{state.rate_limit}/sec)")

      new_state = %{state |
        message_timestamps: recent_msgs,
        exceeded_count: state.exceeded_count + 1
      }

      # Handle based on burst allowance
      if length(recent_msgs) < state.burst_limit do
        # Allow burst
        {:allow, %{new_state | message_timestamps: [now | recent_msgs]}}
      else
        # Deny sending
        {:deny, :rate_limit_exceeded, new_state}
      end
    else
      # Under rate limit, allow
      new_state = %{state | message_timestamps: [now | recent_msgs]}
      {:allow, new_state}
    end
  end

  @impl true
  def handle_rate_limited(message, reason, state) do
    # Handle a rate-limited message
    Logger.warning("Message rate limited: #{reason}")

    # Decide how to handle the rate-limited message
    {:queue, message, state}
  end
end
```

### LoggingHandler

Provides visibility into operations.

```elixir
defmodule MyApp.CustomLoggingHandler do
  @behaviour WebsockexNova.Behaviors.LoggingHandler

  require Logger

  @impl true
  def init(opts) do
    # Initialize with logging configuration
    log_level = Keyword.get(opts, :log_level, :info)

    {:ok, %{
      log_level: log_level,
      log_count: 0,
      start_time: System.monotonic_time(:millisecond)
    }}
  end

  @impl true
  def handle_log(:connection, event, details, state) do
    # Log connection events
    log_message(
      state.log_level,
      "Connection event: #{event}",
      %{details: details, type: :connection}
    )

    {:ok, %{state | log_count: state.log_count + 1}}
  end

  @impl true
  def handle_log(:message, event, details, state) do
    # Log message events
    log_message(
      state.log_level,
      "Message event: #{event}",
      %{details: details, type: :message}
    )

    {:ok, %{state | log_count: state.log_count + 1}}
  end

  @impl true
  def handle_log(:error, event, details, state) do
    # Always log errors at error level
    log_message(
      :error,
      "Error event: #{event}",
      %{details: details, type: :error}
    )

    {:ok, %{state | log_count: state.log_count + 1}}
  end

  @impl true
  def handle_log(type, event, details, state) do
    # Log other event types
    log_message(
      state.log_level,
      "#{type} event: #{event}",
      %{details: details, type: type}
    )

    {:ok, %{state | log_count: state.log_count + 1}}
  end

  # Helper function to log with metadata
  defp log_message(level, message, metadata) do
    case level do
      :debug -> Logger.debug(message, metadata)
      :info -> Logger.info(message, metadata)
      :warning -> Logger.warning(message, metadata)
      :error -> Logger.error(message, metadata)
      _ -> Logger.info(message, metadata)
    end
  end
end
```

### MetricsCollector

Gathers performance and usage data.

```elixir
defmodule MyApp.CustomMetricsCollector do
  @behaviour WebsockexNova.Behaviors.MetricsCollector

  @impl true
  def init(_opts) do
    # Initialize metrics state
    {:ok, %{
      connection_count: 0,
      message_count: 0,
      error_count: 0,
      latency_samples: [],
      last_activity: nil
    }}
  end

  @impl true
  def handle_connection_metric(metric, value, state) do
    # Process connection metrics
    case metric do
      :connected ->
        {:ok, %{state |
          connection_count: state.connection_count + 1,
          last_activity: System.monotonic_time(:millisecond)
        }}

      :disconnected ->
        {:ok, %{state | last_activity: System.monotonic_time(:millisecond)}}

      :latency ->
        # Track latency samples for percentile calculations
        new_samples = [value | state.latency_samples] |> Enum.take(100)
        {:ok, %{state |
          latency_samples: new_samples,
          last_activity: System.monotonic_time(:millisecond)
        }}

      _ ->
        {:ok, %{state | last_activity: System.monotonic_time(:millisecond)}}
    end
  end

  @impl true
  def handle_message_metric(metric, value, state) do
    # Process message metrics
    case metric do
      :received ->
        {:ok, %{state |
          message_count: state.message_count + 1,
          last_activity: System.monotonic_time(:millisecond)
        }}

      :sent ->
        {:ok, %{state |
          last_activity: System.monotonic_time(:millisecond)
        }}

      _ ->
        {:ok, %{state | last_activity: System.monotonic_time(:millisecond)}}
    end
  end

  @impl true
  def handle_error_metric(metric, value, state) do
    # Process error metrics
    case metric do
      :occurred ->
        {:ok, %{state |
          error_count: state.error_count + 1,
          last_activity: System.monotonic_time(:millisecond)
        }}

      _ ->
        {:ok, %{state | last_activity: System.monotonic_time(:millisecond)}}
    end
  end

  @impl true
  def handle_get_metrics(state) do
    # Calculate derived metrics
    avg_latency =
      if Enum.empty?(state.latency_samples) do
        0
      else
        Enum.sum(state.latency_samples) / length(state.latency_samples)
      end

    # Combine metrics
    metrics = %{
      connection: %{
        count: state.connection_count
      },
      messages: %{
        count: state.message_count
      },
      errors: %{
        count: state.error_count
      },
      latency: %{
        average_ms: avg_latency,
        samples: state.latency_samples
      },
      last_activity: state.last_activity
    }

    {:reply, metrics, state}
  end
end
```

## Injecting Custom Behaviors

To use your custom behaviors, pass them as options when starting a connection:

```elixir
{:ok, conn} = WebsockexNova.Connection.start_link(
  adapter: WebsockexNova.Platform.Echo.Adapter,
  connection_handler: MyApp.CustomConnectionHandler,
  message_handler: MyApp.CustomMessageHandler,
  subscription_handler: MyApp.CustomSubscriptionHandler,
  auth_handler: MyApp.CustomAuthHandler,
  error_handler: MyApp.CustomErrorHandler,
  rate_limit_handler: MyApp.CustomRateLimitHandler,
  logging_handler: MyApp.CustomLoggingHandler,
  metrics_collector: MyApp.CustomMetricsCollector
)
```

You can provide any combination of custom handlers - any not specified will use the defaults.

## Integration Patterns

### Client-Side Integration

Create a client module that wraps the connection:

```elixir
defmodule MyApp.WebSocketClient do
  use GenServer

  alias WebsockexNova.Connection
  alias WebsockexNova.Client

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(opts) do
    # Configure connection with custom handlers
    conn_opts = [
      adapter: WebsockexNova.Platform.Echo.Adapter,
      connection_handler: MyApp.CustomConnectionHandler,
      message_handler: MyApp.CustomMessageHandler
    ]

    case Connection.start_link(conn_opts) do
      {:ok, conn} ->
        {:ok, %{conn: conn}}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  # Client API
  def send_message(message) do
    GenServer.call(__MODULE__, {:send, message})
  end

  # Callbacks
  def handle_call({:send, message}, _from, %{conn: conn} = state) do
    reply = Client.send_text(conn, message)
    {:reply, reply, state}
  end
end
```

### Testing Custom Behaviors

Use ExUnit to test your custom behaviors:

```elixir
defmodule MyApp.CustomMessageHandlerTest do
  use ExUnit.Case

  alias MyApp.CustomMessageHandler

  test "handle_message processes text messages correctly" do
    {:ok, initial_state} = CustomMessageHandler.init([])

    {:ok, new_state} = CustomMessageHandler.handle_message(:text, "Hello", initial_state)

    assert length(new_state.messages) == 1
    assert {:text, "Hello", _timestamp} = hd(new_state.messages)
  end

  test "handle_message processes JSON correctly" do
    {:ok, initial_state} = CustomMessageHandler.init([])

    json_string = Jason.encode!(%{type: "update", data: %{value: 42}})
    {:ok, new_state} = CustomMessageHandler.handle_message(:text, json_string, initial_state)

    assert length(new_state.messages) == 1

    # Check that it was parsed as JSON
    {type, data, _timestamp} = hd(new_state.messages)
    assert type == :json
    assert data.value == 42
  end
end
```

## Best Practices

1. **State Management**

   - Keep handler state immutable and use functional updates
   - Consider what should be persisted across reconnections
   - Use meaningful field names in state maps

2. **Error Handling**

   - Use pattern matching to handle different error scenarios
   - Add proper logging for troubleshooting
   - Implement appropriate retry strategies based on error types

3. **Performance**

   - Minimize state size when possible
   - Use ETS tables for larger datasets if needed
   - Consider using process dictionaries for non-critical transient data

4. **Testing**

   - Test each callback function independently
   - Use mocks or stubs for external dependencies
   - Test both success and error scenarios

5. **Integration**
   - Ensure behavior implementations work together harmoniously
   - Consider using an application configuration to define default handlers
   - Document expected interactions between handlers
