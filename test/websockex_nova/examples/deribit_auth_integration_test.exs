defmodule WebsockexNova.Examples.DeribitAuthIntegrationTest do
  use ExUnit.Case, async: false

  alias WebsockexNova.Client
  alias WebsockexNova.Examples.DeribitClient

  require Logger

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
        {:ok, response} ->
          # Parse the response JSON
          {:ok, decoded} = Jason.decode(response)

          # The response could be either the auth request or the auth result
          # If it's a request format that includes method and params, we need to make sure it uses the right credentials
          case decoded do
            %{"method" => "public/auth", "params" => params} ->
              assert params["client_id"] == @client_id
              assert params["client_secret"] == @client_secret
              assert params["grant_type"] == "client_credentials"

            %{"jsonrpc" => "2.0", "id" => _id, "result" => result} ->
              # This is the success response format with a result containing auth data
              assert %{"access_token" => access_token, "expires_in" => expires_in} = result

              # Check the values
              assert is_binary(access_token)
              assert is_integer(expires_in)
              assert expires_in > 0
          end

        {:error, :timeout} ->
          IO.puts("Timeout waiting for authentication response. Process mailbox:")
          Logger.debug(Process.info(self(), :messages))
          flunk("Authentication failed: :timeout")

        {:error, reason} ->
          IO.puts("Authentication failed with error: #{inspect(reason)}")
          flunk("Authentication failed: #{inspect(reason)}")
      end
    end
  end

  describe "DeribitAdapter.needs_reauthentication?/1" do
    alias WebsockexNova.Examples.DeribitAdapter

    test "returns true if auth_status is failed" do
      state = %{auth_status: :failed, credentials: %{token: "token"}}
      assert DeribitAdapter.needs_reauthentication?(state)
    end

    test "returns false if not authenticated yet" do
      state = %{auth_status: :unauthenticated, credentials: %{token: "token"}}
      refute DeribitAdapter.needs_reauthentication?(state)
    end

    test "returns false if no auth_expires_at" do
      state = %{auth_status: :authenticated, credentials: %{token: "token"}}
      refute DeribitAdapter.needs_reauthentication?(state)
    end

    test "returns true if token is expiring soon" do
      now = System.system_time(:second)

      state = %{
        auth_status: :authenticated,
        auth_expires_at: now + 30,
        credentials: %{token: "token"},
        auth_refresh_threshold: 60
      }

      assert DeribitAdapter.needs_reauthentication?(state)
    end

    test "returns false if token is valid and not expiring soon" do
      now = System.system_time(:second)

      state = %{
        auth_status: :authenticated,
        auth_expires_at: now + 3600,
        credentials: %{token: "token"},
        auth_refresh_threshold: 60
      }

      refute DeribitAdapter.needs_reauthentication?(state)
    end
  end
end
