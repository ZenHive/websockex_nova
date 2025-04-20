defmodule WebsockexNova.Platform.DeribitSessionManagementTest do
  use ExUnit.Case, async: false

  alias WebsockexNova.Client
  alias WebsockexNova.Connection
  alias WebsockexNova.Platform.Deribit.Adapter

  @moduletag :integration

  @endpoint "wss://test.deribit.com/ws/api/v2"

  setup do
    client_id = System.get_env("DERIBIT_CLIENT_ID")
    client_secret = System.get_env("DERIBIT_CLIENT_SECRET")

    if is_nil(client_id) or is_nil(client_secret) do
      ExUnit.Case.skip("DERIBIT_CLIENT_ID and DERIBIT_CLIENT_SECRET must be set in ENV for integration tests.")
    else
      {:ok, %{client_id: client_id, client_secret: client_secret}}
    end
  end

  describe "connection lifecycle" do
    test "connects and disconnects cleanly" do
      {:ok, pid} =
        Connection.start_link(
          adapter: Adapter,
          host: "test.deribit.com",
          port: 443,
          path: "/ws/api/v2"
        )

      assert Process.alive?(pid)
      # Terminate the connection
      ref = Process.monitor(pid)
      Process.exit(pid, :normal)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 2_000
    end

    test "can reconnect after disconnect", %{client_id: client_id, client_secret: client_secret} do
      {:ok, pid1} =
        Connection.start_link(
          adapter: Adapter,
          host: "test.deribit.com",
          port: 443,
          path: "/ws/api/v2"
        )

      assert Process.alive?(pid1)
      ref = Process.monitor(pid1)
      Process.exit(pid1, :normal)
      assert_receive {:DOWN, ^ref, :process, ^pid1, :normal}, 2_000

      # Reconnect
      {:ok, pid2} =
        Connection.start_link(
          adapter: Adapter,
          host: "test.deribit.com",
          port: 443,
          path: "/ws/api/v2"
        )

      assert Process.alive?(pid2)
      credentials = %{api_key: client_id, api_secret: client_secret}
      reply = Client.authenticate(pid2, credentials, 3_000)
      assert {:text, json} = reply
      assert %{"jsonrpc" => "2.0", "result" => %{"access_token" => token}} = Jason.decode!(json)
      assert is_binary(token)
    end
  end

  describe "session info queries" do
    test "can query account summary after authentication", %{client_id: client_id, client_secret: client_secret} do
      {:ok, pid} =
        Connection.start_link(
          adapter: Adapter,
          host: "test.deribit.com",
          port: 443,
          path: "/ws/api/v2"
        )

      credentials = %{api_key: client_id, api_secret: client_secret}
      reply = Client.authenticate(pid, credentials, 3_000)
      assert {:text, json} = reply
      assert %{"jsonrpc" => "2.0", "result" => %{"access_token" => token}} = Jason.decode!(json)
      assert is_binary(token)

      # Query account summary (BTC)
      req = %{
        "jsonrpc" => "2.0",
        "id" => :os.system_time(:millisecond),
        "method" => "private/get_account_summary",
        "params" => %{"currency" => "BTC"}
      }

      reply2 = Client.send_raw(pid, req, 3_000)
      assert {:text, json2} = reply2
      decoded = Jason.decode!(json2)
      assert %{"jsonrpc" => "2.0", "result" => %{"currency" => "BTC"}} = decoded
    end
  end
end
