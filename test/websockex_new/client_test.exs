defmodule WebsockexNew.ClientTest do
  use ExUnit.Case

  alias WebsockexNew.{Client, Config}

  @deribit_test_url "wss://test.deribit.com/ws/api/v2"

  test "connect to test.deribit.com with URL string" do
    {:ok, client} = Client.connect(@deribit_test_url)

    assert client.gun_pid != nil
    assert client.stream_ref != nil
    assert client.state == :connecting
    assert client.url == @deribit_test_url

    Client.close(client)
  end

  test "connect with config struct" do
    {:ok, config} = Config.new(@deribit_test_url, timeout: 10_000)
    {:ok, client} = Client.connect(config)

    assert client.gun_pid != nil
    assert client.stream_ref != nil
    assert client.state == :connecting
    assert client.url == @deribit_test_url

    Client.close(client)
  end

  test "connect with invalid URL returns error" do
    {:error, "Invalid URL format"} = Client.connect("http://example.com")
  end

  test "connect with invalid config options returns error" do
    {:error, "Timeout must be positive"} = Client.connect(@deribit_test_url, timeout: 0)
  end

  test "get_state returns current state" do
    {:ok, client} = Client.connect(@deribit_test_url)

    assert Client.get_state(client) == :connecting

    Client.close(client)
  end

  test "send_message when not connected returns error" do
    {:ok, client} = Client.connect(@deribit_test_url)

    result = Client.send_message(client, "test")
    assert {:error, {:not_connected, :connecting}} == result

    Client.close(client)
  end

  test "subscribe formats message correctly" do
    {:ok, client} = Client.connect(@deribit_test_url)

    result = Client.subscribe(client, ["deribit_price_index.btc_usd"])
    assert {:error, {:not_connected, :connecting}} == result

    Client.close(client)
  end
end
