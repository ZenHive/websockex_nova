defmodule WebsockexNova.Adapter do
  @moduledoc """
  Macro for building platform adapters with minimal boilerplate.

  Usage:

      defmodule MyApp.Platform.MyAdapter do
        use WebsockexNova.Adapter

        @impl WebsockexNova.Behaviors.ConnectionHandler
        def handle_connect(conn_info, state), do: {:ok, state}
        # ...implement required callbacks...
      end

  This macro:
    * Injects all core @behaviour declarations
    * Provides default no-op implementations for optional callbacks
    * Makes it easy to override only what you need
  """

  defmacro __using__(_opts) do
    quote do
      @behaviour WebsockexNova.Platform.Adapter
      @behaviour WebsockexNova.Behaviors.ConnectionHandler
      @behaviour WebsockexNova.Behaviors.MessageHandler
      @behaviour WebsockexNova.Behaviors.SubscriptionHandler
      @behaviour WebsockexNova.Behaviors.AuthHandler
      @behaviour WebsockexNova.Behaviors.ErrorHandler
      @behaviour WebsockexNova.Behaviors.RateLimitHandler
      @behaviour WebsockexNova.Behaviors.LoggingHandler
      @behaviour WebsockexNova.Behaviors.MetricsCollector

      # --- Default optional callbacks for ConnectionHandler ---
      def handle_disconnect(reason, state), do: {:ok, state}
      def handle_timeout(state), do: {:ok, state}
      def ping(_stream_ref, state), do: {:pong, state}
      def status(_stream_ref, state), do: {:status, :unknown, state}

      # --- Default optional callbacks for MessageHandler ---
      def handle_message(_message, state), do: {:ok, state}

      # --- Default optional callbacks for SubscriptionHandler ---
      def active_subscriptions(_state), do: []
      def find_subscription_by_channel(_channel, _state), do: nil
      def handle_subscription_response(_resp, state), do: {:ok, state}

      # --- Default optional callbacks for AuthHandler ---
      def needs_reauthentication?(_state), do: false
      def handle_auth_response(_resp, state), do: {:ok, state}

      # --- Default optional callbacks for ErrorHandler ---
      def handle_error(_error, _context, state), do: {:ok, state}

      # --- Default optional callbacks for RateLimitHandler ---
      def check(_request, _handler), do: {:allow, nil}
      def on_process(_request_id, _callback, _handler), do: :ok

      # --- Default optional callbacks for LoggingHandler ---
      def log(_level, _msg, state), do: {:ok, state}

      # --- Default optional callbacks for MetricsCollector ---
      def collect(_event, _data, state), do: {:ok, state}

      # Allow adapter to override any of these
      defoverridable handle_disconnect: 2,
                     handle_timeout: 1,
                     ping: 2,
                     status: 2,
                     handle_message: 2,
                     active_subscriptions: 1,
                     find_subscription_by_channel: 2,
                     handle_subscription_response: 2,
                     needs_reauthentication?: 1,
                     handle_auth_response: 2,
                     handle_error: 3,
                     check: 2,
                     on_process: 3,
                     log: 3,
                     collect: 3
    end
  end
end
