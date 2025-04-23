defmodule WebsockexNova.Examples.DeribitClient do
  @moduledoc """
  Minimal client for the Deribit WebSocket API v2 using DeribitAdapter.
  Allows connecting, sending messages, registering callback processes, and authenticating.

  Reads DERIBIT_CLIENT_ID and DERIBIT_CLIENT_SECRET from the environment for authentication.
  Use WebsockexNova.Client.authenticate/2 for authentication.
  """

  alias WebsockexNova.Client
  alias WebsockexNova.Examples.DeribitAdapter

  require Logger

  @doc """
  Starts a Deribit WebSocket client session.

  Returns {:ok, conn} on success.
  """
  def start do
    Logger.info("Connecting to Deribit WebSocket API v2...")

    case DeribitAdapter.connection_info(%{}) do
      {:ok, connection_info} ->
        Client.connect(DeribitAdapter, connection_info)
    end
  end

  @doc """
  Sends a text message to Deribit.
  """
  def send_message(conn, message) when is_binary(message) do
    Logger.info("Sending message: #{inspect(message)}")
    Client.send_text(conn, message)
  end

  @doc """
  Registers a process to receive Deribit WebSocket messages.
  Defaults to the current process.
  """
  def register_callback(conn, pid \\ self()) do
    Client.register_callback(conn, pid)
  end

  @doc """
  Returns the Deribit client ID from the environment.
  """
  def client_id do
    System.get_env("DERIBIT_CLIENT_ID")
  end

  @doc """
  Returns the Deribit client secret from the environment.
  """
  def client_secret do
    System.get_env("DERIBIT_CLIENT_SECRET")
  end
end
