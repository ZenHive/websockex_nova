defmodule WebsockexNova.Platform.Example.Adapter do
  @moduledoc """
  Example adapter implementing all required WebsockexNova behaviour callbacks as pass-throughs to the default implementations.

  Each callback is documented to explain how to override or implement custom logic for your platform.
  Use this as a template for building robust, explicit adapters with minimal boilerplate.
  """

  use WebsockexNova.Adapter

  alias WebsockexNova.Behaviors.AuthHandler
  alias WebsockexNova.Behaviors.ConnectionHandler
  alias WebsockexNova.Behaviors.ErrorHandler
  alias WebsockexNova.Behaviors.LoggingHandler
  alias WebsockexNova.Behaviors.MessageHandler
  alias WebsockexNova.Behaviors.MetricsCollector
  alias WebsockexNova.Behaviors.RateLimitHandler
  alias WebsockexNova.Behaviors.SubscriptionHandler
  alias WebsockexNova.Defaults.DefaultAuthHandler
  alias WebsockexNova.Defaults.DefaultConnectionHandler
  alias WebsockexNova.Defaults.DefaultErrorHandler
  alias WebsockexNova.Defaults.DefaultLoggingHandler
  alias WebsockexNova.Defaults.DefaultMessageHandler
  alias WebsockexNova.Defaults.DefaultMetricsCollector
  alias WebsockexNova.Defaults.DefaultRateLimitHandler
  alias WebsockexNova.Defaults.DefaultSubscriptionHandler
  alias WebsockexNova.Platform.Adapter

  @default_host "example.com"
  @default_port 443
  @default_path "/ws"
  @default_capacity 60
  @default_refill_rate 1
  @default_refill_interval 1000
  @default_queue_limit 100
  @default_mode :normal
  @default_cost_map %{
    subscription: 5,
    auth: 10,
    query: 1
  }

  # --- ConnectionHandler ---

  @doc """
  Initializes the adapter's state. Sets defaults for connection and rate limiting.
  Override to add platform-specific state or configuration.
  """
  @impl WebsockexNova.Behaviors.ConnectionHandler
  def init(opts) do
    opts = Map.new(opts)

    state =
      opts
      |> Map.put_new(:host, @default_host)
      |> Map.put_new(:port, @default_port)
      |> Map.put_new(:path, @default_path)
      |> Map.put_new(:capacity, @default_capacity)
      |> Map.put_new(:refill_rate, @default_refill_rate)
      |> Map.put_new(:refill_interval, @default_refill_interval)
      |> Map.put_new(:queue_limit, @default_queue_limit)
      |> Map.put_new(:mode, @default_mode)
      |> Map.put_new(:cost_map, @default_cost_map)

    DefaultConnectionHandler.init(state)
  end

  @doc """
  Handles a successful connection. Override to send a handshake or perform setup.
  """
  @impl ConnectionHandler
  def handle_connect(conn_info, state), do: DefaultConnectionHandler.handle_connect(conn_info, state)

  @doc """
  Handles disconnection events. Override to implement custom reconnection or cleanup logic.
  """
  @impl ConnectionHandler
  def handle_disconnect(reason, state), do: DefaultConnectionHandler.handle_disconnect(reason, state)

  @doc """
  Handles incoming WebSocket frames. Override to process platform-specific frame types.
  """
  @impl ConnectionHandler
  def handle_frame(frame_type, frame_data, state),
    do: DefaultConnectionHandler.handle_frame(frame_type, frame_data, state)

  @doc """
  Handles connection timeouts. Override to customize timeout handling.
  """
  @impl ConnectionHandler
  def handle_timeout(state), do: DefaultConnectionHandler.handle_timeout(state)

  @doc """
  Handles ping requests. Override to implement custom keepalive logic.
  """
  @impl ConnectionHandler
  def ping(stream_ref, state), do: DefaultConnectionHandler.ping(stream_ref, state)

  @doc """
  Returns connection status. Override to provide platform-specific status info.
  """
  @impl ConnectionHandler
  def status(stream_ref, state), do: DefaultConnectionHandler.status(stream_ref, state)

  # --- MessageHandler ---

  @doc """
  Handles incoming messages. Override to implement platform-specific message routing or processing.
  """
  @impl MessageHandler
  def handle_message(message, state), do: DefaultMessageHandler.handle_message(message, state)

  @doc """
  Validates incoming messages. Override to enforce platform-specific message formats.
  """
  @impl MessageHandler
  def validate_message(message), do: DefaultMessageHandler.validate_message(message)

  @doc """
  Determines the type of a message. Override to extract custom message types.
  """
  @impl MessageHandler
  def message_type(message), do: DefaultMessageHandler.message_type(message)

  @doc """
  Encodes a message for sending. Override to customize outbound message encoding.
  """
  @impl MessageHandler
  def encode_message(message, state), do: DefaultMessageHandler.encode_message(message, state)

  # --- SubscriptionHandler ---

  @doc """
  Subscribes to a channel or topic. Override to implement platform-specific subscription logic.
  """
  @impl SubscriptionHandler
  def subscribe(channel, params, state), do: DefaultSubscriptionHandler.subscribe(channel, params, state)

  @doc """
  Unsubscribes from a channel or topic. Override to implement custom unsubscription logic.
  """
  @impl SubscriptionHandler
  def unsubscribe(sub_id, state), do: DefaultSubscriptionHandler.unsubscribe(sub_id, state)

  @doc """
  Handles subscription responses. Override to process platform-specific subscription events.
  """
  @impl SubscriptionHandler
  def handle_subscription_response(resp, state), do: DefaultSubscriptionHandler.handle_subscription_response(resp, state)

  @doc """
  Returns all active subscriptions. Override to customize subscription tracking.
  """
  @impl SubscriptionHandler
  def active_subscriptions(state), do: DefaultSubscriptionHandler.active_subscriptions(state)

  @doc """
  Finds a subscription by channel. Override to implement custom lookup logic.
  """
  @impl SubscriptionHandler
  def find_subscription_by_channel(channel, state),
    do: DefaultSubscriptionHandler.find_subscription_by_channel(channel, state)

  # --- AuthHandler ---

  @doc """
  Generates authentication data. Override to implement platform-specific authentication payloads.
  """
  @impl AuthHandler
  def generate_auth_data(state), do: DefaultAuthHandler.generate_auth_data(state)

  @doc """
  Handles authentication responses. Override to process custom auth events.
  """
  @impl AuthHandler
  def handle_auth_response(resp, state), do: DefaultAuthHandler.handle_auth_response(resp, state)

  @doc """
  Determines if reauthentication is needed. Override to implement custom token refresh logic.
  """
  @impl AuthHandler
  def needs_reauthentication?(state), do: DefaultAuthHandler.needs_reauthentication?(state)

  @doc """
  Authenticates using credentials. Override to implement custom authentication flows.
  """
  @impl AuthHandler
  def authenticate(stream_ref, credentials, state), do: DefaultAuthHandler.authenticate(stream_ref, credentials, state)

  # --- ErrorHandler ---

  @doc """
  Handles errors. Override to implement custom error handling or logging.
  """
  @impl ErrorHandler
  def handle_error(error, context, state), do: DefaultErrorHandler.handle_error(error, context, state)

  @doc """
  Determines if the connection should reconnect after an error. Override for custom reconnection strategies.
  """
  @impl ErrorHandler
  def should_reconnect?(error, attempt, state), do: DefaultErrorHandler.should_reconnect?(error, attempt, state)

  @doc """
  Logs errors. Override to customize error logging.
  """
  @impl ErrorHandler
  def log_error(error, context, state), do: DefaultErrorHandler.log_error(error, context, state)

  # --- RateLimitHandler ---

  @doc """
  Checks if a request can proceed based on rate limits. Override for custom rate limiting logic.
  """
  @impl RateLimitHandler
  def check_rate_limit(request, state), do: DefaultRateLimitHandler.check_rate_limit(request, state)

  @doc """
  Handles periodic rate limit ticks. Override to process queued requests or refill tokens.
  """
  @impl RateLimitHandler
  def handle_tick(state), do: DefaultRateLimitHandler.handle_tick(state)

  # --- LoggingHandler ---

  @doc """
  Logs connection events. Override to customize connection event logging.
  """
  @impl LoggingHandler
  def log_connection_event(event, context, state), do: DefaultLoggingHandler.log_connection_event(event, context, state)

  @doc """
  Logs message events. Override to customize message event logging.
  """
  @impl LoggingHandler
  def log_message_event(event, context, state), do: DefaultLoggingHandler.log_message_event(event, context, state)

  @doc """
  Logs error events. Override to customize error event logging.
  """
  @impl LoggingHandler
  def log_error_event(event, context, state), do: DefaultLoggingHandler.log_error_event(event, context, state)

  # --- MetricsCollector ---

  @doc """
  Handles connection metrics events. Override to collect custom metrics.
  """
  @impl MetricsCollector
  def handle_connection_event(event, measurements, metadata),
    do: DefaultMetricsCollector.handle_connection_event(event, measurements, metadata)

  @doc """
  Handles message metrics events. Override to collect custom message metrics.
  """
  @impl MetricsCollector
  def handle_message_event(event, measurements, metadata),
    do: DefaultMetricsCollector.handle_message_event(event, measurements, metadata)

  @doc """
  Handles error metrics events. Override to collect custom error metrics.
  """
  @impl MetricsCollector
  def handle_error_event(event, measurements, metadata),
    do: DefaultMetricsCollector.handle_error_event(event, measurements, metadata)

  # --- Platform Adapter ---

  @doc """
  Handles platform-specific messages. Override to implement custom message routing or transformation.
  """
  @impl Adapter
  def handle_platform_message(_message, state), do: {:ok, state}

  @doc """
  Encodes an authentication request. Override to implement platform-specific auth requests.
  """
  @impl Adapter
  def encode_auth_request(_credentials), do: {:text, ""}

  @doc """
  Encodes a subscription request. Override to implement platform-specific subscription requests.
  """
  @impl Adapter
  def encode_subscription_request(_channel, _params), do: {:text, ""}

  @doc """
  Encodes an unsubscription request. Override to implement platform-specific unsubscription requests.
  """
  @impl Adapter
  def encode_unsubscription_request(_channel), do: {:text, ""}
end
