defmodule WebsockexNova.ClientMacroTest do
  use ExUnit.Case

  # Define test adapter module
  defmodule TestAdapter do
    use WebsockexNova.Adapter

    @moduledoc false
    def connection_info(_opts) do
      {:ok,
       %{
         host: "test.example.com",
         port: 443,
         path: "/ws/test",
         custom_option: "adapter_default"
       }}
    end
  end

  # Define test client using ClientMacro
  defmodule TestClient do
    @moduledoc false
    use WebsockexNova.ClientMacro, adapter: WebsockexNova.ClientMacroTest.TestAdapter

    # Add a domain-specific method
    def subscribe_to_test_channel(conn, channel_id, opts \\ nil) do
      channel = "test_channel.#{channel_id}"
      subscribe(conn, channel, opts)
    end

    # Override default options
    defp default_opts do
      %{
        client_option: "client_default"
      }
    end
  end

  # Simple mock transport module that just returns the options
  defmodule MockTransport do
    @moduledoc false
    def open(_host, _port, _path, opts) do
      {:ok, %WebsockexNova.ClientConn{connection_info: opts}}
    end
  end

  # Simple mock client module for testing subscribe functionality
  defmodule MockClient do
    @moduledoc false
    def subscribe(_conn, channel, _opts) do
      {:ok, "Subscribed to #{channel}"}
    end
  end

  setup do
    # Set our mock transport module in the application environment
    Application.put_env(:websockex_nova, :transport, MockTransport)

    on_exit(fn ->
      # Clean up after tests
      Application.delete_env(:websockex_nova, :transport)
      Application.delete_env(:websockex_nova, :client_module)
    end)

    :ok
  end

  describe "WebsockexNova.ClientMacro" do
    test "connect/1 merges adapter defaults with client defaults and user options" do
      user_opts = %{user_option: "user_value"}

      {:ok, conn} = TestClient.connect(user_opts)

      # Verify option merging priority (user > client > adapter)
      assert conn.connection_info.host == "test.example.com"
      assert conn.connection_info.port == 443
      assert conn.connection_info.path == "/ws/test"
      assert conn.connection_info.custom_option == "adapter_default"
      assert conn.connection_info.client_option == "client_default"
      assert conn.connection_info.user_option == "user_value"
    end

    test "client delegates to configured client module" do
      # Configure our mock client module for this test
      Application.put_env(:websockex_nova, :client_module, MockClient)

      conn = %WebsockexNova.ClientConn{}

      # Call domain-specific method that uses subscribe internally
      result = TestClient.subscribe_to_test_channel(conn, "123")

      # Verify result
      assert result == {:ok, "Subscribed to test_channel.123"}
    end
  end
end
