defmodule WebsockexNova.Examples.ClientDeribit do
  @moduledoc """
  Deribit-specific client API, wrapping WebsockexNova.Client with the Deribit adapter.

  Provides a user-friendly, domain-specific interface for connecting, authenticating,
  and subscribing to Deribit WebSocket channels.
  """

  alias WebsockexNova.Client
  alias WebsockexNova.Examples.AdapterDeribit

  @doc """
  Connect to Deribit WebSocket API with sensible defaults.
  """
  def connect(opts \\ %{}) do
    Client.connect(AdapterDeribit, opts)
  end

  @doc """
  Authenticate using client credentials (from opts or environment).
  """
  def authenticate(conn, credentials \\ %{}, opts \\ nil) do
    Client.authenticate(conn, credentials, opts)
  end

  @doc """
  Subscribe to a Deribit trades channel for a given instrument (e.g., "BTC-PERPETUAL").
  """
  def subscribe_to_trades(conn, instrument, opts \\ nil) do
    channel = "trades.#{instrument}.raw"
    Client.subscribe(conn, channel, opts)
  end

  @doc """
  Subscribe to a Deribit ticker channel for a given instrument (e.g., "BTC-PERPETUAL").
  """
  def subscribe_to_ticker(conn, instrument, opts \\ nil) do
    channel = "ticker.#{instrument}.raw"
    Client.subscribe(conn, channel, opts)
  end

  @doc """
  Send a custom JSON-RPC payload to Deribit.
  """
  def send_json(conn, payload, opts \\ nil) do
    Client.send_json(conn, payload, opts)
  end

  # Add more Deribit-specific helpers as needed...
end
