defmodule WebsockexNew.ReconnectionTest do
  use ExUnit.Case

  alias WebsockexNew.Config
  alias WebsockexNew.Reconnection
  alias WebsockexNova.Test.Support.MockWebSockServer

  @deribit_test_url "wss://test.deribit.com/ws/api/v2"

  describe "exponential backoff" do
    test "calculate_delay/2 returns exponential backoff" do
      assert Reconnection.calculate_delay(0, 1000) == 1000
      assert Reconnection.calculate_delay(1, 1000) == 2000
      assert Reconnection.calculate_delay(2, 1000) == 4000
      assert Reconnection.calculate_delay(3, 1000) == 8000
    end

    test "calculate_delay/2 caps at maximum delay" do
      delay = Reconnection.calculate_delay(10, 1000)
      assert delay == 30_000
    end
  end

  describe "reconnection logic" do
    test "reconnect/3 succeeds on first attempt with valid config" do
      {:ok, config} = Config.new(@deribit_test_url, retry_count: 3)

      {:ok, client} = Reconnection.reconnect(config, 0, [])

      assert client.gun_pid != nil
      assert client.state == :connecting

      WebsockexNew.Client.close(client)
    end

    test "reconnect/3 returns max_retries error when attempt limit reached" do
      # Test the logic directly by starting at max attempts
      {:ok, config} = Config.new(@deribit_test_url, retry_count: 2)

      {:error, :max_retries} = Reconnection.reconnect(config, 2, [])
    end

    test "should_reconnect?/2 returns correct boolean" do
      assert Reconnection.should_reconnect?(0, 3) == true
      assert Reconnection.should_reconnect?(2, 3) == true
      assert Reconnection.should_reconnect?(3, 3) == false
      assert Reconnection.should_reconnect?(5, 3) == false
    end
  end

  describe "subscription restoration" do
    test "restore_subscriptions/2 handles empty subscription list" do
      {:ok, config} = Config.new(@deribit_test_url)
      {:ok, client} = WebsockexNew.Client.connect(config)

      :ok = Reconnection.restore_subscriptions(client, [])

      WebsockexNew.Client.close(client)
    end

    test "restore_subscriptions/2 attempts to restore subscriptions" do
      {:ok, config} = Config.new(@deribit_test_url)
      {:ok, client} = WebsockexNew.Client.connect(config)

      subscriptions = ["deribit_price_index.btc_usd"]
      :ok = Reconnection.restore_subscriptions(client, subscriptions)

      WebsockexNew.Client.close(client)
    end

    test "restore_subscriptions/2 with mock server" do
      {:ok, server_pid, port} = MockWebSockServer.start_link()

      {:ok, config} = Config.new("ws://localhost:#{port}/ws")
      {:ok, client} = WebsockexNew.Client.connect(config)

      subscriptions = ["test_channel"]
      :ok = Reconnection.restore_subscriptions(client, subscriptions)

      WebsockexNew.Client.close(client)
      MockWebSockServer.stop(server_pid)
    end
  end
end
