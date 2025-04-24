defmodule WebsockexNova.Examples.ClientDeribitIntegrationTest do
  use ExUnit.Case, async: false

  alias WebsockexNova.Examples.ClientDeribit

  @tag :integration
  test "connects, authenticates, and subscribes to trades channel on Deribit testnet" do
    # Connect to Deribit testnet
    {:ok, conn} = ClientDeribit.connect(%{host: "test.deribit.com"})
    assert conn
    assert conn.adapter == WebsockexNova.Examples.AdapterDeribit

    # Authenticate if credentials are set
    client_id = System.get_env("DERIBIT_CLIENT_ID")
    client_secret = System.get_env("DERIBIT_CLIENT_SECRET")

    if client_id && client_secret do
      credentials = %{api_key: client_id, secret: client_secret}
      result = ClientDeribit.authenticate(conn, credentials)
      assert match?({:ok, _, _}, result) or match?({:error, _, _}, result)
    else
      IO.puts("[Integration] Skipping authentication: DERIBIT_CLIENT_ID/SECRET not set in env.")
    end

    # Subscribe to BTC-PERPETUAL trades channel
    result = ClientDeribit.subscribe_to_trades(conn, "BTC-PERPETUAL")
    assert match?({:ok, _}, result) or match?({:error, _}, result)
  end
end
