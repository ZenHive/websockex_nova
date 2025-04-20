defmodule WebsockexNova.Platform.DeribitSupportingTest do
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

  describe "public API calls" do
    test "can call public/ping and receive pong" do
      {:ok, pid} =
        Connection.start_link(
          adapter: Adapter,
          host: "test.deribit.com",
          port: 443,
          path: "/ws/api/v2"
        )

      req = %{
        "jsonrpc" => "2.0",
        "id" => :os.system_time(:millisecond),
        "method" => "public/ping",
        "params" => %{}
      }

      reply = Client.send_raw(pid, req, 3_000)
      assert {:text, json} = reply
      decoded = Jason.decode!(json)
      assert %{"jsonrpc" => "2.0", "result" => "pong"} = decoded
    end

    test "can call public/get_instruments and receive a list" do
      {:ok, pid} =
        Connection.start_link(
          adapter: Adapter,
          host: "test.deribit.com",
          port: 443,
          path: "/ws/api/v2"
        )

      req = %{
        "jsonrpc" => "2.0",
        "id" => :os.system_time(:millisecond),
        "method" => "public/get_instruments",
        "params" => %{"currency" => "BTC", "kind" => "future"}
      }

      reply = Client.send_raw(pid, req, 5_000)
      assert {:text, json} = reply
      decoded = Jason.decode!(json)
      assert %{"jsonrpc" => "2.0", "result" => instruments} = decoded
      assert is_list(instruments)
    end
  end

  describe "public channel subscriptions" do
    test "can subscribe to ticker channel and receive updates" do
      {:ok, pid} =
        Connection.start_link(
          adapter: Adapter,
          host: "test.deribit.com",
          port: 443,
          path: "/ws/api/v2"
        )

      channel = "ticker.BTC-PERPETUAL.raw"
      params = %{}
      reply = Client.subscribe(pid, channel, params, 3_000)
      assert {:text, json} = reply
      decoded = Jason.decode!(json)
      assert %{"jsonrpc" => "2.0", "result" => %{"subscription" => ^channel}} = decoded

      # Wait for a notification
      receive do
        {:reply, {:text, notification_json}} ->
          notification = Jason.decode!(notification_json)
          assert %{"jsonrpc" => "2.0", "method" => "subscription", "params" => %{"channel" => ^channel}} = notification
      after
        5_000 ->
          flunk("Did not receive ticker update notification in time")
      end
    end
  end

  describe "error handling" do
    test "returns error for malformed request" do
      {:ok, pid} =
        Connection.start_link(
          adapter: Adapter,
          host: "test.deribit.com",
          port: 443,
          path: "/ws/api/v2"
        )

      # Malformed JSON-RPC
      req = %{"foo" => "bar"}
      reply = Client.send_raw(pid, req, 3_000)
      assert {:text, json} = reply
      decoded = Jason.decode!(json)
      assert %{"jsonrpc" => "2.0", "error" => %{"code" => code, "message" => message}} = decoded
      assert is_integer(code)
      assert is_binary(message)
    end
  end
end
