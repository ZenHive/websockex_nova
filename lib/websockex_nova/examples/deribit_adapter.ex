defmodule WebsockexNova.Examples.DeribitAdapter do
  @moduledoc """
  Minimal Deribit WebSocket API v2 adapter for demonstration/testing.
  Implements only connection and basic message handling.
  """

  @behaviour WebsockexNova.Behaviors.ConnectionHandler
  @behaviour WebsockexNova.Behaviors.MessageHandler

  alias WebsockexNova.Behaviors.ConnectionHandler
  alias WebsockexNova.Behaviors.MessageHandler

  @host "www.deribit.com"
  @port 443
  @path "/ws/api/v2"

  @impl ConnectionHandler
  def connection_info(_opts) do
    {:ok,
     %{
       host: @host,
       port: @port,
       path: @path,
       headers: [],
       timeout: 30_000,
       transport_opts: %{transport: :tls}
     }}
  end

  @impl ConnectionHandler
  def init(_opts) do
    {:ok, %{messages: [], connected_at: nil}}
  end

  @impl ConnectionHandler
  def handle_connect(conn_info, state) do
    {:ok, %{state | connected_at: System.system_time(:millisecond)}}
  end

  @impl ConnectionHandler
  def handle_disconnect(_reason, state) do
    {:reconnect, state}
  end

  @impl ConnectionHandler
  def handle_frame(:text, data, state) do
    new_state = %{state | messages: [data | state.messages]}
    {:ok, new_state}
  end

  @impl ConnectionHandler
  def handle_frame(_type, _data, state) do
    {:ok, state}
  end

  @impl MessageHandler
  def encode_message(:text, message, _state) when is_binary(message) do
    {:ok, message}
  end

  def encode_message(:json, message, _state) when is_map(message) do
    case Jason.encode(message) do
      {:ok, json} -> {:ok, json}
      {:error, reason} -> {:error, reason}
    end
  end

  def encode_message(_type, message, _state) do
    {:ok, to_string(message)}
  end
end
