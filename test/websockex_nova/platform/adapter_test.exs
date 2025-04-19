defmodule WebsockexNova.Platform.AdapterTest do
  use ExUnit.Case, async: true

  # Define a mock implementation of the PlatformAdapter
  defmodule MockPlatformAdapter do
    @moduledoc false
    use WebsockexNova.Platform.Adapter,
      default_host: "wss://mock.example.com",
      default_port: 443

    @impl true
    def init(opts) do
      # Call parent implementation first to get default configuration
      {:ok, state} = super(opts)

      # Customize initialization for mock adapter
      state = Map.put(state, :adapter_type, :mock)
      {:ok, state}
    end

    @impl true
    def handle_platform_message(message, state) when is_map(message) do
      # Mock implementation for handling platform-specific messages
      case message do
        %{"type" => "ping"} ->
          response = %{"type" => "pong", "timestamp" => to_string(DateTime.utc_now())}
          {:reply, {:text, Jason.encode!(response)}, state}

        %{"type" => "subscribe", "channel" => channel} ->
          response = %{"type" => "subscription", "channel" => channel, "status" => "success"}
          {:reply, {:text, Jason.encode!(response)}, state}

        %{"type" => "error", "code" => code} ->
          {:error, %{reason: "Platform error: #{code}"}, state}

        _ ->
          {:noreply, state}
      end
    end

    @impl true
    def encode_auth_request(credentials) do
      # Mock auth encoding
      {:text,
       Jason.encode!(%{
         "type" => "auth",
         "api_key" => credentials.api_key,
         "timestamp" => to_string(DateTime.utc_now())
       })}
    end

    @impl true
    def encode_subscription_request(channel, params) do
      # Mock subscription encoding
      {:text,
       Jason.encode!(%{
         "type" => "subscribe",
         "channel" => channel,
         "params" => params
       })}
    end

    @impl true
    def encode_unsubscription_request(channel) do
      # Mock unsubscription encoding
      {:text,
       Jason.encode!(%{
         "type" => "unsubscribe",
         "channel" => channel
       })}
    end
  end

  # Test setup
  setup do
    # Mock configuration
    config = %{
      host: "wss://test.example.com",
      port: 8080,
      api_key: "test_key",
      api_secret: "test_secret"
    }

    {:ok, config: config}
  end

  describe "Adapter initialization and configuration" do
    test "uses default configuration when not specified", %{config: config} do
      # Setup partial config without host/port
      partial_config = Map.drop(config, [:host, :port])
      {:ok, state} = MockPlatformAdapter.init(partial_config)

      # Should use default host and port
      assert state.host == "wss://mock.example.com"
      assert state.port == 443
    end

    test "overrides default configuration with provided values", %{config: config} do
      {:ok, state} = MockPlatformAdapter.init(config)

      # Should use provided host and port
      assert state.host == "wss://test.example.com"
      assert state.port == 8080
    end

    test "adds adapter type to configuration" do
      {:ok, state} = MockPlatformAdapter.init(%{})
      assert state.adapter_type == :mock
    end
  end

  describe "Behavior implementations" do
    test "encodes authentication request" do
      auth_credentials = %{api_key: "test_key", api_secret: "test_secret"}
      encoded = MockPlatformAdapter.encode_auth_request(auth_credentials)

      assert match?({:text, _}, encoded)
      {:text, json} = encoded
      decoded = Jason.decode!(json)

      assert decoded["type"] == "auth"
      assert decoded["api_key"] == "test_key"
      assert is_binary(decoded["timestamp"])
    end

    test "encodes subscription request" do
      channel = "orderbook.BTC-USD"
      params = %{depth: 10}
      encoded = MockPlatformAdapter.encode_subscription_request(channel, params)

      assert match?({:text, _}, encoded)
      {:text, json} = encoded
      decoded = Jason.decode!(json)

      assert decoded["type"] == "subscribe"
      assert decoded["channel"] == "orderbook.BTC-USD"
      assert decoded["params"] == %{"depth" => 10}
    end

    test "encodes unsubscription request" do
      channel = "orderbook.BTC-USD"
      encoded = MockPlatformAdapter.encode_unsubscription_request(channel)

      assert match?({:text, _}, encoded)
      {:text, json} = encoded
      decoded = Jason.decode!(json)

      assert decoded["type"] == "unsubscribe"
      assert decoded["channel"] == "orderbook.BTC-USD"
    end

    test "handles platform-specific messages - ping" do
      state = %{test: "state"}
      message = %{"type" => "ping"}

      {:reply, {:text, response_json}, returned_state} =
        MockPlatformAdapter.handle_platform_message(message, state)

      response = Jason.decode!(response_json)
      assert response["type"] == "pong"
      assert is_binary(response["timestamp"])
      assert returned_state == state
    end

    test "handles platform-specific messages - subscription" do
      state = %{test: "state"}
      message = %{"type" => "subscribe", "channel" => "trades.BTC-USD"}

      {:reply, {:text, response_json}, returned_state} =
        MockPlatformAdapter.handle_platform_message(message, state)

      response = Jason.decode!(response_json)
      assert response["type"] == "subscription"
      assert response["channel"] == "trades.BTC-USD"
      assert response["status"] == "success"
      assert returned_state == state
    end

    test "handles platform-specific messages - error" do
      state = %{test: "state"}
      message = %{"type" => "error", "code" => 429}

      {:error, error_info, returned_state} =
        MockPlatformAdapter.handle_platform_message(message, state)

      assert error_info.reason == "Platform error: 429"
      assert returned_state == state
    end

    test "handles unknown platform messages" do
      state = %{test: "state"}
      message = %{"type" => "unknown"}

      {:noreply, returned_state} =
        MockPlatformAdapter.handle_platform_message(message, state)

      assert returned_state == state
    end
  end

  describe "Integration with other behaviors" do
    test "can work with ConnectionHandler" do
      # This test verifies that our adapter implementation works correctly
      # with the ConnectionHandler behavior
      defmodule TestConnectionHandler do
        @moduledoc false
        @behaviour WebsockexNova.Behaviors.ConnectionHandler

        def init(state), do: {:ok, state}

        def handle_connect(_conn_info, state) do
          send(self(), {:connected})
          {:ok, state}
        end

        def handle_disconnect(_reason, state) do
          send(self(), {:disconnected})
          {:reconnect, state}
        end

        def handle_frame(frame_type, frame_data, state) do
          send(self(), {:frame, frame_type, frame_data})
          {:ok, state}
        end
      end

      # Verify our mock adapter can be used with the ConnectionHandler
      state = %{connection_handler: TestConnectionHandler}

      # Simulate connection event
      {:ok, _state} = TestConnectionHandler.handle_connect(%{}, state)
      assert_received {:connected}

      # Simulate frame event
      message = %{"type" => "ping"}
      {:reply, response, _state} = MockPlatformAdapter.handle_platform_message(message, state)
      {:ok, _state} = TestConnectionHandler.handle_frame(:text, response, state)
      assert_received {:frame, :text, _}
    end

    test "can work with MessageHandler" do
      # This test verifies that our adapter implementation works correctly
      # with the MessageHandler behavior
      defmodule TestMessageHandler do
        @moduledoc false
        @behaviour WebsockexNova.Behaviors.MessageHandler

        def handle_message(message, state) do
          send(self(), {:message, message})
          {:ok, state}
        end

        def validate_message(message) do
          if Map.has_key?(message, "type"), do: {:ok, message}, else: {:error, :invalid_message}
        end

        def message_type(message) do
          Map.get(message, "type", "unknown")
        end

        def encode_message(type, payload) do
          {:text, Jason.encode!(%{"type" => type, "payload" => payload})}
        end
      end

      # Verify our mock adapter can be used with the MessageHandler
      state = %{message_handler: TestMessageHandler}

      # Generate a message using the adapter
      message = %{"type" => "subscribe", "channel" => "trades.BTC-USD"}

      # Handle it through the message handler
      parsed_message = message |> Jason.encode!() |> Jason.decode!()
      {:ok, _state} = TestMessageHandler.handle_message(parsed_message, state)
      assert_received {:message, ^parsed_message}

      # Verify the message handler's encoding can be used with adapter
      {:text, encoded} = TestMessageHandler.encode_message("heartbeat", %{id: 123})
      decoded = Jason.decode!(encoded)
      assert decoded["type"] == "heartbeat"
      assert decoded["payload"] == %{"id" => 123}
    end
  end
end
