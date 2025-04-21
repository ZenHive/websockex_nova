defmodule WebsockexNova.Platform.Deribit.Adapter do
  @moduledoc """
  WebsockexNova adapter for the Deribit exchange (testnet).

  Demonstrates how to use the `WebsockexNova.Adapter` macro and delegate to default behaviors.
  Only Deribit-specific logic is implemented; all other events use robust defaults.

  ## Quick Start

      # Start a connection to Deribit testnet using all defaults
      {:ok, conn} = WebsockexNova.Connection.start_link(adapter: WebsockexNova.Platform.Deribit.Adapter)

      # Send a JSON-RPC message (echoed back by default handler)
      WebsockexNova.Client.send_json(conn, %{jsonrpc: "2.0", method: "public/ping", params: %{}})

      # Subscribe to a channel (uses default subscription handler)
      WebsockexNova.Client.subscribe(conn, "ticker.BTC-PERPETUAL.raw", %{})

  ## Customizing Handlers

  You can override any handler by passing it to `start_link/1`:

      {:ok, conn} = WebsockexNova.Connection.start_link(
        adapter: WebsockexNova.Platform.Deribit.Adapter,
        message_handler: MyApp.CustomMessageHandler,
        error_handler: MyApp.CustomErrorHandler
      )

  ## Advanced: Custom Platform Logic

  To implement Deribit-specific message routing, override `handle_platform_message/2`:

      def handle_platform_message(message, state) do
        # Custom logic here
        ...
      end

  ## Default Configuration

      adapter: WebsockexNova.Platform.Deribit.Adapter
      host: "test.deribit.com"
      port: 443
      path: "/ws/api/v2"

  See integration tests for real-world usage examples.
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

  require Logger

  @default_host "test.deribit.com"
  @default_port 443
  @default_path "/ws/api/v2"
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
  Initializes the adapter's state with Deribit and rate limit defaults.
  """
  @impl ConnectionHandler
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
  Handles a successful connection. Uses the default handler.
  """
  @impl ConnectionHandler
  def handle_connect(conn_info, state), do: DefaultConnectionHandler.handle_connect(conn_info, state)

  @doc """
  Handles incoming WebSocket frames. Uses the default handler.
  """
  @impl ConnectionHandler
  def handle_frame(frame_type, frame_data, state),
    do: DefaultConnectionHandler.handle_frame(frame_type, frame_data, state)

  @doc """
  Handles connection timeouts. Uses the default handler.
  """
  @impl ConnectionHandler
  def handle_timeout(state), do: DefaultConnectionHandler.handle_timeout(state)

  @doc """
  Handles ping requests. Uses the default handler.
  """
  @impl ConnectionHandler
  def ping(stream_ref, state), do: DefaultConnectionHandler.ping(stream_ref, state)

  @doc """
  Returns connection status. Uses the default handler.
  """
  @impl ConnectionHandler
  def status(stream_ref, state), do: DefaultConnectionHandler.status(stream_ref, state)

  @doc """
  Handles disconnection events. Uses the default handler.
  """
  @impl ConnectionHandler
  def handle_disconnect(reason, state), do: DefaultConnectionHandler.handle_disconnect(reason, state)

  @doc """
  Handles incoming messages. Uses the default handler.
  """
  @impl MessageHandler
  def handle_message(message, state), do: DefaultMessageHandler.handle_message(message, state)

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
  Deribit-specific message routing. Passes the raw message to the default message handler.
  """
  @impl Adapter
  def handle_platform_message(message, state) do
    DefaultMessageHandler.handle_message(message, state)
  end

  @doc """
  Deribit adapter does not support authentication requests via this callback.
  """
  @impl Adapter
  def encode_auth_request(_credentials), do: {:text, ""}

  @doc """
  Deribit adapter does not support subscription requests via this callback.
  """
  @impl Adapter
  def encode_subscription_request(_channel, _params), do: {:text, ""}

  @doc """
  Deribit adapter does not support unsubscription requests via this callback.
  """
  @impl Adapter
  def encode_unsubscription_request(_channel), do: {:text, ""}
end
