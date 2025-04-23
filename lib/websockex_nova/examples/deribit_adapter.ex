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
  alias WebsockexNova.Defaults.DefaultAuthHandler
  alias WebsockexNova.Defaults.DefaultMessageHandler

  require Logger

  @port 443
  @path "/ws/api/v2"
  @logger_prefix "[DeribitAdapter]"

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
    {:ok, %{messages: [], connected_at: nil, auth_status: :unauthenticated}}
  end

  @impl ConnectionHandler
  def handle_connect(_conn_info, state) do
    Logger.info("#{@logger_prefix} Connected to Deribit WebSocket API v2")
    {:ok, %{state | connected_at: System.system_time(:millisecond)}}
  end

  @impl ConnectionHandler
  def handle_disconnect(_reason, state) do
    Logger.info("#{@logger_prefix} Disconnected, will attempt reconnect")
    {:reconnect, state}
  end

  @impl ConnectionHandler
  def handle_frame(:text, data, state) do
    Logger.debug("#{@logger_prefix} Received text frame: #{inspect(data)}")
    # Store the raw message in our message history
    new_state = %{state | messages: [data | state.messages]}
    {:ok, new_state}
  end

  @impl ConnectionHandler
  def handle_frame(_type, _data, state), do: {:ok, state}

  @impl ConnectionHandler
  def handle_timeout(state) do
    Logger.warning("#{@logger_prefix} Connection timeout")
    {:reconnect, state}
  end

  @impl ConnectionHandler
  def ping(_stream_ref, state), do: {:ok, state}

  @impl ConnectionHandler
  def status(_stream_ref, state) do
    status = if state.connected_at, do: :connected, else: :disconnected
    {:ok, status, state}
  end

  # --- MessageHandler ---
  # Delegate to DefaultMessageHandler for message handling functionality

  @impl MessageHandler
  def message_init(opts), do: DefaultMessageHandler.message_init(opts)

  @impl MessageHandler
  def handle_message(message, state) do
    Logger.debug("#{@logger_prefix} Processing message: #{inspect(message)}")

    # Use DefaultMessageHandler but also store the message in our state
    case DefaultMessageHandler.handle_message(message, state) do
      {:ok, updated_state} ->
        {:ok, Map.put(updated_state, :last_message, message)}

      error_response ->
        error_response
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

  # --- AuthHandler ---
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
