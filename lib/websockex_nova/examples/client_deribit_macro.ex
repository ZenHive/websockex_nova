defmodule WebsockexNova.Examples.ClientDeribitMacro do
  @moduledoc """
  Deribit-specific client API using the ClientMacro.

  This demonstrates how to build a Deribit WebSocket API client with minimal code,
  leveraging the WebsockexNova.ClientMacro.
  """
  use WebsockexNova.ClientMacro, adapter: WebsockexNova.Examples.AdapterDeribit

  # You can override default options if needed
  # defp default_opts do
  #   %{
  #     host: "test.deribit.com"
  #   }
  # end

  @doc """
  Subscribe to a Deribit trades channel for a given instrument (e.g., "BTC-PERPETUAL").
  """
  def subscribe_to_trades(conn, instrument, opts \\ nil) do
    channel = "trades.#{instrument}.raw"
    subscribe(conn, channel, opts)
  end

  @doc """
  Subscribe to a Deribit ticker channel for a given instrument (e.g., "BTC-PERPETUAL").
  """
  def subscribe_to_ticker(conn, instrument, opts \\ nil) do
    channel = "ticker.#{instrument}.raw"
    subscribe(conn, channel, opts)
  end

  @doc """
  Place a market order (buy/sell at market price)
  """
  def place_market_order(conn, %{instrument: instrument, side: side, amount: amount}, opts \\ nil) do
    payload = %{
      "jsonrpc" => "2.0",
      "id" => System.unique_integer([:positive]),
      "method" => "private/#{side}",
      "params" => %{
        "instrument_name" => instrument,
        "amount" => amount,
        "type" => "market"
      }
    }

    send_json(conn, payload, opts)
  end

  @doc """
  Get account summary
  """
  def get_account_summary(conn, currency, opts \\ nil) do
    payload = %{
      "jsonrpc" => "2.0",
      "id" => System.unique_integer([:positive]),
      "method" => "private/get_account_summary",
      "params" => %{
        "currency" => currency
      }
    }

    send_json(conn, payload, opts)
  end

  # Supporting API calls

  @doc """
  Retrieves the current time from Deribit (in milliseconds).

  This is useful for checking clock skew between your software and Deribit's systems.

  ## Example

      {:ok, timestamp} = DeribitClient.get_time(conn)
      # timestamp will be something like 1550147385946
  """
  def get_time(conn, opts \\ nil) do
    payload = %{
      "jsonrpc" => "2.0",
      "id" => System.unique_integer([:positive]),
      "method" => "public/get_time",
      "params" => %{}
    }

    send_json(conn, payload, opts)
  end

  @doc """
  Introduce the client software to Deribit over WebSocket.

  Deribit will also introduce itself in the response.

  ## Parameters

  * `client_name` - Client software name
  * `client_version` - Client software version

  ## Example

      {:ok, response} = DeribitClient.hello(conn, "MyTradingApp", "1.0.0")
      # response will include Deribit's version information
  """
  def hello(conn, client_name, client_version, opts \\ nil) do
    payload = %{
      "jsonrpc" => "2.0",
      "id" => System.unique_integer([:positive]),
      "method" => "public/hello",
      "params" => %{
        "client_name" => client_name,
        "client_version" => client_version
      }
    }

    send_json(conn, payload, opts)
  end

  @doc """
  Get information about locked currencies on the platform.

  ## Example

      {:ok, status} = DeribitClient.get_platform_status(conn)
      # status will include information on locked currencies
  """
  def get_platform_status(conn, opts \\ nil) do
    payload = %{
      "jsonrpc" => "2.0",
      "id" => System.unique_integer([:positive]),
      "method" => "public/status",
      "params" => %{}
    }

    send_json(conn, payload, opts)
  end

  @doc """
  Tests the connection to the API server and returns its version.

  Use to verify API reachability and version.

  ## Parameters

  * `expected_result` - (Optional) If set to "exception", triggers error

  ## Example

      {:ok, version_info} = DeribitClient.test(conn)
      # version_info will include Deribit's API version
  """
  def test(conn, expected_result \\ nil, opts \\ nil) do
    params = if expected_result, do: %{"expected_result" => expected_result}, else: %{}

    payload = %{
      "jsonrpc" => "2.0",
      "id" => System.unique_integer([:positive]),
      "method" => "public/test",
      "params" => params
    }

    send_json(conn, payload, opts)
  end
end
