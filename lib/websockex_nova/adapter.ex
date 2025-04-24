defmodule WebsockexNova.Adapter do
  @moduledoc """
  Macro for building WebsockexNova adapters with minimal boilerplate.

  Usage:

      defmodule MyApp.MyAdapter do
        use WebsockexNova.Adapter

        # Override only what you need:
        @impl WebsockexNova.Behaviors.MessageHandler
        def handle_message(message, state), do: ...
      end

  This macro:
  - Declares all core @behaviour attributes
  - Injects default implementations for missing callbacks, delegating to WebsockexNova.Defaults.*
  - Lets you override any callback as needed
  """

  defmacro __using__(_opts) do
    quote do
      # Behaviours
      @behaviour WebsockexNova.Behaviors.ConnectionHandler
      @behaviour WebsockexNova.Behaviors.MessageHandler
      @behaviour WebsockexNova.Behaviors.SubscriptionHandler
      @behaviour WebsockexNova.Behaviors.AuthHandler
      @behaviour WebsockexNova.Behaviors.ErrorHandler

      # --- ConnectionHandler defaults ---
      @impl WebsockexNova.Behaviors.ConnectionHandler
      def init(opts), do: WebsockexNova.Defaults.DefaultConnectionHandler.init(opts)
      @impl WebsockexNova.Behaviors.ConnectionHandler
      def connection_info(opts), do: WebsockexNova.Defaults.DefaultConnectionHandler.connection_info(opts)
      @impl WebsockexNova.Behaviors.ConnectionHandler
      def handle_connect(conn_info, state),
        do: WebsockexNova.Defaults.DefaultConnectionHandler.handle_connect(conn_info, state)

      @impl WebsockexNova.Behaviors.ConnectionHandler
      def handle_disconnect(reason, state),
        do: WebsockexNova.Defaults.DefaultConnectionHandler.handle_disconnect(reason, state)

      @impl WebsockexNova.Behaviors.ConnectionHandler
      def handle_frame(type, data, state),
        do: WebsockexNova.Defaults.DefaultConnectionHandler.handle_frame(type, data, state)

      @impl WebsockexNova.Behaviors.ConnectionHandler
      def handle_timeout(state), do: WebsockexNova.Defaults.DefaultConnectionHandler.handle_timeout(state)
      @impl WebsockexNova.Behaviors.ConnectionHandler
      def ping(stream_ref, state), do: WebsockexNova.Defaults.DefaultConnectionHandler.ping(stream_ref, state)
      @impl WebsockexNova.Behaviors.ConnectionHandler
      def status(stream_ref, state), do: WebsockexNova.Defaults.DefaultConnectionHandler.status(stream_ref, state)

      # --- MessageHandler defaults ---
      @impl WebsockexNova.Behaviors.MessageHandler
      def message_init(opts), do: WebsockexNova.Defaults.DefaultMessageHandler.message_init(opts)
      @impl WebsockexNova.Behaviors.MessageHandler
      def handle_message(message, state), do: WebsockexNova.Defaults.DefaultMessageHandler.handle_message(message, state)
      @impl WebsockexNova.Behaviors.MessageHandler
      def validate_message(message), do: WebsockexNova.Defaults.DefaultMessageHandler.validate_message(message)
      @impl WebsockexNova.Behaviors.MessageHandler
      def message_type(message), do: WebsockexNova.Defaults.DefaultMessageHandler.message_type(message)
      @impl WebsockexNova.Behaviors.MessageHandler
      def encode_message(message, state), do: WebsockexNova.Defaults.DefaultMessageHandler.encode_message(message, state)

      # --- SubscriptionHandler defaults ---
      @impl WebsockexNova.Behaviors.SubscriptionHandler
      def subscription_init(opts), do: WebsockexNova.Defaults.DefaultSubscriptionHandler.subscription_init(opts)
      @impl WebsockexNova.Behaviors.SubscriptionHandler
      def subscribe(channel, params, state),
        do: WebsockexNova.Defaults.DefaultSubscriptionHandler.subscribe(channel, params, state)

      @impl WebsockexNova.Behaviors.SubscriptionHandler
      def unsubscribe(channel, state), do: WebsockexNova.Defaults.DefaultSubscriptionHandler.unsubscribe(channel, state)
      @impl WebsockexNova.Behaviors.SubscriptionHandler
      def handle_subscription_response(response, state),
        do: WebsockexNova.Defaults.DefaultSubscriptionHandler.handle_subscription_response(response, state)

      @impl WebsockexNova.Behaviors.SubscriptionHandler
      def active_subscriptions(state), do: WebsockexNova.Defaults.DefaultSubscriptionHandler.active_subscriptions(state)
      @impl WebsockexNova.Behaviors.SubscriptionHandler
      def find_subscription_by_channel(channel, state),
        do: WebsockexNova.Defaults.DefaultSubscriptionHandler.find_subscription_by_channel(channel, state)

      # --- AuthHandler defaults ---
      @impl WebsockexNova.Behaviors.AuthHandler
      def generate_auth_data(state), do: WebsockexNova.Defaults.DefaultAuthHandler.generate_auth_data(state)
      @impl WebsockexNova.Behaviors.AuthHandler
      def handle_auth_response(response, state),
        do: WebsockexNova.Defaults.DefaultAuthHandler.handle_auth_response(response, state)

      @impl WebsockexNova.Behaviors.AuthHandler
      def needs_reauthentication?(state), do: WebsockexNova.Defaults.DefaultAuthHandler.needs_reauthentication?(state)
      @impl WebsockexNova.Behaviors.AuthHandler
      def authenticate(stream_ref, credentials, state),
        do: WebsockexNova.Defaults.DefaultAuthHandler.authenticate(stream_ref, credentials, state)

      # --- ErrorHandler defaults ---
      @impl WebsockexNova.Behaviors.ErrorHandler
      def handle_error(error, context, state),
        do: WebsockexNova.Defaults.DefaultErrorHandler.handle_error(error, context, state)

      @impl WebsockexNova.Behaviors.ErrorHandler
      def should_reconnect?(error, attempt, state),
        do: WebsockexNova.Defaults.DefaultErrorHandler.should_reconnect?(error, attempt, state)

      @impl WebsockexNova.Behaviors.ErrorHandler
      def log_error(error, context, state),
        do: WebsockexNova.Defaults.DefaultErrorHandler.log_error(error, context, state)

      @impl WebsockexNova.Behaviors.ErrorHandler
      def classify_error(error, state), do: WebsockexNova.Defaults.DefaultErrorHandler.classify_error(error, state)

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
