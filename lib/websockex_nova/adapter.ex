defmodule WebsockexNova.Adapter do
  @moduledoc """
  Macro that implements WebsockexNova behaviours.

  Usage:
  ```elixir
  defmodule MyApp.MyAdapter do
    use WebsockexNova.Adapter

    # Override only what you need:
    @impl WebsockexNova.Behaviours.MessageHandler
    def handle_message(message, state), do: ...
  end
  ```

  This macro:
  - Declares all core @behaviour attributes
  - Injects default implementations for missing callbacks, delegating to WebsockexNova.Defaults.*
  - Lets you override any callback as needed
  """

  defmacro __using__(_opts) do
    quote do
      # Behaviours
      @behaviour WebsockexNova.Behaviours.AuthHandler
      @behaviour WebsockexNova.Behaviours.ConnectionHandler
      @behaviour WebsockexNova.Behaviours.ErrorHandler
      @behaviour WebsockexNova.Behaviours.MessageHandler
      @behaviour WebsockexNova.Behaviours.SubscriptionHandler

      alias WebsockexNova.Behaviours.AuthHandler
      alias WebsockexNova.Behaviours.ConnectionHandler
      alias WebsockexNova.Behaviours.ErrorHandler
      alias WebsockexNova.Behaviours.MessageHandler
      alias WebsockexNova.Behaviours.SubscriptionHandler
      alias WebsockexNova.Defaults.DefaultAuthHandler
      alias WebsockexNova.Defaults.DefaultConnectionHandler
      alias WebsockexNova.Defaults.DefaultErrorHandler
      alias WebsockexNova.Defaults.DefaultMessageHandler
      alias WebsockexNova.Defaults.DefaultSubscriptionHandler

      # --- ConnectionHandler defaults ---
      @impl ConnectionHandler
      def init(opts),
        do: DefaultConnectionHandler.init(opts)

      @impl ConnectionHandler
      def connection_info(opts),
        do: DefaultConnectionHandler.connection_info(opts)

      @impl ConnectionHandler
      def handle_connect(conn_info, state),
        do: DefaultConnectionHandler.handle_connect(conn_info, state)

      @impl ConnectionHandler
      def handle_disconnect(reason, state),
        do: DefaultConnectionHandler.handle_disconnect(reason, state)

      @impl ConnectionHandler
      def handle_frame(type, data, state),
        do: DefaultConnectionHandler.handle_frame(type, data, state)

      @impl ConnectionHandler
      def handle_timeout(state),
        do: DefaultConnectionHandler.handle_timeout(state)

      @impl ConnectionHandler
      def ping(stream_ref, state),
        do: DefaultConnectionHandler.ping(stream_ref, state)

      @impl ConnectionHandler
      def status(stream_ref, state),
        do: DefaultConnectionHandler.status(stream_ref, state)

      # --- MessageHandler defaults ---
      @impl MessageHandler
      def message_init(opts),
        do: DefaultMessageHandler.message_init(opts)

      @impl MessageHandler
      def handle_message(message, state),
        do: DefaultMessageHandler.handle_message(message, state)

      @impl MessageHandler
      def validate_message(message),
        do: DefaultMessageHandler.validate_message(message)

      @impl MessageHandler
      def message_type(message),
        do: DefaultMessageHandler.message_type(message)

      @impl MessageHandler
      def encode_message(message, state),
        do: DefaultMessageHandler.encode_message(message, state)

      # --- SubscriptionHandler defaults ---
      @impl SubscriptionHandler
      def subscription_init(opts),
        do: DefaultSubscriptionHandler.subscription_init(opts)

      @impl SubscriptionHandler
      def subscribe(channel, params, state),
        do: DefaultSubscriptionHandler.subscribe(channel, params, state)

      @impl SubscriptionHandler
      def unsubscribe(channel, state),
        do: DefaultSubscriptionHandler.unsubscribe(channel, state)

      @impl SubscriptionHandler
      def handle_subscription_response(response, state),
        do: DefaultSubscriptionHandler.handle_subscription_response(response, state)

      @impl SubscriptionHandler
      def active_subscriptions(state),
        do: DefaultSubscriptionHandler.active_subscriptions(state)

      @impl SubscriptionHandler
      def find_subscription_by_channel(channel, state),
        do: DefaultSubscriptionHandler.find_subscription_by_channel(channel, state)

      # --- AuthHandler defaults ---
      @impl AuthHandler
      def generate_auth_data(state),
        do: DefaultAuthHandler.generate_auth_data(state)

      @impl AuthHandler
      def handle_auth_response(response, state),
        do: DefaultAuthHandler.handle_auth_response(response, state)

      @impl AuthHandler
      def needs_reauthentication?(state),
        do: DefaultAuthHandler.needs_reauthentication?(state)

      @impl AuthHandler
      def authenticate(stream_ref, credentials, state),
        do: DefaultAuthHandler.authenticate(stream_ref, credentials, state)

      # --- ErrorHandler defaults ---
      @impl ErrorHandler
      def handle_error(error, context, state),
        do: DefaultErrorHandler.handle_error(error, context, state)

      @impl ErrorHandler
      def should_reconnect?(error, attempt, state),
        do: DefaultErrorHandler.should_reconnect?(error, attempt, state)

      @impl ErrorHandler
      def log_error(error, context, state),
        do: DefaultErrorHandler.log_error(error, context, state)

      @impl ErrorHandler
      def classify_error(error, state),
        do: DefaultErrorHandler.classify_error(error, state)

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
