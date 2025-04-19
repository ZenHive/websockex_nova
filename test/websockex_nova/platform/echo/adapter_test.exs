defmodule WebsockexNova.Platform.Echo.AdapterTest do
  use ExUnit.Case, async: true

  alias WebsockexNova.Platform.Echo.Adapter, as: EchoAdapter

  describe "initialization" do
    test "uses default configuration values" do
      {:ok, state} = EchoAdapter.init(%{})

      assert state.host == "wss://echo.websocket.org"
      assert state.port == 443
      assert state.adapter_type == :echo
      assert state.echo_prefix == "ECHO: "
      assert state.subscriptions == []
    end

    test "allows custom echo prefix" do
      {:ok, state} = EchoAdapter.init(%{echo_prefix: "TEST: "})

      assert state.echo_prefix == "TEST: "
    end

    test "overrides defaults with provided values" do
      custom_config = %{
        host: "wss://custom.example.com",
        port: 8000,
        echo_prefix: "CUSTOM: "
      }

      {:ok, state} = EchoAdapter.init(custom_config)

      assert state.host == "wss://custom.example.com"
      assert state.port == 8000
      assert state.echo_prefix == "CUSTOM: "
    end
  end

  describe "handle_platform_message/2" do
    setup do
      {:ok, state} = EchoAdapter.init(%{})
      {:ok, state: state}
    end

    test "echoes plain text with prefix", %{state: state} do
      message = "Hello World"

      {:reply, {:text, response}, ^state} = EchoAdapter.handle_platform_message(message, state)

      assert response == "ECHO: Hello World"
    end

    test "handles ping messages", %{state: state} do
      message = %{"type" => "ping"}

      {:reply, {:text, response_json}, ^state} = EchoAdapter.handle_platform_message(message, state)

      response = Jason.decode!(response_json)
      assert response["type"] == "pong"
      assert is_binary(response["time"])
    end

    test "handles echo message with specific content", %{state: state} do
      message = %{"type" => "echo", "message" => "Test message"}

      {:reply, {:text, response_json}, ^state} = EchoAdapter.handle_platform_message(message, state)

      response = Jason.decode!(response_json)
      assert response["type"] == "echo_response"
      assert response["original"] == "Test message"
      assert response["echo"] == "ECHO: Test message"
    end

    test "handles authentication success", %{state: state} do
      message = %{"type" => "auth", "success" => true}

      {:ok, updated_state} = EchoAdapter.handle_platform_message(message, state)

      assert updated_state.authenticated == true
    end

    test "handles subscription requests", %{state: state} do
      message = %{"type" => "subscribe", "channel" => "test-channel"}

      {:reply, {:text, response_json}, updated_state} =
        EchoAdapter.handle_platform_message(message, state)

      response = Jason.decode!(response_json)
      assert response["type"] == "subscription"
      assert response["channel"] == "test-channel"
      assert response["status"] == "subscribed"
      assert "test-channel" in updated_state.subscriptions
    end

    test "handles unsubscription requests", %{state: state} do
      # First subscribe
      state_with_sub = %{state | subscriptions: ["test-channel"]}

      # Then unsubscribe
      message = %{"type" => "unsubscribe", "channel" => "test-channel"}

      {:reply, {:text, response_json}, updated_state} =
        EchoAdapter.handle_platform_message(message, state_with_sub)

      response = Jason.decode!(response_json)
      assert response["type"] == "subscription"
      assert response["channel"] == "test-channel"
      assert response["status"] == "unsubscribed"
      assert updated_state.subscriptions == []
    end

    test "handles error messages", %{state: state} do
      message = %{"type" => "error", "reason" => "Test error", "code" => 123}

      {:error, error_info, ^state} = EchoAdapter.handle_platform_message(message, state)

      assert error_info.reason == "Test error"
      assert error_info.code == 123
    end

    test "echoes unknown message types", %{state: state} do
      message = %{"action" => "unknown", "data" => "test"}

      {:reply, {:text, response_json}, ^state} = EchoAdapter.handle_platform_message(message, state)

      response = Jason.decode!(response_json)
      assert response["action"] == "unknown"
      assert response["data"] == "test"
      assert response["echo"] == true
    end
  end

  describe "encode_auth_request/1" do
    test "formats authentication request" do
      credentials = %{api_key: "test-key", api_secret: "test-secret"}

      {:text, auth_json} = EchoAdapter.encode_auth_request(credentials)

      auth = Jason.decode!(auth_json)
      assert auth["type"] == "auth"
      assert auth["api_key"] == "test-key"
      assert auth["echo_auth"] == true
      assert is_binary(auth["timestamp"])
    end

    test "handles missing credentials" do
      {:text, auth_json} = EchoAdapter.encode_auth_request(%{})

      auth = Jason.decode!(auth_json)
      assert auth["type"] == "auth"
      assert auth["api_key"] == ""
    end
  end

  describe "encode_subscription_request/2" do
    test "formats subscription request with parameters" do
      channel = "test-channel"
      params = %{depth: 10, frequency: "100ms"}

      {:text, sub_json} = EchoAdapter.encode_subscription_request(channel, params)

      sub = Jason.decode!(sub_json)
      assert sub["type"] == "subscribe"
      assert sub["channel"] == "test-channel"
      assert sub["params"]["depth"] == 10
      assert sub["params"]["frequency"] == "100ms"
      assert is_binary(sub["timestamp"])
    end

    test "handles nil parameters" do
      channel = "test-channel"

      {:text, sub_json} = EchoAdapter.encode_subscription_request(channel, nil)

      sub = Jason.decode!(sub_json)
      assert sub["type"] == "subscribe"
      assert sub["channel"] == "test-channel"
      assert sub["params"] == %{}
    end
  end

  describe "encode_unsubscription_request/1" do
    test "formats unsubscription request" do
      channel = "test-channel"

      {:text, unsub_json} = EchoAdapter.encode_unsubscription_request(channel)

      unsub = Jason.decode!(unsub_json)
      assert unsub["type"] == "unsubscribe"
      assert unsub["channel"] == "test-channel"
      assert is_binary(unsub["timestamp"])
    end
  end
end
