defmodule WebsockexNova.Examples.DeribitAdapter do
  @moduledoc """
  Minimal Deribit WebSocket API v2 adapter for demonstration/testing.
  Implements connection, message, and authentication handling.
  """

  @behaviour WebsockexNova.Behaviors.AuthHandler
  @behaviour WebsockexNova.Behaviors.ConnectionHandler
  @behaviour WebsockexNova.Behaviors.MessageHandler

  alias WebsockexNova.Behaviors.AuthHandler
  alias WebsockexNova.Behaviors.ConnectionHandler
  alias WebsockexNova.Behaviors.MessageHandler

  require Logger

  @host "www.deribit.com"
  @port 443
  @path "/ws/api/v2"

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
  def connection_init(opts), do: init(opts)

  @impl ConnectionHandler
  def init(_opts) do
    Logger.debug("[DeribitAdapter] Initializing state")
    {:ok, %{messages: [], connected_at: nil, access_token: nil, expires_in: nil}}
  end

  @impl ConnectionHandler
  def handle_connect(_conn_info, state) do
    Logger.info("[DeribitAdapter] Connected to Deribit WebSocket API v2")
    {:ok, %{state | connected_at: System.system_time(:millisecond)}}
  end

  @impl ConnectionHandler
  def handle_disconnect(_reason, state) do
    Logger.info("[DeribitAdapter] Disconnected, will attempt reconnect")
    {:reconnect, state}
  end

  @impl ConnectionHandler
  def handle_frame(:text, data, state) do
    Logger.debug("[DeribitAdapter] Received text frame: #{inspect(data)}")
    new_state = %{state | messages: [data | state.messages]}
    {:ok, new_state}
  end

  @impl ConnectionHandler
  def handle_frame(_type, _data, state) do
    {:ok, state}
  end

  @impl ConnectionHandler
  def handle_timeout(state) do
    Logger.warning("[DeribitAdapter] Connection timeout")
    {:reconnect, state}
  end

  @impl ConnectionHandler
  def ping(_stream_ref, state), do: {:ok, state}

  @impl ConnectionHandler
  def status(_stream_ref, state) do
    status = if state.connected_at, do: :connected, else: :disconnected
    {:ok, status, state}
  end

  @impl MessageHandler
  def message_init(_opts), do: {:ok, %{}}

  @impl MessageHandler
  def handle_message(message, state) do
    Logger.debug("[DeribitAdapter] handle_message: #{inspect(message)}")
    {:ok, message, state}
  end

  @impl MessageHandler
  def validate_message(message), do: {:ok, message}

  @impl MessageHandler
  def message_type(message) when is_binary(message), do: :text
  @impl MessageHandler
  def message_type(message) when is_map(message), do: :json
  @impl MessageHandler
  def message_type(_message), do: :unknown

  @impl MessageHandler
  def encode_message(:text, message) when is_binary(message), do: {:ok, message}
  @impl MessageHandler
  def encode_message(:json, message) when is_map(message) do
    case Jason.encode(message) do
      {:ok, json} -> {:ok, json}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl MessageHandler
  def encode_message(_type, message), do: {:ok, to_string(message)}

  # 3-arity version for compatibility
  def encode_message(:text, message, _state) when is_binary(message), do: {:ok, message}

  def encode_message(:json, message, _state) when is_map(message) do
    case Jason.encode(message) do
      {:ok, json} -> {:ok, json}
      {:error, reason} -> {:error, reason}
    end
  end

  def encode_message(_type, message, _state), do: {:ok, to_string(message)}

  # --- AuthHandler ---

  @impl AuthHandler
  def generate_auth_data(state) do
    client_id = System.get_env("DERIBIT_CLIENT_ID")
    client_secret = System.get_env("DERIBIT_CLIENT_SECRET")
    id = 42

    payload = %{
      "jsonrpc" => "2.0",
      "id" => id,
      "method" => "public/auth",
      "params" => %{
        "grant_type" => "client_credentials",
        "client_id" => client_id,
        "client_secret" => client_secret
      }
    }

    {:ok, Jason.encode!(payload), state}
  end

  @impl AuthHandler
  def handle_auth_response(response, state) do
    case Jason.decode(response) do
      {:ok, %{"result" => %{"access_token" => token, "expires_in" => expires_in}}} ->
        {:ok, %{state | access_token: token, expires_in: expires_in}}

      {:ok, %{"error" => error}} ->
        {:error, error, state}

      _ ->
        {:error, :invalid_auth_response, state}
    end
  end

  @impl AuthHandler
  def authenticate(_stream_ref, _credentials, state) do
    # The client will use generate_auth_data/1 and handle_auth_response/2
    {:ok, state}
  end
end
