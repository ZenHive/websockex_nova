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
      auth_handler: __MODULE__,
      credentials: %{
        api_key: System.get_env("DERIBIT_CLIENT_ID"),
        secret: System.get_env("DERIBIT_CLIENT_SECRET")
      },
      auth_refresh_threshold: 60,

      # Subscription
      subscription_handler: __MODULE__,
      subscription_timeout: 30,

      # Message
      message_handler: __MODULE__,

      # Connection handler
      connection_handler: __MODULE__,

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

  @doc """
  Handle WebSocket frames directly. This is crucial for proper handling of
  Deribit's heartbeat mechanism, which requires responding to test_request
  frames with a public/test request.
  """
  @impl ConnectionHandler
  def handle_frame(:text, frame_data, state) do
    # Store the frame in the message list for debugging if needed
    updated_state =
      Map.update(state, :messages, [], fn msgs ->
        # Limit messages list to prevent memory growth
        Enum.take([frame_data | msgs], 50)
      end)

    # First check for heartbeat test_request messages
    case Jason.decode(frame_data) do
      {:ok, %{"method" => "heartbeat", "params" => %{"type" => "test_request"}}} ->
        # Generate a response to the heartbeat test_request
        # This is required by Deribit to maintain the connection
        test_request = %{
          "jsonrpc" => "2.0",
          "id" => System.unique_integer([:positive]),
          "method" => "public/test",
          "params" => %{}
        }

        # Return the response immediately using the proper format
        # Must be {:reply, frame_type, frame_data, updated_state, stream_ref}
        # The stream_ref is needed by the ConnectionWrapper to properly route the response
        # Since we don't have access to the actual stream_ref in the callback,
        # we return :text_frame and the MessageHandlers will use the correct stream_ref
        {:reply, :text, Jason.encode!(test_request), updated_state, :text_frame}

      # For normal JSON messages, pass to message handler after storing in state
      {:ok, decoded} ->
        # Add the parsed message to state for access by higher-level components
        updated_state =
          Map.update(updated_state, :messages, [], fn msgs ->
            # Limit messages list to prevent memory growth
            Enum.take([decoded | msgs], 50)
          end)

        # Normal path - no immediate reply needed
        {:ok, updated_state}

      # Handle JSON parsing errors gracefully
      {:error, _} ->
        # Just pass through if we can't parse the JSON
        {:ok, updated_state}
    end
  end

  # Handle other types of frames (binary, ping, pong, etc.)
  def handle_frame(_frame_type, _frame_data, state) do
    # Just pass them through
    {:ok, state}
  end

  # ConnectionHandler callbacks - required methods

  @impl ConnectionHandler
  def handle_connect(_conn_info, state) do
    # Connection established successfully
    {:ok, state}
  end

  @impl ConnectionHandler
  def handle_disconnect(_reason, state) do
    # Handle disconnection
    {:ok, state}
  end

  @impl ConnectionHandler
  def ping(_stream_ref, state) do
    # Use default ping implementation
    {:ok, state}
  end

  @impl ConnectionHandler
  def status(_stream_ref, state) do
    # Return connection status
    {:ok, :connected, state}
  end


  @impl ConnectionHandler
  def handle_timeout(state) do
    # Handle timeout
    {:ok, state}
  end
end
