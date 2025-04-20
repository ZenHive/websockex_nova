defmodule WebsockexNova.Platform.Deribit.Adapter do
  @moduledoc """
  WebsockexNova adapter for the Deribit exchange (testnet).

  Implements the WebsockexNova.Platform.Adapter behaviour for Deribit, supporting:
  - Authentication (public/auth)
  - Public and private JSON-RPC 2.0 requests
  - Subscriptions to public channels
  - Error handling for Deribit-specific responses

  ## Usage
      adapter: WebsockexNova.Platform.Deribit.Adapter
      host: "test.deribit.com"
      port: 443
      path: "/ws/api/v2"

  See integration tests for real-world usage examples.
  """

  use WebsockexNova.Platform.Adapter,
    default_host: "test.deribit.com",
    default_port: 443,
    default_path: "/ws/api/v2"

  require Logger

  @impl true
  @doc """
  Initializes the Deribit adapter state.
  Accepts options and merges with defaults.
  Sets TLS options for Deribit testnet wildcard SSL certificate.
  """
  def init(opts) do
    state =
      opts
      |> Map.new()
      |> Map.put_new(:message_id, 1)
      |> Map.put_new(:subscriptions, %{})
      |> Map.put_new(:auth_token, nil)
      # Ensure Gun is configured for Deribit's wildcard SSL cert
      |> Map.put_new(:transport, :tls)
      |> Map.put_new(:transport_opts,
        verify: :verify_peer,
        cacerts: :certifi.cacerts(),
        server_name_indication: ~c"test.deribit.com"
      )

    {:ok, state}
  end

  @impl true
  @doc """
  Handles platform messages (JSON-RPC 2.0 requests and notifications).
  """
  def handle_platform_message(message, state) when is_map(message) do
    # Encode and send as JSON-RPC
    {:reply, {:text, Jason.encode!(message)}, state}
  end

  def handle_platform_message(message, state) when is_binary(message) do
    # Assume already JSON-encoded, forward as-is
    {:reply, {:text, message}, state}
  end

  def handle_platform_message(_other, state) do
    {:error, %{reason: :invalid_message}, state}
  end

  @impl true
  @doc """
  Encodes an authentication request for Deribit (public/auth).
  Expects credentials map with :api_key and :api_secret.
  """
  def encode_auth_request(%{api_key: key, api_secret: secret}) do
    id = :os.system_time(:millisecond)

    req = %{
      "jsonrpc" => "2.0",
      "id" => id,
      "method" => "public/auth",
      "params" => %{
        "grant_type" => "client_credentials",
        "client_id" => key,
        "client_secret" => secret
      }
    }

    {:text, Jason.encode!(req)}
  end

  @impl true
  @doc """
  Encodes a subscription request for Deribit public channels.
  """
  def encode_subscription_request(channel, params) do
    id = :os.system_time(:millisecond)

    req = %{
      "jsonrpc" => "2.0",
      "id" => id,
      "method" => "public/subscribe",
      "params" => Map.merge(%{"channels" => [channel]}, params)
    }

    {:text, Jason.encode!(req)}
  end

  @impl true
  @doc """
  Encodes an unsubscription request for Deribit public channels.
  """
  def encode_unsubscription_request(channel) do
    id = :os.system_time(:millisecond)

    req = %{
      "jsonrpc" => "2.0",
      "id" => id,
      "method" => "public/unsubscribe",
      "params" => %{
        "channels" => [channel]
      }
    }

    {:text, Jason.encode!(req)}
  end

  # TODO: Add advanced stateful handling for session, token refresh, etc.
end
