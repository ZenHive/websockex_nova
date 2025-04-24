defmodule WebsockexNova.Examples.AdapterDeribitTest do
  use ExUnit.Case, async: true

  alias WebsockexNova.Examples.AdapterDeribit

  describe "connection_info/1" do
    test "returns all required default keys" do
      {:ok, info} = AdapterDeribit.connection_info(%{})
      assert is_map(info)
      assert info[:host]
      assert info[:port]
      assert info[:path]
      assert info[:headers] == []
      assert info[:timeout]
      assert info[:transport_opts]
      assert info[:protocols]
      assert info[:retry]
      assert info[:backoff_type]
      assert info[:base_backoff]
      assert info[:ws_opts]
      assert info[:rate_limit_handler]
      assert info[:rate_limit_opts]
      assert info[:log_level]
      assert info[:log_format]
    end

    test "merges user opts over defaults" do
      {:ok, info} = AdapterDeribit.connection_info(%{host: "custom", timeout: 1234, log_level: :debug})
      assert info[:host] == "custom"
      assert info[:timeout] == 1234
      assert info[:log_level] == :debug
    end
  end

  describe "generate_auth_data/1" do
    test "returns encoded payload and updates state" do
      state = %{}
      {:ok, payload, new_state} = AdapterDeribit.generate_auth_data(state)
      assert is_binary(payload)
      assert String.contains?(payload, "public/auth")
      assert %{credentials: %{api_key: _, secret: _}} = new_state
    end
  end

  describe "handle_auth_response/2" do
    test "success response updates state" do
      resp = %{"result" => %{"access_token" => "token", "expires_in" => 1000}}
      state = %{}
      {:ok, new_state} = AdapterDeribit.handle_auth_response(resp, state)
      assert new_state[:auth_status] == :authenticated
      assert new_state[:access_token] == "token"
      assert new_state[:auth_expires_in] == 1000
    end

    test "error response updates state" do
      resp = %{"error" => "bad creds"}
      state = %{}
      {:error, "bad creds", new_state} = AdapterDeribit.handle_auth_response(resp, state)
      assert new_state[:auth_status] == :failed
      assert new_state[:auth_error] == "bad creds"
    end

    test "unknown response is a no-op" do
      resp = %{"foo" => "bar"}
      state = %{}
      {:ok, ^state} = AdapterDeribit.handle_auth_response(resp, state)
    end
  end

  describe "subscribe/3" do
    test "returns encoded subscription message" do
      channel = "trades.BTC-PERPETUAL.raw"
      {:ok, payload, state} = AdapterDeribit.subscribe(channel, %{}, %{})
      assert is_binary(payload)
      assert String.contains?(payload, channel)
      assert is_map(state)
    end
  end
end
