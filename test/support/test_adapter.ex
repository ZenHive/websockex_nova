defmodule WebsockexNova.Test.Support.TestAdapter do
  @moduledoc """
  A simple adapter for testing WebsockexNova functionality.

  This adapter implements the minimum required behaviors to work with
  WebsockexNova client and is designed for use in tests.
  """

  # Implement only the ConnectionHandler behavior to avoid having to implement
  # all methods from other behaviors for our simple tests
  @behaviour WebsockexNova.Behaviors.ConnectionHandler

  @doc """
  Initializes the adapter state.
  """
  @impl WebsockexNova.Behaviors.ConnectionHandler
  def init(options) do
    # Convert to map if it's a keyword list
    options_map = if is_list(options), do: Enum.into(options, %{}), else: options
    initial_state = Map.get(options_map, :adapter_state, %{})
    {:ok, initial_state}
  end

  @doc """
  Gets connection information from the options.
  """
  @impl WebsockexNova.Behaviors.ConnectionHandler
  def connection_info(options) do
    connection_info = %{
      host: Map.get(options, :host, "localhost"),
      port: Map.get(options, :port, 80),
      path: Map.get(options, :path, "/ws"),
      transport: Map.get(options, :transport, :tls),
      headers: Map.get(options, :headers, []),
      protocols: Map.get(options, :protocols, [:http]),
      transport_opts: Map.get(options, :transport_opts, %{}),
      reconnect: Map.get(options, :reconnect, true),
      retry: Map.get(options, :retry, 5),
      backoff_type: Map.get(options, :backoff_type, :linear),
      base_backoff: Map.get(options, :base_backoff, 1000)
    }

    {:ok, connection_info}
  end

  @doc """
  Encodes a message for sending to the server.
  """
  # Helper function for our tests
  def encode_message(message, _state) do
    case message do
      %{type: "subscribe", channel: channel} ->
        {:ok, "subscribe:#{channel}"}

      %{type: "unsubscribe", channel: channel} ->
        {:ok, "unsubscribe:#{channel}"}

      %{type: "authenticate"} ->
        {:ok, "authenticate"}

      %{type: "ping"} ->
        {:ok, "ping"}

      text when is_binary(text) ->
        {:ok, text}

      _ ->
        {:ok, Jason.encode!(message)}
    end
  end

  @doc """
  Decodes a message received from the server.
  """
  # Not part of behavior but needed for our tests
  def decode_message(message, _state) do
    case message do
      "pong" ->
        {:ok, "pong"}

      "subscribed:" <> channel ->
        {:ok, "subscribed:#{channel}"}

      "unsubscribed:" <> channel ->
        {:ok, "unsubscribed:#{channel}"}

      "authenticated" ->
        {:ok, "authenticated"}

      "echo:" <> content ->
        {:ok, "echo:#{content}"}

      _ ->
        {:ok, message}
    end
  end

  @doc """
  Creates a subscription request.
  """
  # Helper function for our tests
  def subscription_init(options) do
    {:ok, Map.get(options, :subscriptions, %{})}
  end

  @doc """
  Formats a subscription request.
  """
  # Helper function for our tests
  def format_subscription(channel, _params, state) do
    {:ok, %{type: "subscribe", channel: channel}, state}
  end

  @doc """
  Formats an unsubscription request.
  """
  # Helper function for our tests
  def format_unsubscription(channel, _state) do
    {:ok, %{type: "unsubscribe", channel: channel}}
  end

  @doc """
  Updates the subscription state.
  """
  # Helper function for our tests
  def update_subscription_state(channel, _params, state) do
    updated_state = Map.update(state, :subscriptions, %{channel => %{id: 1}}, fn subs -> 
      Map.put(subs, channel, %{id: map_size(subs) + 1})
    end)
    {:ok, updated_state}
  end

  @doc """
  Formats an authentication request.
  """
  # Helper function for our tests
  def format_auth_request(_credentials, _state) do
    {:ok, %{type: "authenticate"}}
  end

  @doc """
  Updates the authentication state.
  """
  # Helper function for our tests
  def update_auth_state(_response, state) do
    updated_state = Map.put(state, :auth_status, :authenticated)
    {:ok, updated_state}
  end
  
  # Implement required callbacks for ConnectionHandler
  @impl true
  def handle_connect(_frame, state), do: {:ok, state}
  @impl true
  def handle_disconnect(_reason, state), do: {:ok, state}
  @impl true
  def handle_frame(_frame, _meta, state), do: {:ok, state}
  @impl true
  def handle_timeout(state), do: {:ok, state}
  @impl true
  def ping(_state, _stream_ref), do: {:ok, "ping"}
  @impl true
  def status(_state, _stream_ref), do: {:ok, :connected}
  
  # Implement required callbacks for MessageHandler (used by Client)
  def message_init(_), do: {:ok, %{}}
  def message_type(_), do: {:text, "text/plain"}
  def validate_message(_), do: :ok 
  def handle_message(_, state), do: {:ok, state}
  
  # Implement required callbacks for SubscriptionHandler (used by Client)
  def subscribe(_, _, state), do: {:ok, state}
  def unsubscribe(_, state), do: {:ok, state}
  def find_subscription_by_channel(channel, state), do: {:ok, Map.get(state, :subscriptions, %{})[channel]}
  def active_subscriptions(state), do: {:ok, Map.get(state, :subscriptions, %{})}
  def handle_subscription_response(_, state), do: {:ok, state}
  
  # Implement required callbacks for AuthHandler (used by Client)
  def generate_auth_data(_), do: {:ok, %{}}
  def authenticate(_, _, state), do: {:ok, state}
  def handle_auth_response(_, state), do: {:ok, state}
  def needs_reauthentication?(_), do: false
end