defmodule WebsockexNova.Defaults.DefaultMessageHandlerTest do
  use ExUnit.Case, async: true

  alias WebsockexNova.Defaults.DefaultMessageHandler

  describe "DefaultMessageHandler.handle_message/2" do
    test "passes through messages without modification" do
      message = %{"type" => "data", "content" => "test"}
      state = %{processed_count: 0}

      assert {:ok, new_state} = DefaultMessageHandler.handle_message(message, state)
      assert new_state.processed_count == 1
      assert new_state.last_message == message
    end

    test "handles error responses" do
      message = %{"type" => "error", "code" => 1001, "message" => "Permission denied"}
      state = %{}

      assert {:error, "Permission denied", new_state} =
               DefaultMessageHandler.handle_message(message, state)

      assert new_state.last_error == message
    end

    test "handles subscription responses" do
      message = %{
        "type" => "subscription",
        "channel" => "updates",
        "status" => "subscribed"
      }

      state = %{}

      assert {:ok, new_state} = DefaultMessageHandler.handle_message(message, state)
      assert new_state.subscriptions == %{"updates" => :subscribed}
    end
  end

  describe "DefaultMessageHandler.validate_message/1" do
    test "validates well-formed JSON messages" do
      json = ~s({"type": "data", "content": "test"})

      assert {:ok, %{"type" => "data", "content" => "test"}} =
               DefaultMessageHandler.validate_message(json)
    end

    test "validates binary messages" do
      binary = <<1, 0, 1, 0>>

      assert {:ok, %{"content" => ^binary, "type" => "binary_data"}} =
               DefaultMessageHandler.validate_message(binary)
    end

    test "validates pre-decoded messages" do
      message = %{"already" => "decoded"}
      assert {:ok, ^message} = DefaultMessageHandler.validate_message(message)
    end

    test "handles invalid JSON" do
      invalid_json = ~s({"broken: json})

      assert {:ok, %{"content" => ^invalid_json, "type" => "binary_data"}} =
               DefaultMessageHandler.validate_message(invalid_json)
    end
  end

  describe "DefaultMessageHandler.message_type/1" do
    test "extracts message type from type field" do
      message = %{"type" => "data"}
      assert DefaultMessageHandler.message_type(message) == :data
    end

    test "extracts message type from method field if no type" do
      message = %{"method" => "subscribe"}
      assert DefaultMessageHandler.message_type(message) == :subscribe
    end

    test "extracts message type from action field if no type or method" do
      message = %{"action" => "ping"}
      assert DefaultMessageHandler.message_type(message) == :ping
    end

    test "uses :unknown for messages without type indicators" do
      message = %{"content" => "test"}
      assert DefaultMessageHandler.message_type(message) == :unknown
    end

    test "handles binary messages" do
      binary = <<1, 0, 1, 0>>
      assert DefaultMessageHandler.message_type(binary) == :unknown
    end
  end

  describe "DefaultMessageHandler.encode_message/2" do
    test "encodes maps as JSON text frames" do
      message = %{type: "request", id: 123, method: "ping"}
      state = %{}

      assert {:ok, :text, encoded} = DefaultMessageHandler.encode_message(message, state)
      assert is_binary(encoded)
      assert Jason.decode!(encoded) == %{"type" => "request", "id" => 123, "method" => "ping"}
    end

    test "passes through binary data unchanged" do
      message = <<1, 2, 3, 4>>
      state = %{}

      assert {:ok, :text, encoded} = DefaultMessageHandler.encode_message(message, state)
      decoded = Jason.decode!(encoded)
      assert decoded["type"] == "raw_data"
      assert decoded["content"] == <<1, 2, 3, 4>>
    end

    test "encodes atom keys in maps" do
      message = %{type: "request", params: %{symbol: "BTC-USD"}}
      state = %{}

      assert {:ok, :text, encoded} = DefaultMessageHandler.encode_message(message, state)
      decoded = Jason.decode!(encoded)
      assert decoded["type"] == "request"
      assert decoded["params"]["symbol"] == "BTC-USD"
    end

    test "handles custom message types through protocol" do
      message = :ping
      state = %{}

      assert {:ok, :text, encoded} = DefaultMessageHandler.encode_message(message, state)
      assert Jason.decode!(encoded) == %{"type" => "ping"}
    end
  end
end
