defmodule WebsockexNova.Examples.DeribitClientTest do
  use ExUnit.Case, async: true

  alias WebsockexNova.Examples.DeribitClient

  describe "DeribitClient minimal integration" do
    test "can connect and register callback" do
      {:ok, conn} = DeribitClient.start()
      assert is_map(conn)
      {:ok, _conn} = DeribitClient.register_callback(conn, self())
    end

    test "can send a text message" do
      {:ok, conn} = DeribitClient.start()
      {:ok, _conn} = DeribitClient.register_callback(conn, self())
      # This will not receive a real response unless connected to Deribit, but should not error
      {:ok, _} = DeribitClient.send_message(conn, ~s({"jsonrpc":"2.0","method":"public/test","id":42}))
    end
  end
end
