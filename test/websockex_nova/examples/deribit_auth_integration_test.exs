defmodule WebsockexNova.Examples.DeribitAuthIntegrationTest do
  use ExUnit.Case, async: false

  alias WebsockexNova.Client
  alias WebsockexNova.Examples.DeribitClient

  @moduletag :integration

  @deribit_host System.get_env("DERIBIT_HOST", "test.deribit.com")
  @client_id System.get_env("DERIBIT_CLIENT_ID")
  @client_secret System.get_env("DERIBIT_CLIENT_SECRET")

  @tag :external
  test "connects to the correct Deribit testnet host" do
    # Use the adapter directly to check connection info
    {:ok, info} = WebsockexNova.Examples.DeribitAdapter.connection_info(%{})
    assert info.host == @deribit_host
    assert info.port == 443
    assert info.path == "/ws/api/v2"
  end

  @tag :external
  test "authenticates and receives a valid access token" do
    # Skip if credentials are not set
    if is_nil(@client_id) or is_nil(@client_secret) do
      IO.puts("DERIBIT_CLIENT_ID and DERIBIT_CLIENT_SECRET must be set for this test.")
      :ok
    else
      {:ok, conn} = DeribitClient.start()
      {:ok, _conn} = DeribitClient.register_callback(conn, self())
      :timer.sleep(50)

      credentials = %{
        "client_id" => @client_id,
        "client_secret" => @client_secret
      }

      case Client.authenticate(conn, credentials) do
        {:ok, _auth_data, new_state} ->
          assert is_binary(new_state.access_token)
          assert is_integer(new_state.expires_in) and new_state.expires_in > 0

        {:error, :timeout} ->
          IO.puts("Timeout waiting for authentication response. Process mailbox:")
          IO.inspect(Process.info(self(), :messages))
          flunk("Authentication failed: :timeout")

        {:error, reason} ->
          IO.puts("Authentication failed with error: #{inspect(reason)}")
          flunk("Authentication failed: #{inspect(reason)}")
      end
    end
  end
end
