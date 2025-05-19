defmodule WebsockexNova.Adapter do
  @moduledoc """
  Macro for building WebsockexNova adapters with minimal boilerplate.

  This macro provides a convenient way to create platform-specific WebSocket adapters
  by automatically implementing all required behaviors with sensible defaults. You only
  need to override the specific behaviors needed for your use case.

  ## Basic Usage

      defmodule MyApp.MyAdapter do
        use WebsockexNova.Adapter

        # Override only what you need:
        @impl WebsockexNova.Behaviors.MessageHandler
        def handle_message(message, state) do
          # Custom message handling
          {:ok, decoded_message, state}
        end
      end

  ## What this macro does

  - Declares all core `@behaviour` attributes (AuthHandler, ConnectionHandler, etc.)
  - Injects default implementations for all callbacks, delegating to `WebsockexNova.Defaults.*`
  - Allows you to override any callback by implementing it in your module
  - Imports necessary aliases for convenient access to behaviors and defaults

  ## Examples

  ### Simple adapter with custom connection info

      defmodule MyApp.EchoAdapter do
        use WebsockexNova.Adapter

        @impl WebsockexNova.Behaviors.ConnectionHandler
        def connection_info(opts) do
          {:ok, Map.merge(%{
            host: "echo.websocket.org",
            port: 443,
            path: "/",
            transport: :tls
          }, opts)}
        end
      end

  ### Financial trading adapter with authentication

      defmodule MyApp.TradingAdapter do
        use WebsockexNova.Adapter

        @impl WebsockexNova.Behaviors.ConnectionHandler
        def connection_info(opts) do
          {:ok, Map.merge(%{
            host: "api.exchange.com",
            port: 443,
            path: "/ws/v2",
            transport: :tls
          }, opts)}
        end

        @impl WebsockexNova.Behaviors.AuthHandler
        def authenticate(conn, auth_config, state) do
          # Send authentication message
          auth_msg = %{
            method: "auth",
            params: %{
              api_key: auth_config.api_key,
              api_secret: auth_config.api_secret
            }
          }
          WebsockexNova.Client.send_message(conn, auth_msg)
          {:ok, state}
        end

        @impl WebsockexNova.Behaviors.MessageHandler
        def handle_message(%{"method" => "auth", "result" => true}, state) do
          # Authentication successful
          {:ok, %{authenticated: true}, Map.put(state, :authenticated, true)}
        end
        def handle_message(message, state) do
          # Decode JSON messages
          with {:ok, decoded} <- Jason.decode(message) do
            {:ok, decoded, state}
          else
            _ -> {:error, :invalid_json, state}
          end
        end
      end

  ### Gaming adapter with custom subscription handling

      defmodule MyApp.GameAdapter do
        use WebsockexNova.Adapter
        alias WebsockexNova.Message.SubscriptionManager

        @impl WebsockexNova.Behaviors.SubscriptionHandler
        def handle_subscription(channel, opts, conn, state) do
          # Custom subscription format for game events
          subscribe_msg = %{
            action: "subscribe",
            channel: channel,
            params: opts || %{}
          }
          
          case WebsockexNova.Client.send_message(conn, subscribe_msg) do
            {:ok, _} ->
              manager = Map.get(state, :subscription_manager, SubscriptionManager.new())
              updated_manager = SubscriptionManager.add_subscription(manager, channel, opts)
              {:ok, %{}, Map.put(state, :subscription_manager, updated_manager)}
            error ->
              error
          end
        end

        @impl WebsockexNova.Behaviors.MessageHandler
        def handle_message(%{"type" => "game_event"} = message, state) do
          # Handle game-specific events
          {:ok, message, state}
        end
        def handle_message(message, state) do
          DefaultMessageHandler.handle_message(message, state)
        end
      end

  ## Available Behaviors

  The macro automatically implements these behaviors with default implementations:

  - `WebsockexNova.Behaviors.AuthHandler` - Authentication flow
  - `WebsockexNova.Behaviors.ConnectionHandler` - Connection lifecycle
  - `WebsockexNova.Behaviors.ErrorHandler` - Error handling strategies
  - `WebsockexNova.Behaviors.MessageHandler` - Message processing
  - `WebsockexNova.Behaviors.SubscriptionHandler` - Channel subscriptions

  Note: LoggingHandler, MetricsCollector, and RateLimitHandler are not included by default
  since they're typically configured at the client level rather than the adapter level.

  ## Tips

  1. Only override the behaviors you need to customize
  2. Call the default implementations when you want to extend rather than replace behavior
  3. Use pattern matching in message handlers for efficient message routing
  4. Store adapter-specific state in the adapter_state field of the connection

  See the `WebsockexNova.Examples.AdapterDeribit` module for a complete real-world example.
  """

  defmacro __using__(_opts) do
    quote do
      @behaviour WebsockexNova.Behaviors.AuthHandler
      # Behaviours
      @behaviour WebsockexNova.Behaviors.ConnectionHandler
      @behaviour WebsockexNova.Behaviors.ErrorHandler
      @behaviour WebsockexNova.Behaviors.MessageHandler
      @behaviour WebsockexNova.Behaviors.SubscriptionHandler

      alias WebsockexNova.Behaviors.AuthHandler
      alias WebsockexNova.Behaviors.ConnectionHandler
      alias WebsockexNova.Behaviors.ErrorHandler
      alias WebsockexNova.Behaviors.MessageHandler
      alias WebsockexNova.Behaviors.SubscriptionHandler
      alias WebsockexNova.Defaults.DefaultAuthHandler
      alias WebsockexNova.Defaults.DefaultConnectionHandler
      alias WebsockexNova.Defaults.DefaultErrorHandler
      alias WebsockexNova.Defaults.DefaultMessageHandler
      alias WebsockexNova.Defaults.DefaultSubscriptionHandler

      # --- ConnectionHandler defaults ---
      @impl ConnectionHandler
      def init(opts), do: DefaultConnectionHandler.init(opts)
      @impl ConnectionHandler
      def connection_info(opts), do: DefaultConnectionHandler.connection_info(opts)
      @impl ConnectionHandler
      def handle_connect(conn_info, state), do: DefaultConnectionHandler.handle_connect(conn_info, state)

      @impl ConnectionHandler
      def handle_disconnect(reason, state), do: DefaultConnectionHandler.handle_disconnect(reason, state)

      @impl ConnectionHandler
      def handle_frame(type, data, state), do: DefaultConnectionHandler.handle_frame(type, data, state)

      @impl ConnectionHandler
      def handle_timeout(state), do: DefaultConnectionHandler.handle_timeout(state)
      @impl ConnectionHandler
      def ping(stream_ref, state), do: DefaultConnectionHandler.ping(stream_ref, state)
      @impl ConnectionHandler
      def status(stream_ref, state), do: DefaultConnectionHandler.status(stream_ref, state)

      # --- MessageHandler defaults ---
      @impl MessageHandler
      def message_init(opts), do: DefaultMessageHandler.message_init(opts)
      @impl MessageHandler
      def handle_message(message, state), do: DefaultMessageHandler.handle_message(message, state)
      @impl MessageHandler
      def validate_message(message), do: DefaultMessageHandler.validate_message(message)
      @impl MessageHandler
      def message_type(message), do: DefaultMessageHandler.message_type(message)
      @impl MessageHandler
      def encode_message(message, state), do: DefaultMessageHandler.encode_message(message, state)

      # --- SubscriptionHandler defaults ---
      @impl SubscriptionHandler
      def subscription_init(opts), do: DefaultSubscriptionHandler.subscription_init(opts)
      @impl SubscriptionHandler
      def subscribe(channel, params, state), do: DefaultSubscriptionHandler.subscribe(channel, params, state)

      @impl SubscriptionHandler
      def unsubscribe(channel, state), do: DefaultSubscriptionHandler.unsubscribe(channel, state)
      @impl SubscriptionHandler
      def handle_subscription_response(response, state),
        do: DefaultSubscriptionHandler.handle_subscription_response(response, state)

      @impl SubscriptionHandler
      def active_subscriptions(state), do: DefaultSubscriptionHandler.active_subscriptions(state)
      @impl SubscriptionHandler
      def find_subscription_by_channel(channel, state),
        do: DefaultSubscriptionHandler.find_subscription_by_channel(channel, state)

      # --- AuthHandler defaults ---
      @impl AuthHandler
      def generate_auth_data(state), do: DefaultAuthHandler.generate_auth_data(state)
      @impl AuthHandler
      def handle_auth_response(response, state), do: DefaultAuthHandler.handle_auth_response(response, state)

      @impl AuthHandler
      def needs_reauthentication?(state), do: DefaultAuthHandler.needs_reauthentication?(state)
      @impl AuthHandler
      def authenticate(stream_ref, credentials, state),
        do: DefaultAuthHandler.authenticate(stream_ref, credentials, state)

      # --- ErrorHandler defaults ---
      @impl ErrorHandler
      def handle_error(error, context, state), do: DefaultErrorHandler.handle_error(error, context, state)

      @impl ErrorHandler
      def should_reconnect?(error, attempt, state), do: DefaultErrorHandler.should_reconnect?(error, attempt, state)

      @impl ErrorHandler
      def log_error(error, context, state), do: DefaultErrorHandler.log_error(error, context, state)

      @impl ErrorHandler
      def classify_error(error, state), do: DefaultErrorHandler.classify_error(error, state)

      # Allow adapter authors to override any callback
      defoverridable init: 1,
                     # ConnectionHandler
                     connection_info: 1,
                     handle_connect: 2,
                     handle_disconnect: 2,
                     handle_frame: 3,
                     handle_timeout: 1,
                     ping: 2,
                     status: 2,
                     # MessageHandler
                     message_init: 1,
                     handle_message: 2,
                     validate_message: 1,
                     message_type: 1,
                     encode_message: 2,
                     # SubscriptionHandler
                     subscription_init: 1,
                     subscribe: 3,
                     unsubscribe: 2,
                     handle_subscription_response: 2,
                     active_subscriptions: 1,
                     find_subscription_by_channel: 2,
                     # AuthHandler
                     generate_auth_data: 1,
                     handle_auth_response: 2,
                     needs_reauthentication?: 1,
                     authenticate: 3,
                     # ErrorHandler
                     handle_error: 3,
                     should_reconnect?: 3,
                     log_error: 3,
                     classify_error: 2
    end
  end
end
