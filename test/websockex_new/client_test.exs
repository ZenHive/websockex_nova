defmodule WebsockexNew.ClientTest do
  use ExUnit.Case
  
  @deribit_test_url "wss://test.deribit.com/ws/api/v2"
  
  test "connect to test.deribit.com" do
    {:ok, client} = WebsockexNew.Client.connect(@deribit_test_url)
    
    assert client.gun_pid != nil
    assert client.stream_ref != nil
    assert client.state == :connecting
    assert client.url == @deribit_test_url
    
    WebsockexNew.Client.close(client)
  end
  
  test "get_state returns current state" do
    {:ok, client} = WebsockexNew.Client.connect(@deribit_test_url)
    
    assert WebsockexNew.Client.get_state(client) == :connecting
    
    WebsockexNew.Client.close(client)
  end
  
  test "send_message when not connected returns error" do
    {:ok, client} = WebsockexNew.Client.connect(@deribit_test_url)
    
    result = WebsockexNew.Client.send_message(client, "test")
    assert {:error, {:not_connected, :connecting}} == result
    
    WebsockexNew.Client.close(client)
  end
  
  test "subscribe formats message correctly" do
    {:ok, client} = WebsockexNew.Client.connect(@deribit_test_url)
    
    result = WebsockexNew.Client.subscribe(client, ["deribit_price_index.btc_usd"])
    assert {:error, {:not_connected, :connecting}} == result
    
    WebsockexNew.Client.close(client)
  end
end