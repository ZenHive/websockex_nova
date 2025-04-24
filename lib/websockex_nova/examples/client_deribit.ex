defmodule WebsockexNova.Examples.ClientDeribit do
  @moduledoc """
  Deribit-specific client API, wrapping WebsockexNova.Client with the Deribit adapter.

  Provides a user-friendly, domain-specific interface for connecting, authenticating,
  and subscribing to Deribit WebSocket channels.
  """

  alias WebsockexNova.Client
  alias WebsockexNova.Examples.AdapterDeribit

  # This is intentionally left as an empty map to satisfy Dialyzer's type checks.
  # All Deribit protocol-level defaults (host, port, path, transport, etc.) are now set in the adapter.
  # Only add app-level or user-facing defaults here if needed for your application.
  @default_opts %{}

  @doc """
  Connect to Deribit WebSocket API with sensible defaults.
  User-supplied opts override defaults.
  """
  def connect(opts \\ %{}) when is_map(opts) do
    merged_opts = Map.merge(@default_opts, opts)
    Client.connect(AdapterDeribit, merged_opts)
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
