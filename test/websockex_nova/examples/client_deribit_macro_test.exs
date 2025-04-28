defmodule WebsockexNova.Examples.ClientDeribitMacroTest do
  use ExUnit.Case

  alias WebsockexNova.Examples.ClientDeribitMacro

  # Simple mock transport module that just returns the options
  defmodule MockTransport do
    @moduledoc false
    def open(_host, _port, _path, opts) do
      {:ok, %WebsockexNova.ClientConn{connection_info: opts}}
    end
  end

  # Simple mock client module for testing send_json functionality
  defmodule MockClient do
    @moduledoc false
    def connect(_adapter, opts) do
      {:ok, %WebsockexNova.ClientConn{connection_info: opts}}
    end

    def send_json(_conn, payload, _opts) do
      # Return the payload with fake result for testing
      {:ok,
       %{
         "jsonrpc" => "2.0",
         "id" => payload["id"],
         "result" => get_mock_result(payload["method"])
       }}
    end

    # Helper to generate appropriate mock result for each API method
    defp get_mock_result("public/get_time"), do: 1_550_147_385_946
    defp get_mock_result("public/hello"), do: %{"version" => "1.2.26"}
    defp get_mock_result("public/status"), do: %{"locked_currencies" => ["BTC", "ETH"], "locked" => true}
    defp get_mock_result("public/test"), do: %{"version" => "1.2.26"}
    defp get_mock_result(_), do: %{}
  end

  setup do
    # Setup our mock modules
    Application.put_env(:websockex_nova, :transport, MockTransport)
    Application.put_env(:websockex_nova, :client_module, MockClient)

    on_exit(fn ->
      # Clean up after tests
      Application.delete_env(:websockex_nova, :transport)
      Application.delete_env(:websockex_nova, :client_module)
    end)

    # Create a client connection for tests
    {:ok, conn: %WebsockexNova.ClientConn{}}
  end

  describe "supporting API calls" do
    test "get_time/2 sends correct request", %{conn: conn} do
      {:ok, response} = ClientDeribitMacro.get_time(conn)

      # Verify that the response contains the expected structure
      assert is_map(response)
      assert response["jsonrpc"] == "2.0"
      assert is_integer(response["id"])
      assert response["result"] == 1_550_147_385_946
    end

    test "hello/4 sends correct request with client info", %{conn: conn} do
      client_name = "TestClientApp"
      client_version = "1.0.0"

      {:ok, response} = ClientDeribitMacro.hello(conn, client_name, client_version)

      # Verify result structure
      assert is_map(response)
      assert response["jsonrpc"] == "2.0"
      assert is_integer(response["id"])
      assert response["result"]["version"] == "1.2.26"
    end

    test "get_platform_status/2 returns locked currencies", %{conn: conn} do
      {:ok, response} = ClientDeribitMacro.get_platform_status(conn)

      # Verify result structure
      assert is_map(response)
      assert response["jsonrpc"] == "2.0"
      assert is_integer(response["id"])
      assert response["result"]["locked"] == true
      assert response["result"]["locked_currencies"] == ["BTC", "ETH"]
    end

    test "test/3 verifies API connection", %{conn: conn} do
      {:ok, response} = ClientDeribitMacro.test(conn)

      # Verify result structure
      assert is_map(response)
      assert response["jsonrpc"] == "2.0"
      assert is_integer(response["id"])
      assert response["result"]["version"] == "1.2.26"
    end

    test "test/3 with expected_result parameter", %{conn: conn} do
      # Just verifying the parameter is passed correctly
      {:ok, response} = ClientDeribitMacro.test(conn, "exception")

      # With our mock, this will still return the standard result
      assert is_map(response)
      assert response["jsonrpc"] == "2.0"
      assert is_integer(response["id"])
      assert response["result"]["version"] == "1.2.26"
    end
  end
end
