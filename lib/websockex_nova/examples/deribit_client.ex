defmodule WebsockexNova.Examples.DeribitClient do
  @moduledoc """
  Minimal client for the Deribit WebSocket API v2 using DeribitAdapter.
  Allows connecting, sending messages, and registering callback processes.
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

      other ->
        {:error, {:unexpected_connection_info, other}}
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
end
