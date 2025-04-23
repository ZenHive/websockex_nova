defmodule WebsockexNova.Examples.DeribitAdapter do
  @moduledoc """
  Minimal Deribit WebSocket API v2 adapter for demonstration/testing.

  This adapter implements the following behaviors:
  - ConnectionHandler - For managing WebSocket connections
  - MessageHandler - For processing and formatting messages
  - AuthHandler - For authentication with Deribit API
  - SubscriptionHandler - For managing channel subscriptions

  It leverages the default implementations where possible while adding
  Deribit-specific functionality where needed.
  """

  @behaviour WebsockexNova.Behaviors.AuthHandler
  @behaviour WebsockexNova.Behaviors.ConnectionHandler
  @behaviour WebsockexNova.Behaviors.MessageHandler
  @behaviour WebsockexNova.Behaviors.SubscriptionHandler

  alias WebsockexNova.Behaviors.AuthHandler
  alias WebsockexNova.Behaviors.ConnectionHandler
  alias WebsockexNova.Behaviors.MessageHandler
  alias WebsockexNova.Behaviors.SubscriptionHandler
  alias WebsockexNova.Defaults.DefaultAuthHandler
  alias WebsockexNova.Defaults.DefaultMessageHandler
  alias WebsockexNova.Defaults.DefaultSubscriptionHandler

  require Logger

  @port 443
  @path "/ws/api/v2"
  @logger_prefix "[DeribitAdapter]"
  @default_max_reconnect_attempts 5

  # --- ConnectionHandler implementation ---

  @impl ConnectionHandler
  def connection_info(_opts) do
    host = System.get_env("DERIBIT_HOST") || default_host()

    {:ok,
     %{
       host: host,
       port: @port,
       path: @path,
       headers: [],
       timeout: 30_000,
       transport_opts: %{transport: :tls}
     }}
  end

  defp default_host do
    case Mix.env() do
      :test -> "test.deribit.com"
      :dev -> "test.deribit.com"
      _ -> "www.deribit.com"
    end
  end

  @impl ConnectionHandler
  def init(_opts) do
    Logger.debug("#{@logger_prefix} Initializing adapter")

    # Initialize with a merged state containing Deribit-specific fields
    # and standard fields used by default handlers
    state = %{
      messages: [],
      connected_at: nil,
      auth_status: :unauthenticated,
      reconnect_attempts: 0,
      max_reconnect_attempts: @default_max_reconnect_attempts,
      subscriptions: %{},
      subscription_requests: %{}
    }

    {:ok, state}
  end

  @impl ConnectionHandler
  def handle_connect(_conn_info, state) do
    Logger.info("#{@logger_prefix} Connected to Deribit WebSocket API v2")
    {:ok, %{state | connected_at: System.system_time(:millisecond), reconnect_attempts: 0}}
  end

  @impl ConnectionHandler
  def handle_disconnect(reason, state) do
    Logger.info("#{@logger_prefix} Disconnected, will attempt reconnect. Reason: #{inspect(reason)}")

    # Handle reconnect logic similar to DefaultConnectionHandler
    current_attempts = Map.get(state, :reconnect_attempts, 0)
    max_attempts = Map.get(state, :max_reconnect_attempts, @default_max_reconnect_attempts)

    updated_state = Map.put(state, :last_disconnect_reason, reason)

    if current_attempts < max_attempts do
      updated_state = Map.put(updated_state, :reconnect_attempts, current_attempts + 1)
      {:reconnect, updated_state}
    else
      Logger.warning("#{@logger_prefix} Max reconnect attempts (#{max_attempts}) reached")
      {:ok, updated_state}
    end
  end

  @impl ConnectionHandler
  def handle_frame(:text, data, state) do
    Logger.debug("#{@logger_prefix} Received text frame: #{inspect(data)}")
    # Store the raw message in our message history
    new_state = %{state | messages: [data | state.messages]}
    {:ok, new_state}
  end

  @impl ConnectionHandler
  def handle_frame(:ping, frame_data, state) do
    Logger.debug("#{@logger_prefix} Responding to ping")
    # Automatically respond to pings with pongs (from DefaultConnectionHandler)
    {:reply, :pong, frame_data, state}
  end

  @impl ConnectionHandler
  def handle_frame(_type, _data, state), do: {:ok, state}

  @impl ConnectionHandler
  def handle_timeout(state) do
    Logger.warning("#{@logger_prefix} Connection timeout")

    # Handle timeout reconnect logic similar to DefaultConnectionHandler
    current_attempts = Map.get(state, :reconnect_attempts, 0)
    max_attempts = Map.get(state, :max_reconnect_attempts, @default_max_reconnect_attempts)

    if current_attempts < max_attempts do
      updated_state = Map.put(state, :reconnect_attempts, current_attempts + 1)
      {:reconnect, updated_state}
    else
      Logger.error("#{@logger_prefix} Max reconnect attempts reached, stopping")
      {:stop, :max_reconnect_attempts_reached, state}
    end
  end

  @impl ConnectionHandler
  def ping(_stream_ref, state), do: {:ok, state}

  @impl ConnectionHandler
  def status(_stream_ref, state) do
    status = if state.connected_at, do: :connected, else: :disconnected
    {:ok, status, state}
  end

  # --- MessageHandler implementation ---
  # Delegate to DefaultMessageHandler for message handling functionality

  @impl MessageHandler
  def message_init(opts), do: DefaultMessageHandler.message_init(opts)

  @impl MessageHandler
  def handle_message(message, state) do
    Logger.debug("#{@logger_prefix} Processing message: #{inspect(message)}")

    # Check if this is a subscription-related message first
    if is_map(message) and
         (Map.has_key?(message, "subscription") or
            (Map.has_key?(message, "method") and String.contains?(Map.get(message, "method", ""), "subscribe"))) do
      # Process as a subscription message
      case handle_subscription_response(message, state) do
        {:ok, updated_state} ->
          # Also store the message in our state
          {:ok, Map.put(updated_state, :last_message, message)}

        error_response ->
          error_response
      end
    else
      # Use DefaultMessageHandler for non-subscription messages
      case DefaultMessageHandler.handle_message(message, state) do
        {:ok, updated_state} ->
          {:ok, Map.put(updated_state, :last_message, message)}

        error_response ->
          error_response
      end
    end
  end

  @impl MessageHandler
  def validate_message(message), do: DefaultMessageHandler.validate_message(message)

  @impl MessageHandler
  def message_type(message), do: DefaultMessageHandler.message_type(message)

  @impl MessageHandler
  def encode_message(message, state) do
    Logger.debug("#{@logger_prefix} Encoding message: #{inspect(message)}")
    DefaultMessageHandler.encode_message(message, state)
  end

  # --- SubscriptionHandler implementation ---
  # Use DefaultSubscriptionHandler with Deribit-specific customizations

  @impl SubscriptionHandler
  def subscription_init(opts) do
    # Add subscription_requests to the default init
    {:ok, state} = DefaultSubscriptionHandler.subscription_init(opts)
    {:ok, Map.put(state, :subscription_requests, %{})}
  end

  @impl SubscriptionHandler
  def subscribe(channel, params, state) do
    Logger.info("#{@logger_prefix} Subscribing to channel: #{channel}")

    # Get a subscription ID from DefaultSubscriptionHandler
    case DefaultSubscriptionHandler.subscribe(channel, params, state) do
      {:ok, subscription_id, updated_state} ->
        # Create Deribit-specific subscription message
        message = %{
          "jsonrpc" => "2.0",
          "id" => System.unique_integer([:positive]),
          "method" => "public/subscribe",
          "params" => %{
            "channels" => [channel]
          }
        }

        # Ensure subscription_requests exists in state
        subscription_requests = Map.get(updated_state, :subscription_requests, %{})
        subscription_request = Jason.encode!(message)

        # Store the subscription_id with the formatted message for future reference
        updated_state =
          Map.put(
            updated_state,
            :subscription_requests,
            Map.put(subscription_requests, subscription_id, subscription_request)
          )

        {:ok, subscription_request, updated_state}
    end
  end

  @impl SubscriptionHandler
  def unsubscribe(subscription_id, state) do
    Logger.info("#{@logger_prefix} Unsubscribing from subscription: #{subscription_id}")

    # Find channel for this subscription
    subscription = get_in(state, [:subscriptions, subscription_id])

    if subscription do
      channel = subscription.channel

      # Create Deribit-specific unsubscribe message
      message = %{
        "jsonrpc" => "2.0",
        "id" => System.unique_integer([:positive]),
        "method" => "public/unsubscribe",
        "params" => %{
          "channels" => [channel]
        }
      }

      # Update state through DefaultSubscriptionHandler
      case DefaultSubscriptionHandler.unsubscribe(subscription_id, state) do
        {:ok, updated_state} ->
          {:ok, Jason.encode!(message), updated_state}

        error ->
          error
      end
    else
      {:error, :subscription_not_found, state}
    end
  end

  @impl SubscriptionHandler
  def handle_subscription_response(response, state) do
    Logger.debug("#{@logger_prefix} Handling subscription response: #{inspect(response)}")

    # Handle Deribit-specific subscription responses
    # Deribit subscription confirmation format
    if is_map(response) and Map.has_key?(response, "params") and Map.has_key?(response, "method") and
         response["method"] == "subscription" do
      channel = get_in(response, ["params", "channel"])
      subscription_id = DefaultSubscriptionHandler.find_subscription_by_channel(channel, state)

      if subscription_id do
        # Mark as confirmed using DefaultSubscriptionHandler helper
        subscriptions = Map.get(state, :subscriptions, %{})
        updated_subscription = Map.put(subscriptions[subscription_id], :status, :confirmed)
        updated_subscriptions = Map.put(subscriptions, subscription_id, updated_subscription)
        updated_state = Map.put(state, :subscriptions, updated_subscriptions)

        {:ok, updated_state}
      else
        # Unknown subscription, just pass through
        {:ok, state}
      end
    else
      # Delegate to DefaultSubscriptionHandler for standard formats
      DefaultSubscriptionHandler.handle_subscription_response(response, state)
    end
  end

  @impl SubscriptionHandler
  def active_subscriptions(state) do
    DefaultSubscriptionHandler.active_subscriptions(state)
  end

  @impl SubscriptionHandler
  def find_subscription_by_channel(channel, state) do
    DefaultSubscriptionHandler.find_subscription_by_channel(channel, state)
  end

  # --- AuthHandler implementation ---
  # Deribit-specific auth implementation with some delegation to DefaultAuthHandler

  @impl AuthHandler
  def generate_auth_data(state) do
    Logger.debug("#{@logger_prefix} Generating auth data")

    client_id = System.get_env("DERIBIT_CLIENT_ID")
    client_secret = System.get_env("DERIBIT_CLIENT_SECRET")

    # This is Deribit-specific auth payload format
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

    # Store credentials in state for potential future use
    state = put_in(state, [:credentials], %{api_key: client_id, secret: client_secret})

    {:ok, Jason.encode!(payload), state}
  end

  @impl AuthHandler
  def authenticate(_stream_ref, _credentials, state) do
    # The client will use generate_auth_data/1 and handle_auth_response/2
    {:ok, state}
  end

  @impl AuthHandler
  def needs_reauthentication?(state) do
    DefaultAuthHandler.needs_reauthentication?(state)
  end

  @impl AuthHandler
  def handle_auth_response(%{"result" => %{"access_token" => token, "expires_in" => expires_in}} = _response, state) do
    Logger.info("#{@logger_prefix} Authentication successful")

    auth_expires_at = System.system_time(:second) + expires_in

    state =
      state
      |> Map.put(:auth_status, :authenticated)
      |> Map.put(:auth_expires_at, auth_expires_at)
      |> put_in([:credentials, :token], token)

    {:ok, state}
  end

  @impl AuthHandler
  def handle_auth_response(%{"error" => error} = _response, state) do
    Logger.error("#{@logger_prefix} Authentication failed: #{inspect(error)}")

    state =
      state
      |> Map.put(:auth_status, :failed)
      |> Map.put(:auth_error, error)

    {:error, error, state}
  end

  # Fallback clause for any other response format
  @impl AuthHandler
  def handle_auth_response(_response, state) do
    Logger.error("#{@logger_prefix} Invalid authentication response format")
    {:error, :invalid_auth_response, state}
  end
end
