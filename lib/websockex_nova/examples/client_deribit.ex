defmodule WebsockexNova.Examples.ClientDeribit do
  @moduledoc """
  Deribit-specific client API, wrapping WebsockexNova.Client with the Deribit adapter.

  Provides a user-friendly, domain-specific interface for connecting, authenticating,
  and subscribing to Deribit WebSocket channels.
  """

  alias WebsockexNova.Client
  alias WebsockexNova.Examples.AdapterDeribit

  @default_opts %{
    host: System.get_env("DERIBIT_HOST") || "www.deribit.com",
    port: 443,
    path: "/ws/api/v2",
    headers: [],
    timeout: 10_000,
    transport_opts: %{transport: :tls},
    protocols: [:http],
    retry: 10,
    backoff_type: :exponential,
    base_backoff: 1_000,
    ws_opts: %{},
    rate_limit_handler: WebsockexNova.Defaults.DefaultRateLimitHandler,
    rate_limit_opts: %{
      capacity: 120,
      refill_rate: 10,
      refill_interval: 1_000,
      queue_limit: 200,
      cost_map: %{
        subscription: 5,
        auth: 10,
        query: 1,
        order: 10
      }
    },
    log_level: :info,
    log_format: :plain
  }

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
