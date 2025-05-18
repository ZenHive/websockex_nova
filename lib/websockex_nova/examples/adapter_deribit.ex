defmodule WebsockexNova.Examples.AdapterDeribit do
  @moduledoc """
  Example Deribit adapter using `use WebsockexNova.Adapter` macro.

  This demonstrates how to build a Deribit WebSocket API adapter with minimal overrides.
  """
  use WebsockexNova.Adapter

  alias WebsockexNova.Behaviors.AuthHandler
  alias WebsockexNova.Behaviors.ConnectionHandler
  alias WebsockexNova.Defaults.DefaultMessageHandler

  @port 443
  @path "/ws/api/v2"

  defp default_host do
    case Mix.env() do
      :test -> "test.deribit.com"
      :dev -> "test.deribit.com"
      _ -> "www.deribit.com"
    end
  end

  @impl ConnectionHandler
  def connection_info(opts) do
    host = Map.get(opts, :host) || System.get_env("DERIBIT_HOST") || default_host()

    defaults = %{
      # Connection/Transport
      host: host,
      port: @port,
      path: @path,
      headers: [],
      timeout: 10_000,
      transport: :tls,
      transport_opts: %{},
      protocols: [:http],
      retry: 10,
      backoff_type: :exponential,
      base_backoff: 2_000,
      ws_opts: %{},
      callback_pid: nil,

      # Rate Limiting
      rate_limit_handler: WebsockexNova.Defaults.DefaultRateLimitHandler,
      rate_limit_opts: %{
        mode: :normal,
        capacity: 120,
        refill_rate: 10,
        refill_interval: 1_000,
        queue_limit: 200,
        cost_map: %{
          subscription: 5,
          auth: 10,
          query: 1,
          order: 10
        }
      },

      # Logging
      logging_handler: WebsockexNova.Defaults.DefaultLoggingHandler,
      log_level: :info,
      log_format: :plain,

      # Metrics
      metrics_collector: nil,

      # Authentication
      auth_handler: WebsockexNova.Defaults.DefaultAuthHandler,
      credentials: %{
        api_key: System.get_env("DERIBIT_CLIENT_ID"),
        secret: System.get_env("DERIBIT_CLIENT_SECRET")
      },
      auth_refresh_threshold: 60,

      # Subscription
      subscription_handler: WebsockexNova.Defaults.DefaultSubscriptionHandler,
      subscription_timeout: 30,

      # Message
      message_handler: DefaultMessageHandler,

      # Error Handling
      error_handler: WebsockexNova.Defaults.DefaultErrorHandler,
      max_reconnect_attempts: 5,
      reconnect_attempts: 0,
      ping_interval: 30_000
    }

    {:ok, Map.merge(defaults, opts)}
  end

  @impl ConnectionHandler
  def init(_opts) do
    then(
      %{
        messages: [],
        connected_at: nil,
        auth_status: :unauthenticated,
        reconnect_attempts: 0,
        max_reconnect_attempts: 5,
        subscriptions: %{},
        subscription_requests: %{}
      },
      &{:ok, &1}
    )
  end

  @impl AuthHandler
  def generate_auth_data(state) do
    client_id = System.get_env("DERIBIT_CLIENT_ID")
    client_secret = System.get_env("DERIBIT_CLIENT_SECRET")

    payload = %{
      "jsonrpc" => "2.0",
      "id" => 42,
      "method" => "public/auth",
      "params" => %{
        "grant_type" => "client_credentials",
        "client_id" => client_id,
        "client_secret" => client_secret
      }
    }

    state = put_in(state, [:credentials], %{api_key: client_id, secret: client_secret})
    {:ok, Jason.encode!(payload), state}
  end

  @impl AuthHandler
  def handle_auth_response(%{"result" => %{"access_token" => access_token, "expires_in" => expires_in}}, state) do
    state =
      state
      |> Map.put(:auth_status, :authenticated)
      |> Map.put(:access_token, access_token)
      |> Map.put(:auth_expires_in, expires_in)

    {:ok, state}
  end

  def handle_auth_response(%{"error" => error}, state) do
    state =
      state
      |> Map.put(:auth_status, :failed)
      |> Map.put(:auth_error, error)

    {:error, error, state}
  end

  def handle_auth_response(_other, state), do: {:ok, state}

  @impl WebsockexNova.Behaviors.SubscriptionHandler
  def subscribe(channel, _params, state) do
    # Check if we need authentication for raw channels
    needs_auth = String.contains?(channel, ".raw")

    method = if needs_auth && state[:access_token], do: "private/subscribe", else: "public/subscribe"

    params = %{"channels" => [channel]}

    params =
      if needs_auth && state[:access_token] do
        Map.put(params, "access_token", state[:access_token])
      else
        params
      end

    message = %{
      "jsonrpc" => "2.0",
      "id" => System.unique_integer([:positive]),
      "method" => method,
      "params" => params
    }

    {:ok, Jason.encode!(message), state}
  end

  @impl WebsockexNova.Behaviors.MessageHandler
  def handle_message(%{"error" => %{"code" => 13_778}} = message, state) do
    # Handle "raw_subscriptions_not_available_for_unauthorized" error
    # This means we need to authenticate first
    {:needs_auth, message, state}
  end

  def handle_message(message, state) do
    # Let the default handler process other messages
    DefaultMessageHandler.handle_message(message, state)
  end
end
