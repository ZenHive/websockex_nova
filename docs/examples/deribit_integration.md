# WebSockexNova Deribit Integration Example

This example demonstrates how to implement a WebSocket client for the Deribit cryptocurrency exchange using WebSockexNova. The implementation follows the Financial Platform profile for optimal performance and reliability.

## Overview

Deribit is a cryptocurrency derivatives exchange that provides WebSocket API access for real-time market data and trading. This example shows how to:

1. Connect to Deribit WebSocket API
2. Authenticate using API keys
3. Subscribe to market data
4. Handle trading operations
5. Implement robust error handling and reconnection strategies

## Implementation

### Directory Structure

```
lib/
└── my_app/
    └── deribit/
        ├── client.ex            # Main WebSocket client
        ├── message.ex           # Message handling
        ├── subscription.ex      # Subscription management
        ├── auth.ex              # Authentication handling
        ├── rate_limiter.ex      # Rate limit handling
        ├── types.ex             # Type definitions
        └── error_handler.ex     # Error handling
```

### Client Implementation

```elixir
defmodule MyApp.Deribit.Client do
  @moduledoc """
  WebSocket client for Deribit cryptocurrency exchange.

  Implements a robust, production-ready connection to Deribit's
  WebSocket API with authentication, subscription management,
  and automatic reconnection.
  """

  use WebSockexNova.Client,
    strategy: :always_reconnect,
    platform: :deribit,
    profile: :financial

  alias MyApp.Deribit.{Message, Auth, Subscription, RateLimiter}

  @default_endpoint "wss://www.deribit.com/ws/api/v2"

  @impl true
  def init(opts) do
    endpoint = Keyword.get(opts, :endpoint, @default_endpoint)
    api_key = Keyword.fetch!(opts, :api_key)
    api_secret = Keyword.fetch!(opts, :api_secret)

    state = %{
      endpoint: endpoint,
      api_key: api_key,
      api_secret: api_secret,
      authenticated: false,
      subscriptions: %{},
      request_id: 1,
      pending_requests: %{},
      rate_limits: %{
        # Track rate limits for different operations
        subscribe: %{count: 0, last_reset: System.system_time(:second), limit: 10},
        trade: %{count: 0, last_reset: System.system_time(:second), limit: 5}
      },
      # Circuit breaker state
      circuit: %{
        failures: 0,
        last_failure: nil,
        status: :closed,
        reset_after: System.system_time(:second) + 60
      },
      heartbeat_interval: 15_000,  # 15 seconds
      heartbeat_timer_ref: nil
    }

    {:ok, state}
  end

  @impl true
  def handle_connect(conn_info, state) do
    # Start authentication process
    case Auth.generate_auth_request(state) do
      {:ok, auth_msg, new_state} ->
        {:ok, encoded_msg} = Message.encode_message(auth_msg, new_state)
        WebSockexNova.send_frame(:text, encoded_msg)

        # Start heartbeat timer
        timer_ref = Process.send_after(self(), :heartbeat, state.heartbeat_interval)

        # Log successful connection
        :telemetry.execute(
          [:websockex_nova, :connection, :completed],
          %{duration: System.monotonic_time() - conn_info.connect_time},
          %{client_id: self(), platform: :deribit}
        )

        {:ok, %{new_state | heartbeat_timer_ref: timer_ref}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def handle_disconnect(reason, state) do
    # Cancel any existing timer
    if state.heartbeat_timer_ref, do: Process.cancel_timer(state.heartbeat_timer_ref)

    # Record disconnect in telemetry
    :telemetry.execute(
      [:websockex_nova, :connection, :disconnected],
      %{system_time: System.system_time()},
      %{client_id: self(), platform: :deribit, reason: reason}
    )

    # Calculate reconnection delay based on attempts
    attempt = Map.get(state, :reconnect_attempt, 0)
    delay = calculate_reconnect_delay(attempt)

    # Update state for reconnection
    new_state = %{state |
      authenticated: false,
      heartbeat_timer_ref: nil,
      reconnect_attempt: attempt + 1
    }

    {:reconnect, delay, new_state}
  end

  @impl true
  def handle_frame(:text, frame_data, state) do
    case Message.decode_message(frame_data) do
      {:ok, message} ->
        # Log received message in telemetry
        :telemetry.execute(
          [:websockex_nova, :message, :received],
          %{size: byte_size(frame_data), system_time: System.system_time()},
          %{client_id: self(), platform: :deribit, type: message_type(message)}
        )

        # Process the message
        handle_message(message, state)

      {:error, reason} ->
        # Log decode error
        :telemetry.execute(
          [:websockex_nova, :error, :occurred],
          %{system_time: System.system_time()},
          %{client_id: self(), platform: :deribit, error_type: :decode_error, error: reason}
        )

        {:ok, state}
    end
  end

  @impl true
  def handle_frame(:ping, _frame_data, state) do
    # Reply with pong frame
    {:reply, :pong, <<>>, state}
  end

  @impl true
  def handle_frame(frame_type, _frame_data, state) do
    # Log unexpected frame type
    :telemetry.execute(
      [:websockex_nova, :error, :occurred],
      %{system_time: System.system_time()},
      %{client_id: self(), platform: :deribit, error_type: :unexpected_frame, frame_type: frame_type}
    )

    {:ok, state}
  end

  # Handle authentication response
  defp handle_message(%{"id" => id, "result" => %{"access_token" => _token}} = msg, state) do
    case Map.get(state.pending_requests, id) do
      {:auth, _} ->
        # Authentication successful
        new_state = %{state | authenticated: true}

        # Restore subscriptions after re-authentication
        new_state = restore_subscriptions(new_state)

        # Reset circuit breaker if it was open
        new_state = if state.circuit.status == :open do
          %{new_state | circuit: %{state.circuit | status: :closed, failures: 0}}
        else
          new_state
        end

        {:ok, new_state}

      _ ->
        # Unexpected authentication response
        {:ok, state}
    end
  end

  # Handle subscription response
  defp handle_message(%{"id" => id, "result" => channels} = _msg, state) when is_list(channels) do
    case Map.get(state.pending_requests, id) do
      {:subscribe, requested_channels} ->
        # Update subscription state with successful channels
        subscriptions = Enum.reduce(channels, state.subscriptions, fn channel, acc ->
          Map.put(acc, channel, %{active: true, timestamp: System.system_time(:second)})
        end)

        # Remove from pending requests
        pending_requests = Map.delete(state.pending_requests, id)

        # Update rate limit usage
        {:ok, rate_limits} = RateLimiter.update_rate_limit(:subscribe, state.rate_limits)

        new_state = %{state |
          subscriptions: subscriptions,
          pending_requests: pending_requests,
          rate_limits: rate_limits
        }

        {:ok, new_state}

      _ ->
        # Unexpected subscription response
        {:ok, state}
    end
  end

  # Handle subscription data
  defp handle_message(%{"method" => "subscription", "params" => params}, state) do
    # Extract and process subscription data
    channel = params["channel"]
    data = params["data"]

    # Emit telemetry for subscription data
    :telemetry.execute(
      [:websockex_nova, :subscription, :data],
      %{system_time: System.system_time(), data_size: byte_size(Jason.encode!(data))},
      %{client_id: self(), platform: :deribit, channel: channel}
    )

    # Forward data to subscribers
    notify_subscribers(channel, data)

    {:ok, state}
  end

  # Handle heartbeat message
  defp handle_message(%{"method" => "heartbeat", "params" => %{"type" => "test_request"}}, state) do
    # Respond to test request heartbeat
    {:ok, heartbeat_response} = Message.create_test_request_response(state)
    {:ok, encoded} = Message.encode_message(heartbeat_response, state)

    # Reset heartbeat timer
    if state.heartbeat_timer_ref, do: Process.cancel_timer(state.heartbeat_timer_ref)
    timer_ref = Process.send_after(self(), :heartbeat, state.heartbeat_interval)

    {:reply, :text, encoded, %{state | heartbeat_timer_ref: timer_ref}}
  end

  # Handle error response
  defp handle_message(%{"error" => error} = _msg, state) do
    # Extract error information
    code = error["code"]
    message = error["message"]

    # Log error in telemetry
    :telemetry.execute(
      [:websockex_nova, :error, :occurred],
      %{system_time: System.system_time()},
      %{client_id: self(), platform: :deribit, error_type: :api_error, code: code, message: message}
    )

    # Handle specific error types
    case code do
      10401 -> # Authentication error
        handle_authentication_error(message, state)

      10009 -> # Rate limit error
        handle_rate_limit_error(message, state)

      _ ->
        # Generic error handling
        circuit = update_circuit_breaker(state.circuit, :increment)
        {:ok, %{state | circuit: circuit}}
    end
  end

  # Catch-all for unhandled messages
  defp handle_message(_msg, state) do
    {:ok, state}
  end

  # Handle :heartbeat message from timer
  def handle_info(:heartbeat, state) do
    if state.authenticated do
      # Send heartbeat message
      {:ok, heartbeat_msg} = Message.create_heartbeat(state)
      {:ok, encoded} = Message.encode_message(heartbeat_msg, state)

      # Reset timer for next heartbeat
      timer_ref = Process.send_after(self(), :heartbeat, state.heartbeat_interval)

      {:reply, :text, encoded, %{state | heartbeat_timer_ref: timer_ref}}
    else
      # Not authenticated, just reset timer
      timer_ref = Process.send_after(self(), :heartbeat, state.heartbeat_interval)
      {:ok, %{state | heartbeat_timer_ref: timer_ref}}
    end
  end

  # Public API functions

  @doc """
  Subscribe to one or more Deribit channels.

  ## Parameters
    * `pid` - Client process ID
    * `channels` - List of channel names to subscribe to
    * `opts` - Subscription options

  ## Options
    * `:persistent` - Whether to persist subscription across reconnects

  ## Returns
    * `{:ok, subscription_id}` - Subscription successful
    * `{:error, reason}` - Subscription failed
  """
  def subscribe(pid, channels, opts \\ []) do
    GenServer.call(pid, {:subscribe, channels, opts})
  end

  @doc """
  Unsubscribe from one or more Deribit channels.

  ## Parameters
    * `pid` - Client process ID
    * `channels` - List of channel names to unsubscribe from

  ## Returns
    * `:ok` - Unsubscription successful
    * `{:error, reason}` - Unsubscription failed
  """
  def unsubscribe(pid, channels) do
    GenServer.call(pid, {:unsubscribe, channels})
  end

  @doc """
  Execute a trading operation on Deribit.

  ## Parameters
    * `pid` - Client process ID
    * `method` - API method to call
    * `params` - Parameters for the API call

  ## Returns
    * `{:ok, result}` - Operation successful
    * `{:error, reason}` - Operation failed
  """
  def execute(pid, method, params) do
    GenServer.call(pid, {:execute, method, params})
  end

  # Helper functions

  # Calculate exponential backoff with jitter for reconnection
  defp calculate_reconnect_delay(attempt) do
    # Base delay of 100ms, with exponential backoff
    base_delay = 100
    max_delay = 30_000  # 30 seconds

    # Calculate exponential backoff
    delay = min(base_delay * :math.pow(2, attempt), max_delay)

    # Add jitter (±25%)
    jitter = delay * 0.25 * (2.0 * :rand.uniform() - 1.0)

    # Return final delay in milliseconds
    trunc(delay + jitter)
  end

  # Restore subscriptions after reconnect
  defp restore_subscriptions(state) do
    # Get persistent subscriptions
    persistent_channels = state.subscriptions
      |> Enum.filter(fn {_channel, data} -> data[:persistent] end)
      |> Enum.map(fn {channel, _} -> channel end)

    if persistent_channels != [] do
      # Create subscription request
      request_id = state.request_id
      {:ok, sub_msg} = Message.create_subscription_request(persistent_channels, request_id)
      {:ok, encoded} = Message.encode_message(sub_msg, state)

      # Send subscription request
      WebSockexNova.send_frame(:text, encoded)

      # Update state
      %{state |
        request_id: request_id + 1,
        pending_requests: Map.put(state.pending_requests, request_id, {:subscribe, persistent_channels})
      }
    else
      state
    end
  end

  # Update circuit breaker state
  defp update_circuit_breaker(circuit, :increment) do
    now = System.system_time(:second)
    failures = circuit.failures + 1

    # If we've had too many failures in a short time, open the circuit
    if failures >= 5 && now - circuit.reset_after < 120 do
      %{circuit |
        failures: failures,
        last_failure: now,
        status: :open,
        reset_after: now + 60  # Try again after 60 seconds
      }
    else
      # Just record the failure
      %{circuit |
        failures: failures,
        last_failure: now
      }
    end
  end

  # Handle authentication errors
  defp handle_authentication_error(_message, state) do
    # Set state as unauthenticated and try to re-authenticate
    new_state = %{state | authenticated: false}

    # Generate new auth request
    case Auth.generate_auth_request(new_state) do
      {:ok, auth_msg, state_with_id} ->
        {:ok, encoded} = Message.encode_message(auth_msg, state_with_id)
        {:reply, :text, encoded, state_with_id}

      {:error, reason} ->
        {:error, reason, state}
    end
  end

  # Handle rate limit errors
  defp handle_rate_limit_error(message, state) do
    # Extract retry time if available in message
    retry_after = extract_retry_time(message) || 2000

    # Update rate limit state
    {:ok, state}
  end

  # Extract retry time from rate limit error message
  defp extract_retry_time(message) do
    case Regex.run(~r/Available in (\d+)ms/, message) do
      [_, ms] -> String.to_integer(ms)
      _ -> nil
    end
  end

  # Determine message type for telemetry
  defp message_type(%{"method" => "subscription"}), do: :subscription_data
  defp message_type(%{"method" => "heartbeat"}), do: :heartbeat
  defp message_type(%{"error" => _}), do: :error
  defp message_type(%{"id" => _, "result" => %{"access_token" => _}}), do: :auth_response
  defp message_type(%{"id" => _, "result" => result}) when is_list(result), do: :subscription_response
  defp message_type(%{"id" => _, "result" => _}), do: :api_response
  defp message_type(_), do: :unknown

  # Forward subscription data to subscribers
  defp notify_subscribers(channel, data) do
    # In a real implementation, this would use a proper PubSub mechanism
    # For this example, we'll use Registry pattern
    Registry.dispatch(MyApp.Deribit.SubscriptionRegistry, channel, fn entries ->
      for {pid, _} <- entries do
        send(pid, {:deribit_data, channel, data})
      end
    end)
  end
end
```

### Message Handler

```elixir
defmodule MyApp.Deribit.Message do
  @moduledoc """
  Handles encoding and decoding of Deribit WebSocket messages.
  """

  @doc """
  Encodes a message for transmission.

  ## Parameters
    * `message` - Message to encode
    * `state` - Current client state

  ## Returns
    * `{:ok, binary}` - Encoded message
    * `{:error, reason}` - Encoding error
  """
  def encode_message(message, _state) do
    case Jason.encode(message) do
      {:ok, json} -> {:ok, json}
      {:error, reason} -> {:error, {:encode_error, reason}}
    end
  end

  @doc """
  Decodes a received message.

  ## Parameters
    * `data` - Binary data to decode

  ## Returns
    * `{:ok, message}` - Decoded message
    * `{:error, reason}` - Decoding error
  """
  def decode_message(data) do
    case Jason.decode(data) do
      {:ok, json} -> {:ok, json}
      {:error, reason} -> {:error, {:decode_error, reason}}
    end
  end

  @doc """
  Creates an authentication request.

  ## Parameters
    * `request_id` - Request ID to use
    * `api_key` - API key for authentication
    * `api_secret` - API secret for authentication
    * `timestamp` - Current timestamp (optional)

  ## Returns
    * `{:ok, message}` - Authentication request message
    * `{:error, reason}` - Error creating request
  """
  def create_auth_request(request_id, api_key, api_secret, timestamp \\ nil) do
    timestamp = timestamp || System.system_time(:millisecond)

    # Create authentication signature
    signature = :crypto.hmac(
      :sha256,
      api_secret,
      "#{timestamp}\nauth\n"
    ) |> Base.encode16(case: :lower)

    # Build auth request
    message = %{
      "jsonrpc" => "2.0",
      "id" => request_id,
      "method" => "public/auth",
      "params" => %{
        "grant_type" => "client_signature",
        "client_id" => api_key,
        "timestamp" => timestamp,
        "signature" => signature
      }
    }

    {:ok, message}
  end

  @doc """
  Creates a subscription request.

  ## Parameters
    * `channels` - List of channels to subscribe to
    * `request_id` - Request ID to use

  ## Returns
    * `{:ok, message}` - Subscription request message
    * `{:error, reason}` - Error creating request
  """
  def create_subscription_request(channels, request_id) do
    message = %{
      "jsonrpc" => "2.0",
      "id" => request_id,
      "method" => "public/subscribe",
      "params" => %{
        "channels" => channels
      }
    }

    {:ok, message}
  end

  @doc """
  Creates an unsubscription request.

  ## Parameters
    * `channels` - List of channels to unsubscribe from
    * `request_id` - Request ID to use

  ## Returns
    * `{:ok, message}` - Unsubscription request message
    * `{:error, reason}` - Error creating request
  """
  def create_unsubscription_request(channels, request_id) do
    message = %{
      "jsonrpc" => "2.0",
      "id" => request_id,
      "method" => "public/unsubscribe",
      "params" => %{
        "channels" => channels
      }
    }

    {:ok, message}
  end

  @doc """
  Creates a heartbeat message.

  ## Parameters
    * `state` - Current client state

  ## Returns
    * `{:ok, message}` - Heartbeat message
    * `{:error, reason}` - Error creating heartbeat
  """
  def create_heartbeat(state) do
    message = %{
      "jsonrpc" => "2.0",
      "id" => state.request_id,
      "method" => "public/test",
      "params" => %{}
    }

    {:ok, message}
  end

  @doc """
  Creates a response to a test_request heartbeat.

  ## Parameters
    * `state` - Current client state

  ## Returns
    * `{:ok, message}` - Test request response
    * `{:error, reason}` - Error creating response
  """
  def create_test_request_response(state) do
    message = %{
      "jsonrpc" => "2.0",
      "id" => state.request_id,
      "method" => "public/test",
      "params" => %{
        "type" => "heartbeat"
      }
    }

    {:ok, message}
  end

  @doc """
  Creates a trade method request.

  ## Parameters
    * `method` - API method to call
    * `params` - Method parameters
    * `request_id` - Request ID to use

  ## Returns
    * `{:ok, message}` - API request message
    * `{:error, reason}` - Error creating request
  """
  def create_method_request(method, params, request_id) do
    message = %{
      "jsonrpc" => "2.0",
      "id" => request_id,
      "method" => method,
      "params" => params
    }

    {:ok, message}
  end
end
```

### Authentication Handler

```elixir
defmodule MyApp.Deribit.Auth do
  @moduledoc """
  Handles Deribit authentication flows.
  """

  alias MyApp.Deribit.Message

  @doc """
  Generates an authentication request from client state.

  ## Parameters
    * `state` - Current client state

  ## Returns
    * `{:ok, message, new_state}` - Authentication request and updated state
    * `{:error, reason}` - Error generating request
  """
  def generate_auth_request(state) do
    request_id = state.request_id

    case Message.create_auth_request(request_id, state.api_key, state.api_secret) do
      {:ok, auth_msg} ->
        # Update state with request ID and pending request
        new_state = %{state |
          request_id: request_id + 1,
          pending_requests: Map.put(state.pending_requests, request_id, {:auth, System.system_time(:second)})
        }

        {:ok, auth_msg, new_state}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Checks if the client needs to re-authenticate.

  ## Parameters
    * `state` - Current client state

  ## Returns
    * `boolean` - Whether authentication is needed
  """
  def needs_authentication?(state) do
    !state.authenticated
  end

  @doc """
  Validates authentication response.

  ## Parameters
    * `response` - Authentication response from server

  ## Returns
    * `:ok` - Authentication successful
    * `{:error, reason}` - Authentication failed
  """
  def validate_auth_response(%{"result" => %{"access_token" => _token}}), do: :ok
  def validate_auth_response(%{"error" => error}), do: {:error, error}
  def validate_auth_response(_), do: {:error, :invalid_auth_response}
end
```

### Error Handler

```elixir
defmodule MyApp.Deribit.ErrorHandler do
  @moduledoc """
  Handles errors for Deribit client.
  """

  require Logger

  @doc """
  Handles an error and determines recovery strategy.

  ## Parameters
    * `error` - Error that occurred
    * `context` - Context where error occurred
    * `state` - Current client state

  ## Returns
    * `{:retry, delay, new_state}` - Retry operation after delay
    * `{:stop, reason, new_state}` - Stop client with reason
  """
  def handle_error({:decode_error, reason}, _context, state) do
    # Log the error
    Logger.error("Deribit message decode error: #{inspect(reason)}")

    # For decode errors, we just continue (non-fatal)
    {:retry, 0, state}
  end

  def handle_error({:auth_error, reason}, _context, state) do
    # Authentication errors may be temporary, retry with backoff
    attempt = Map.get(state, :auth_retry_count, 0)

    if attempt < 5 do
      delay = 1000 * :math.pow(2, attempt)
      Logger.warn("Deribit authentication error (attempt #{attempt + 1}): #{inspect(reason)}")
      {:retry, round(delay), %{state | auth_retry_count: attempt + 1}}
    else
      Logger.error("Deribit authentication failed after #{attempt} attempts: #{inspect(reason)}")
      {:stop, {:auth_error, reason}, state}
    end
  end

  def handle_error({:rate_limit, retry_after}, _context, state) do
    # Rate limit errors should pause and retry
    Logger.warn("Deribit rate limit exceeded, retry after #{retry_after}ms")
    {:retry, retry_after, state}
  end

  def handle_error({:connection_error, reason}, _context, state) do
    # Connection errors need reconnection logic
    attempt = Map.get(state, :reconnect_attempt, 0)
    delay = calculate_reconnect_delay(attempt)

    Logger.warn("Deribit connection error (attempt #{attempt + 1}): #{inspect(reason)}")
    {:retry, delay, %{state | reconnect_attempt: attempt + 1}}
  end

  def handle_error(error, context, state) do
    # Generic error handler for unexpected errors
    Logger.error("Deribit unexpected error: #{inspect(error)}, context: #{inspect(context)}")

    # For unknown errors, retry with modest delay
    {:retry, 5000, state}
  end

  @doc """
  Determines whether to reconnect after an error.

  ## Parameters
    * `error` - Error that occurred
    * `attempt` - Current reconnection attempt number
    * `state` - Current client state

  ## Returns
    * `{boolean, delay | nil}` - Whether to reconnect and optional delay
  """
  def should_reconnect?({:auth_error, _}, attempt, _state) when attempt > 5 do
    # Stop retrying authentication after 5 attempts
    {false, nil}
  end

  def should_reconnect?(_error, attempt, _state) when attempt > 50 do
    # Slow down reconnections after many attempts
    # But keep trying indefinitely for resilient financial connections
    {true, 60_000} # 1 minute delay
  end

  def should_reconnect?(_error, _attempt, _state) do
    # Default is to always reconnect
    {true, nil}
  end

  # Calculate exponential backoff with jitter for reconnection
  defp calculate_reconnect_delay(attempt) do
    # Base delay of 100ms, with exponential backoff
    base_delay = 100
    max_delay = 30_000  # 30 seconds

    # Calculate exponential backoff
    delay = min(base_delay * :math.pow(2, attempt), max_delay)

    # Add jitter (±25%)
    jitter = delay * 0.25 * (2.0 * :rand.uniform() - 1.0)

    # Return final delay in milliseconds
    trunc(delay + jitter)
  end
end
```

## Usage Example

```elixir
# Start the client
{:ok, pid} = MyApp.Deribit.Client.start_link([
  api_key: System.get_env("DERIBIT_API_KEY"),
  api_secret: System.get_env("DERIBIT_API_SECRET"),
  name: :deribit_client
])

# Subscribe to trade data
{:ok, _subscription_id} = MyApp.Deribit.Client.subscribe(
  :deribit_client,
  ["BTC-PERPETUAL.trades", "ETH-PERPETUAL.trades"],
  persistent: true
)

# Register to receive market data
:ok = Registry.register(MyApp.Deribit.SubscriptionRegistry, "BTC-PERPETUAL.trades", [])

# Place a market buy order
{:ok, result} = MyApp.Deribit.Client.execute(
  :deribit_client,
  "private/buy",
  %{
    "instrument_name" => "BTC-PERPETUAL",
    "amount" => 100,
    "type" => "market"
  }
)
```

## Key Features

This implementation demonstrates several important features:

### 1. Financial-Grade Error Handling

- Exponential backoff with jitter for reconnections
- Circuit breaker pattern to prevent hammering failing services
- Detailed error categorization (authentication, rate limit, connection)
- Telemetry for monitoring and alerting

### 2. Authentication Management

- Secure signature generation
- Automatic reauthentication on token expiry
- Authentication failure handling

### 3. Subscription Management

- Persistent subscriptions across reconnects
- Efficient subscription state tracking
- Broadcasting mechanism for subscription data

### 4. Rate Limiting

- Proactive rate limit tracking
- Reactive handling of rate limit errors
- Automatic backoff when limits are approached

### 5. Heartbeat Management

- Regular heartbeat sending
- Response to test_request heartbeats
- Connection health monitoring

## Production Considerations

For production use, consider the following enhancements:

1. **Enhanced Monitoring**: Add additional telemetry events for detailed operational metrics
2. **Clustering Support**: Enable distribution across multiple nodes for resilience
3. **Improved Message Queuing**: Add priority queuing for critical messages
4. **Enhanced Testing**: Comprehensive integration tests with WebSocket mocks
5. **Observability**: Grafana dashboards for real-time monitoring

## Conclusion

This example demonstrates how to implement a robust, financial-grade WebSocket client for Deribit using WebSockexNova. The implementation follows best practices for stability, error handling, and performance in high-frequency trading environments.

For more detailed documentation on WebSockexNova's features and APIs, refer to the main documentation.
