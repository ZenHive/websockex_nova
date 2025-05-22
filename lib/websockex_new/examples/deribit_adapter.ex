defmodule WebsockexNew.Examples.DeribitAdapter do
  @moduledoc """
  Deribit WebSocket API adapter for WebsockexNew.

  Handles Deribit-specific functionality:
  - Authentication flow
  - Subscription management
  - Message format handling
  - Heartbeat responses
  """

  alias WebsockexNew.Client
  alias WebsockexNew.MessageHandler

  defstruct [:client, :authenticated, :subscriptions, :client_id, :client_secret]

  @type t :: %__MODULE__{
          client: Client.t(),
          authenticated: boolean(),
          subscriptions: MapSet.t(),
          client_id: String.t() | nil,
          client_secret: String.t() | nil
        }

  @deribit_test_url "wss://test.deribit.com/ws/api/v2"

  @doc """
  Connect to Deribit WebSocket API with optional authentication.
  """
  @spec connect(keyword()) :: {:ok, t()} | {:error, term()}
  def connect(opts \\ []) do
    client_id = Keyword.get(opts, :client_id)
    client_secret = Keyword.get(opts, :client_secret)
    url = Keyword.get(opts, :url, @deribit_test_url)

    case Client.connect(url) do
      {:ok, client} ->
        adapter = %__MODULE__{
          client: client,
          authenticated: false,
          subscriptions: MapSet.new(),
          client_id: client_id,
          client_secret: client_secret
        }

        {:ok, adapter}

      error ->
        error
    end
  end

  @doc """
  Authenticate with Deribit using client credentials.
  """
  @spec authenticate(t()) :: {:ok, t()} | {:error, term()}
  def authenticate(%__MODULE__{client_id: nil}), do: {:error, :missing_credentials}

  def authenticate(%__MODULE__{client: client, client_id: client_id, client_secret: client_secret} = adapter) do
    auth_message =
      Jason.encode!(%{
        jsonrpc: "2.0",
        id: :erlang.unique_integer([:positive]),
        method: "public/auth",
        params: %{
          grant_type: "client_credentials",
          client_id: client_id,
          client_secret: client_secret
        }
      })

    case Client.send_message(client, auth_message) do
      :ok ->
        {:ok, %{adapter | authenticated: true}}

      error ->
        error
    end
  end

  @doc """
  Subscribe to Deribit channels.
  """
  @spec subscribe(t(), list(String.t())) :: {:ok, t()} | {:error, term()}
  def subscribe(%__MODULE__{client: client, subscriptions: subs} = adapter, channels) when is_list(channels) do
    subscription_message =
      Jason.encode!(%{
        jsonrpc: "2.0",
        id: :erlang.unique_integer([:positive]),
        method: "public/subscribe",
        params: %{
          channels: channels
        }
      })

    case Client.send_message(client, subscription_message) do
      :ok ->
        new_subs = Enum.reduce(channels, subs, &MapSet.put(&2, &1))
        {:ok, %{adapter | subscriptions: new_subs}}

      error ->
        error
    end
  end

  @doc """
  Unsubscribe from Deribit channels.
  """
  @spec unsubscribe(t(), list(String.t())) :: {:ok, t()} | {:error, term()}
  def unsubscribe(%__MODULE__{client: client, subscriptions: subs} = adapter, channels) when is_list(channels) do
    unsubscription_message =
      Jason.encode!(%{
        jsonrpc: "2.0",
        id: :erlang.unique_integer([:positive]),
        method: "public/unsubscribe",
        params: %{
          channels: channels
        }
      })

    case Client.send_message(client, unsubscription_message) do
      :ok ->
        new_subs = Enum.reduce(channels, subs, &MapSet.delete(&2, &1))
        {:ok, %{adapter | subscriptions: new_subs}}

      error ->
        error
    end
  end

  @doc """
  Handle Deribit-specific messages including heartbeats.
  """
  @spec handle_message(term()) :: :ok | {:response, binary()}
  def handle_message({:text, message}) do
    case Jason.decode(message) do
      {:ok, %{"method" => "heartbeat", "params" => %{"type" => "test_request"}}} ->
        response =
          Jason.encode!(%{
            jsonrpc: "2.0",
            method: "public/test",
            params: %{}
          })

        {:response, response}

      {:ok, decoded} ->
        handle_decoded_message(decoded)

      {:error, _reason} ->
        :ok
    end
  end

  def handle_message(_message), do: :ok

  @doc """
  Create a message handler function for Deribit connections.
  """
  @spec create_message_handler(keyword()) :: function()
  def create_message_handler(opts \\ []) do
    on_message = Keyword.get(opts, :on_message, &default_message_handler/1)
    on_heartbeat = Keyword.get(opts, :on_heartbeat, &default_heartbeat_handler/1)

    MessageHandler.create_handler(
      on_message: fn frame ->
        case handle_message(frame) do
          {:response, response} ->
            on_heartbeat.(response)

          :ok ->
            on_message.(frame)
        end
      end,
      on_upgrade: fn upgrade_info ->
        IO.puts("WebSocket connection upgraded: #{inspect(upgrade_info)}")
      end,
      on_error: fn error ->
        IO.puts("WebSocket error: #{inspect(error)}")
      end
    )
  end

  # Private helper functions

  defp handle_decoded_message(%{"result" => %{"access_token" => _token}} = auth_result) do
    default_auth_handler(auth_result)
    :ok
  end

  defp handle_decoded_message(%{"error" => error} = error_response) do
    handle_error_message(error, error_response)
  end

  defp handle_decoded_message(%{"params" => %{"channel" => _channel, "data" => _data}} = notification) do
    default_message_handler(notification)
    :ok
  end

  defp handle_decoded_message(_message), do: :ok

  defp handle_error_message(%{"code" => code, "message" => message}, full_response) do
    error_data = {:error, {:api_error, code, message}}

    case WebsockexNew.ErrorHandler.handle_error(error_data) do
      :stop ->
        if is_auth_error?(code, message) do
          default_auth_error_handler({:auth_failed, code, message, full_response})
        else
          default_error_handler({:api_error, code, message, full_response})
        end

      _ ->
        default_error_handler({:api_error, code, message, full_response})
    end

    :ok
  end

  defp is_auth_error?(code, message) do
    case code do
      -32_600 -> String.contains?(message, "unauthorized")
      -32_602 -> String.contains?(message, "invalid_credentials")
      _ -> false
    end
  end

  defp default_message_handler(message) do
    IO.puts("Deribit message: #{inspect(message)}")
  end

  defp default_heartbeat_handler(response) do
    IO.puts("Sending heartbeat response: #{response}")
  end

  defp default_auth_handler(auth_result) do
    IO.puts("Authentication result: #{inspect(auth_result)}")
  end

  defp default_auth_error_handler(auth_error) do
    IO.puts("Authentication error: #{inspect(auth_error)}")
  end

  defp default_error_handler(error) do
    IO.puts("API error: #{inspect(error)}")
  end
end
