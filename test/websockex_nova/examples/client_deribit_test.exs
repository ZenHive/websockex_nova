defmodule WebsockexNova.Examples.ClientDeribitTest do
  use ExUnit.Case, async: true

  import Mox

  alias WebsockexNova.Examples.ClientDeribit

  setup :verify_on_exit!

  describe "connect/0 and connect/1" do
    test "merges all layers and delegates to Client.connect/2" do
      # Patch Client.connect/2 to return a known value
      stub = fn _adapter, opts -> {:ok, opts} end

      # Patch the Client module for this test
      original = &WebsockexNova.Client.connect/2
      :meck.new(WebsockexNova.Client, [:passthrough])
      :meck.expect(WebsockexNova.Client, :connect, stub)

      # Should merge adapter defaults, client defaults, and user opts
      result = ClientDeribit.connect(%{host: "custom", timeout: 1234})
      assert {:ok, opts} = result
      assert opts[:host] == "custom"
      assert opts[:timeout] == 1234
      assert opts[:port] == 443
      assert opts[:path] == "/ws/api/v2"

      :meck.unload(WebsockexNova.Client)
    end
  end

  describe "authenticate/3" do
    test "delegates to Client.authenticate/3" do
      conn = :fake_conn
      credentials = %{api_key: "a", secret: "b"}
      opts = %{timeout: 1000}
      stub = fn ^conn, ^credentials, ^opts -> :ok end
      :meck.new(WebsockexNova.Client, [:passthrough])
      :meck.expect(WebsockexNova.Client, :authenticate, stub)
      assert :ok == ClientDeribit.authenticate(conn, credentials, opts)
      :meck.unload(WebsockexNova.Client)
    end
  end

  describe "subscribe_to_trades/3" do
    test "delegates to Client.subscribe/3 with correct channel" do
      conn = :fake_conn
      instrument = "BTC-PERPETUAL"
      opts = %{timeout: 1000}
      expected_channel = "trades.BTC-PERPETUAL.raw"
      stub = fn ^conn, ^expected_channel, ^opts -> :ok end
      :meck.new(WebsockexNova.Client, [:passthrough])
      :meck.expect(WebsockexNova.Client, :subscribe, stub)
      assert :ok == ClientDeribit.subscribe_to_trades(conn, instrument, opts)
      :meck.unload(WebsockexNova.Client)
    end
  end

  describe "subscribe_to_ticker/3" do
    test "delegates to Client.subscribe/3 with correct channel" do
      conn = :fake_conn
      instrument = "BTC-PERPETUAL"
      opts = %{timeout: 1000}
      expected_channel = "ticker.BTC-PERPETUAL.raw"
      stub = fn ^conn, ^expected_channel, ^opts -> :ok end
      :meck.new(WebsockexNova.Client, [:passthrough])
      :meck.expect(WebsockexNova.Client, :subscribe, stub)
      assert :ok == ClientDeribit.subscribe_to_ticker(conn, instrument, opts)
      :meck.unload(WebsockexNova.Client)
    end
  end

  describe "send_json/3" do
    test "delegates to Client.send_json/3" do
      conn = :fake_conn
      payload = %{foo: "bar"}
      opts = %{timeout: 1000}
      stub = fn ^conn, ^payload, ^opts -> :ok end
      :meck.new(WebsockexNova.Client, [:passthrough])
      :meck.expect(WebsockexNova.Client, :send_json, stub)
      assert :ok == ClientDeribit.send_json(conn, payload, opts)
      :meck.unload(WebsockexNova.Client)
    end
  end
end
