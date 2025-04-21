defmodule WebsockexNova.Platform.EchoAdapter do
  @moduledoc """
  Minimal echo adapter using the WebsockexNova.Adapter macro.
  Echoes back any text or JSON message sent to it. Intended as a template for new adapters.
  All other callbacks delegate to the default handler modules.
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

  @default_host "echo.websocket.org"
  @default_port 443
  @default_path "/"
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
  @doc """
  Handles platform-specific messages. For echo, delegates to handle_message/2.
  """
  @impl Adapter
  def handle_platform_message(message, state) do
    handle_message({:text, message}, state)
  end

  @doc """
  Initializes the adapter's state with echo defaults.
  """
  @impl ConnectionHandler
  def connection_init(opts) do
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

    DefaultConnectionHandler.connection_init(state)
  end

  @doc """
  Handles a successful connection. Uses the default handler.
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
  Echoes back any text or JSON message sent to it.
  """
  @impl MessageHandler
  def handle_message(message, state) when is_binary(message) or is_map(message) do
    handle_message({:text, message}, state)
  end

  def handle_message({:text, message}, state) when is_binary(message), do: {:reply, {:text, message}, state}
  def handle_message({:text, message}, state) when is_map(message), do: {:reply, {:text, Jason.encode!(message)}, state}
  def handle_message({:text, message}, state), do: {:reply, {:text, to_string(message)}, state}

  @doc """
  Validates incoming messages. Uses the default handler.
  """
  @impl MessageHandler
  def validate_message(message), do: DefaultMessageHandler.validate_message(message)

  @doc """
  Determines the type of a message. Uses the default handler.
  """
  @impl MessageHandler
  def message_type(message), do: DefaultMessageHandler.message_type(message)

  @doc """
  Encodes a message for sending. Uses the default handler.
  """
  @impl MessageHandler
  def encode_message(message, state), do: DefaultMessageHandler.encode_message(message, state)

  @doc """
  Subscribes to a channel or topic. Uses the default handler.
  """
  @impl SubscriptionHandler
  def subscribe(channel, params, state), do: DefaultSubscriptionHandler.subscribe(channel, params, state)

  @doc """
  Unsubscribes from a channel or topic. Uses the default handler.
  """
  @impl SubscriptionHandler
  def unsubscribe(sub_id, state), do: DefaultSubscriptionHandler.unsubscribe(sub_id, state)

  @doc """
  Handles subscription responses. Uses the default handler.
  """
  @impl SubscriptionHandler
  def handle_subscription_response(resp, state), do: DefaultSubscriptionHandler.handle_subscription_response(resp, state)

  @doc """
  Returns all active subscriptions. Uses the default handler.
  """
  @impl SubscriptionHandler
  def active_subscriptions(state), do: DefaultSubscriptionHandler.active_subscriptions(state)

  @doc """
  Finds a subscription by channel. Uses the default handler.
  """
  @impl SubscriptionHandler
  def find_subscription_by_channel(channel, state),
    do: DefaultSubscriptionHandler.find_subscription_by_channel(channel, state)

  @doc """
  Generates authentication data. Uses the default handler.
  """
  @impl AuthHandler
  def generate_auth_data(state), do: DefaultAuthHandler.generate_auth_data(state)

  @doc """
  Handles authentication responses. Uses the default handler.
  """
  @impl AuthHandler
  def handle_auth_response(resp, state), do: DefaultAuthHandler.handle_auth_response(resp, state)

  @doc """
  Determines if reauthentication is needed. Uses the default handler.
  """
  @impl AuthHandler
  def needs_reauthentication?(state), do: DefaultAuthHandler.needs_reauthentication?(state)

  @doc """
  Authenticates using credentials. Uses the default handler.
  """
  @impl AuthHandler
  def authenticate(stream_ref, credentials, state), do: DefaultAuthHandler.authenticate(stream_ref, credentials, state)

  @doc """
  Handles errors. Uses the default handler.
  """
  @impl ErrorHandler
  def handle_error(error, context, state), do: DefaultErrorHandler.handle_error(error, context, state)

  @doc """
  Determines if the connection should reconnect after an error. Uses the default handler.
  """
  @impl ErrorHandler
  def should_reconnect?(error, attempt, state), do: DefaultErrorHandler.should_reconnect?(error, attempt, state)

  @doc """
  Logs errors. Uses the default handler.
  """
  @impl ErrorHandler
  def log_error(error, context, state), do: DefaultErrorHandler.log_error(error, context, state)

  @doc """
  Checks if a request can proceed based on rate limits. Uses the default handler.
  """
  @impl RateLimitHandler
  def check_rate_limit(request, state), do: DefaultRateLimitHandler.check_rate_limit(request, state)

  @doc """
  Handles periodic rate limit ticks. Uses the default handler.
  """
  @impl RateLimitHandler
  def handle_tick(state), do: DefaultRateLimitHandler.handle_tick(state)

  @doc """
  Logs connection events. Uses the default handler.
  """
  @impl LoggingHandler
  def log_connection_event(event, context, state), do: DefaultLoggingHandler.log_connection_event(event, context, state)

  @doc """
  Logs message events. Uses the default handler.
  """
  @impl LoggingHandler
  def log_message_event(event, context, state), do: DefaultLoggingHandler.log_message_event(event, context, state)

  @doc """
  Logs error events. Uses the default handler.
  """
  @impl LoggingHandler
  def log_error_event(event, context, state), do: DefaultLoggingHandler.log_error_event(event, context, state)

  @doc """
  Handles connection metrics events. Uses the default handler.
  """
  @impl MetricsCollector
  def handle_connection_event(event, measurements, metadata),
    do: DefaultMetricsCollector.handle_connection_event(event, measurements, metadata)

  @doc """
  Handles message metrics events. Uses the default handler.
  """
  @impl MetricsCollector
  def handle_message_event(event, measurements, metadata),
    do: DefaultMetricsCollector.handle_message_event(event, measurements, metadata)

  @doc """
  Handles error metrics events. Uses the default handler.
  """
  @impl MetricsCollector
  def handle_error_event(event, measurements, metadata),
    do: DefaultMetricsCollector.handle_error_event(event, measurements, metadata)

  @doc """
  Encodes an authentication request. For echo, returns an empty text frame.
  """
  @impl Adapter
  def encode_auth_request(_credentials), do: {:text, ""}

  @doc """
  Encodes a subscription request. For echo, returns an empty text frame.
  """
  @impl Adapter
  def encode_subscription_request(_channel, _params), do: {:text, ""}

  @doc """
  Encodes an unsubscription request. For echo, returns an empty text frame.
  """
  @impl Adapter
  def encode_unsubscription_request(_channel), do: {:text, ""}

  @impl MessageHandler
  def message_init(opts), do: DefaultMessageHandler.message_init(opts)

  @impl ErrorHandler
  def error_init(opts), do: DefaultErrorHandler.error_init(opts)

  @impl RateLimitHandler
  def rate_limit_init(opts), do: DefaultRateLimitHandler.rate_limit_init(opts)

  @impl SubscriptionHandler
  def subscription_init(opts), do: DefaultSubscriptionHandler.subscription_init(opts)
end
