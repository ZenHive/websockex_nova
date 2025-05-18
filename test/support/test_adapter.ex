defmodule WebsockexNova.Test.Support.TestAdapter do
  @moduledoc """
  A simple adapter for testing WebsockexNova functionality.

  This adapter implements the minimum required behaviors to work with
  WebsockexNova client and is designed for use in tests.
  """

  # Implement the required behaviors
  @behaviour WebsockexNova.Behaviors.ConnectionHandler
  @behaviour WebsockexNova.Behaviors.AuthHandler
  @behaviour WebsockexNova.Behaviors.MessageHandler

  # ConnectionHandler implementations
  @impl WebsockexNova.Behaviors.ConnectionHandler
  def init(options) do
    # Convert to map if it's a keyword list
    options_map = if is_list(options), do: Enum.into(options, %{}), else: options
    initial_state = Map.get(options_map, :adapter_state, %{})
    {:ok, initial_state}
  end

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

  @impl WebsockexNova.Behaviors.ConnectionHandler
  def handle_connect(_frame, state), do: {:ok, state}

  @impl WebsockexNova.Behaviors.ConnectionHandler
  def handle_disconnect(_reason, state), do: {:ok, state}

  @impl WebsockexNova.Behaviors.ConnectionHandler
  def handle_frame(_frame, _meta, state), do: {:ok, state}

  @impl WebsockexNova.Behaviors.ConnectionHandler
  def handle_timeout(state), do: {:ok, state}

  @impl WebsockexNova.Behaviors.ConnectionHandler
  def ping(state, _params), do: {:ok, :pong, state}
  
  @impl WebsockexNova.Behaviors.ConnectionHandler
  def status(_meta, state), do: {:ok, :connected, state}

  # MessageHandler implementations
  @impl WebsockexNova.Behaviors.MessageHandler
  def message_init(_), do: {:ok, %{}}

  @impl WebsockexNova.Behaviors.MessageHandler
  def message_type(_), do: {:text, "text/plain"}

  @impl WebsockexNova.Behaviors.MessageHandler
  def encode_message(data, _state) when is_map(data) do
    encoded = Jason.encode!(data)
    {:ok, :text, encoded}
  end
  def encode_message(text, _state) when is_binary(text) do
    {:ok, :text, text}
  end

  @impl WebsockexNova.Behaviors.MessageHandler
  def handle_message(message, state) do
    # Try to decode JSON messages
    decoded = case Jason.decode(message) do
      {:ok, data} -> data
      _ -> message
    end
    {:ok, decoded, state}
  end

  @impl WebsockexNova.Behaviors.MessageHandler
  def validate_message(_), do: :ok

  # AuthHandler implementations
  @impl WebsockexNova.Behaviors.AuthHandler
  def generate_auth_data(%WebsockexNova.ClientConn{adapter_state: adapter_state} = conn) do
    credentials = Map.get(adapter_state, :credentials, %{})
    auth_data = %{
      type: "auth",
      token: Map.get(credentials, :token, "test_token")
    }
    
    {:ok, Jason.encode!(auth_data), conn}
  end

  @impl WebsockexNova.Behaviors.AuthHandler
  def handle_auth_response(response, %WebsockexNova.ClientConn{adapter_state: adapter_state} = conn) do
    # Handle both parsed JSON and raw string responses
    IO.puts("TestAdapter handle_auth_response - Raw response: #{inspect(response)}")
    
    parsed_response = case response do
      resp when is_binary(resp) ->
        case Jason.decode(resp) do
          {:ok, data} -> 
            IO.puts("TestAdapter - Parsed JSON: #{inspect(data)}")
            data
          _ -> 
            IO.puts("TestAdapter - Failed to parse JSON, using empty map")
            %{}
        end
      resp when is_map(resp) -> 
        IO.puts("TestAdapter - Response is already a map: #{inspect(resp)}")
        resp
      _ -> 
        IO.puts("TestAdapter - Unknown response type: #{inspect(response)}")
        %{}
    end
    
    case parsed_response do
      %{"type" => "auth_success"} ->
        IO.puts("TestAdapter - Auth success response detected")
        updated_state = adapter_state
          |> Map.put(:auth_status, :authenticated)
          |> Map.put(:token, Map.get(parsed_response, "token"))
        {:ok, %{conn | adapter_state: updated_state}}
      _ ->
        IO.puts("TestAdapter - Auth failed, response doesn't match expected format")
        {:error, :auth_failed, conn}
    end
  end

  @impl WebsockexNova.Behaviors.AuthHandler
  def authenticate(conn, _credentials, _options), do: {:ok, conn}

  @impl WebsockexNova.Behaviors.AuthHandler
  def needs_reauthentication?(_), do: false
end