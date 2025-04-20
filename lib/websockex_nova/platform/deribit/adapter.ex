defmodule WebsockexNova.Platform.Deribit.Adapter do
  @moduledoc """
  Deribit platform adapter for WebsockexNova.

  Implements the WebsockexNova.Platform.Adapter contract for Deribit public and private WebSocket API.
  Handles authentication, subscription, and generic JSON-RPC requests.

  ## Features

  - Encodes authentication, subscription, and unsubscription requests as JSON-RPC frames.
  - Handles platform messages by echoing back inert responses (for test scaffolding).
  - Intended as a starting point for full Deribit integration.
  """

  use WebsockexNova.Platform.Adapter,
    default_host: "test.deribit.com",
    default_port: 443,
    default_path: "/ws/api/v2"

  @impl true
  @doc """
  Initializes the Deribit adapter state.
  Accepts options and merges with defaults.
  """
  def init(opts) do
    {:ok, opts}
  end

  @impl true
  @doc """
  Handles platform messages by echoing back inert responses for test scaffolding.
  """
  def handle_platform_message(%{"method" => "public/hello"} = msg, state) do
    reply = %{jsonrpc: "2.0", id: Map.get(msg, "id", 1), result: "hello"}
    {:reply, {:text, Jason.encode!(reply)}, state}
  end

  def handle_platform_message(%{"method" => method} = msg, state) when is_binary(method) do
    # Echo back a generic inert response for any other method
    reply = %{jsonrpc: "2.0", id: Map.get(msg, "id", 1), result: "ok"}
    {:reply, {:text, Jason.encode!(reply)}, state}
  end

  def handle_platform_message(message, state) when is_map(message) do
    # Fallback for map messages
    reply = %{jsonrpc: "2.0", id: 1, result: "ok"}
    {:reply, {:text, Jason.encode!(reply)}, state}
  end

  def handle_platform_message(message, state) when is_binary(message) do
    # Try to decode as JSON, otherwise echo as text
    case Jason.decode(message) do
      {:ok, decoded} -> handle_platform_message(decoded, state)
      _ -> {:reply, {:text, message}, state}
    end
  end

  def handle_platform_message(message, state) do
    {:reply, {:text, to_string(message)}, state}
  end

  @impl true
  @doc """
  Encodes an authentication request for Deribit using client credentials.
  """
  def encode_auth_request(%{client_id: client_id, client_secret: client_secret}) do
    req = %{
      jsonrpc: "2.0",
      id: 1,
      method: "public/auth",
      params: %{
        grant_type: "client_credentials",
        client_id: client_id,
        client_secret: client_secret
      }
    }

    {:text, Jason.encode!(req)}
  end

  @impl true
  @doc """
  Encodes a subscription request for Deribit public or private channels.
  """
  def encode_subscription_request(channel, params \\ %{}) do
    req = %{
      jsonrpc: "2.0",
      id: 1,
      method: "public/subscribe",
      params: Map.merge(%{"channels" => [channel]}, params)
    }

    {:text, Jason.encode!(req)}
  end

  @impl true
  @doc """
  Encodes an unsubscription request for Deribit public or private channels.
  """
  def encode_unsubscription_request(channel) do
    req = %{
      jsonrpc: "2.0",
      id: 1,
      method: "public/unsubscribe",
      params: %{"channels" => [channel]}
    }

    {:text, Jason.encode!(req)}
  end
end
