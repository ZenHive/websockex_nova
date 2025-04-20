defmodule WebsockexNova.Platform.DeribitAuthenticationTest do
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

  describe "authentication with valid credentials" do
    test "successfully authenticates and receives a token", %{client_id: client_id, client_secret: client_secret} do
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
    end
  end

  describe "authentication with invalid credentials" do
    test "fails to authenticate and returns an error" do
      {:ok, pid} =
        Connection.start_link(
          adapter: Adapter,
          host: "test.deribit.com",
          port: 443,
          path: "/ws/api/v2"
        )

      credentials = %{api_key: "invalid", api_secret: "invalid"}
      reply = Client.authenticate(pid, credentials, 3_000)

      assert {:text, json} = reply
      decoded = Jason.decode!(json)
      assert %{"jsonrpc" => "2.0", "error" => %{"code" => code, "message" => message}} = decoded
      assert is_integer(code)
      assert is_binary(message)
    end
  end
end
