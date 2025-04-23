defmodule WebsockexNova.Examples.EchoAdapter do
  @moduledoc """
  An example adapter for the echo.websocket.org WebSocket Echo Server.

  This adapter demonstrates how to create a simple WebSocket client implementation
  that connects to a public WebSocket echo service. The echo server will return
  any message sent to it.

  ## Usage

  ```elixir
  alias WebsockexNova.Client
  alias WebsockexNova.Examples.EchoAdapter

  # Connect to the echo server
  {:ok, conn} = Client.connect(EchoAdapter, %{})

  # Send a text message and receive the echo
  {:ok, response} = Client.send_text(conn, "Hello, WebSocket!")
  # => {:ok, "Hello, WebSocket!"}
  ```

  The echo server at echo.websocket.org provides a simple way to test WebSocket
  functionality by echoing back any messages sent to it.
  """

  @behaviour WebsockexNova.Behaviors.AuthHandler
  @behaviour WebsockexNova.Behaviors.ConnectionHandler
  @behaviour WebsockexNova.Behaviors.ErrorHandler
  @behaviour WebsockexNova.Behaviors.MessageHandler
  @behaviour WebsockexNova.Behaviors.SubscriptionHandler

  alias WebsockexNova.Behaviors.AuthHandler
  alias WebsockexNova.Behaviors.ConnectionHandler
  alias WebsockexNova.Behaviors.ErrorHandler
  alias WebsockexNova.Behaviors.MessageHandler
  alias WebsockexNova.Behaviors.SubscriptionHandler

  require Logger

  @host "echo.websocket.org"
  @port 443
  @path "/"

  @doc """
  Returns connection information for the echo.websocket.org WebSocket server.
  """
  @impl ConnectionHandler
  def connection_info(_opts) do
    {:ok,
     %{
       host: @host,
       port: @port,
       path: @path,
       headers: [],
       timeout: 30_000,
       transport_opts: %{
         transport: :tls
       }
     }}
  end

  #
  # ConnectionHandler callbacks
  #

  @impl ConnectionHandler
  def init(_opts) do
    {:ok,
     %{
       messages: [],
       connected_at: nil
     }}
  end

  @impl ConnectionHandler
  def handle_connect(conn_info, state) do
    Logger.info("Connected to echo.websocket.org: #{inspect(conn_info)}")

    # Update state with connection information
    {:ok, %{state | connected_at: System.system_time(:millisecond)}}
  end

  @impl ConnectionHandler
  def handle_disconnect(reason, state) do
    Logger.info("Disconnected from echo.websocket.org: #{inspect(reason)}")
    {:ok, state}
  end

  @impl ConnectionHandler
  def handle_frame(:text, data, state) do
    Logger.debug("Received text frame: #{inspect(data)}")

    # Store the message
    new_state = %{state | messages: [data | state.messages]}

    {:ok, new_state}
  end

  @impl ConnectionHandler
  def handle_frame(:ping, _data, state) do
    # Send pong automatically (although the library should handle this too)
    {:reply, :pong, "", state}
  end

  @impl ConnectionHandler
  def handle_frame(frame_type, data, state) do
    Logger.debug("Received #{inspect(frame_type)} frame: #{inspect(data)}")
    {:ok, state}
  end

  @impl ConnectionHandler
  def handle_timeout(state) do
    Logger.warning("Connection timeout")
    {:ok, state}
  end

  @impl ConnectionHandler
  def ping(_stream_ref, state) do
    {:ok, state}
  end

  @impl ConnectionHandler
  def status(_stream_ref, state) do
    status = if state.connected_at, do: :connected, else: :disconnected
    {:ok, status, state}
  end

  #
  # MessageHandler callbacks
  #

  @impl MessageHandler
  def message_init(_opts) do
    {:ok, %{}}
  end

  @impl MessageHandler
  def handle_message(message, state) do
    # Simply echo the message back to the client
    {:ok, %{state | last_message: message}}
  end

  @impl MessageHandler
  def validate_message(message) do
    # Accept all messages
    {:ok, message}
  end

  @impl MessageHandler
  def message_type(message) when is_binary(message) do
    :text
  end

  @impl MessageHandler
  def message_type(message) when is_map(message) do
    :json
  end

  @impl MessageHandler
  def message_type(_message) do
    :unknown
  end

  @impl MessageHandler
  def encode_message(message_type, _state) do
    case message_type do
      message when is_binary(message) ->
        {:ok, :text, message}

      message when is_map(message) ->
        case Jason.encode(message) do
          {:ok, json} -> {:ok, :text, json}
          {:error, reason} -> {:error, reason}
        end

      _ ->
        {:ok, :text, to_string(message_type)}
    end
  end

  # Support for the 3-parameter version for client.ex
  def encode_message(:text, message, _state) when is_binary(message) do
    # Text messages are sent as-is
    {:ok, message}
  end

  def encode_message(:json, message, _state) when is_map(message) do
    # Encode maps as JSON strings
    case Jason.encode(message) do
      {:ok, json} -> {:ok, json}
      {:error, reason} -> {:error, reason}
    end
  end

  def encode_message(_type, message, _state) do
    # Convert other types to string
    {:ok, to_string(message)}
  end

  #
  # ErrorHandler callbacks
  #

  @impl ErrorHandler
  def handle_error(error, context, state) do
    Logger.error("Error: #{inspect(error)}, Context: #{inspect(context)}")
    {:stop, error, state}
  end

  @impl ErrorHandler
  def should_reconnect?(_error, attempt, _state) do
    # Use exponential backoff for reconnection
    delay = min(1000 * :math.pow(2, attempt), 30_000)
    {true, round(delay)}
  end

  @impl ErrorHandler
  def log_error(error, context, _state) do
    Logger.error("Echo server error: #{inspect(error)}, Context: #{inspect(context)}")
    :ok
  end

  @impl ErrorHandler
  def classify_error(_error, _state) do
    :recoverable
  end

  #
  # SubscriptionHandler callbacks
  #

  @impl SubscriptionHandler
  def subscription_init(_opts) do
    # Echo server doesn't support subscriptions, but we provide implementations
    # to satisfy the behavior
    {:ok, %{subscriptions: []}}
  end

  @impl SubscriptionHandler
  def subscribe(_channel, state, _opts) do
    # Echo server doesn't support subscriptions
    {:error, :not_supported, state}
  end

  @impl SubscriptionHandler
  def unsubscribe(_channel, state) do
    # Echo server doesn't support subscriptions
    {:error, :not_supported, state}
  end

  @impl SubscriptionHandler
  def handle_subscription_response(_response, state) do
    {:ok, state}
  end

  @impl SubscriptionHandler
  def active_subscriptions(_state) do
    %{}
  end

  @impl SubscriptionHandler
  def find_subscription_by_channel(_channel, _state) do
    nil
  end

  #
  # AuthHandler callbacks
  #

  @impl AuthHandler
  def generate_auth_data(state) do
    # Echo server doesn't require authentication
    {:ok, "", state}
  end

  @impl AuthHandler
  def handle_auth_response(_response, state) do
    {:ok, state}
  end

  @impl AuthHandler
  def needs_reauthentication?(_state) do
    false
  end

  @impl AuthHandler
  def authenticate(_stream_ref, _credentials, state) do
    # Echo server doesn't require authentication
    {:ok, state}
  end
end
