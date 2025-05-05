defmodule WebsockexNova.Behaviours.MessageHandlerTest do
  use ExUnit.Case, async: true

  # Define a mock module that implements the MessageHandler behavior
  defmodule MockMessageHandler do
    @moduledoc false
    @behaviour WebsockexNova.Behaviours.MessageHandler

    def message_init(opts) do
      send(opts[:test_pid], {:message_init, opts})
      {:ok, opts}
    end

    def handle_message(%{"type" => type} = message, state) do
      send(self(), {:handled, type, message})
      {:ok, state}
    end

    def handle_message(message, state) do
      send(self(), {:handled, :unknown, message})
      {:ok, state}
    end

    def validate_message(%{"valid" => true} = message) do
      {:ok, message}
    end

    def validate_message(%{"valid" => false} = message) do
      {:error, :invalid_message, message}
    end

    def validate_message(message) do
      {:error, :unknown_format, message}
    end

    def message_type(%{"type" => type}) do
      type
    end

    def message_type(_message) do
      :unknown
    end

    def encode_message(:heartbeat, _state) do
      {:ok, :text, ~s({"type":"heartbeat"})}
    end

    def encode_message({:subscribe, channel}, _state) do
      {:ok, :text, ~s({"type":"subscribe","channel":"#{channel}"})}
    end

    def encode_message(_type, _state) do
      {:error, :unknown_message_type}
    end
  end

  describe "MessageHandler behavior" do
    setup do
      {:ok, state: %{test: true}}
    end

    test "handle_message/2 processes valid messages", %{state: state} do
      message = %{"type" => "data", "value" => 123}
      assert {:ok, ^state} = MockMessageHandler.handle_message(message, state)
      assert_received {:handled, "data", ^message}
    end

    test "handle_message/2 handles unknown message types", %{state: state} do
      message = %{"unknown_field" => true}
      assert {:ok, ^state} = MockMessageHandler.handle_message(message, state)
      assert_received {:handled, :unknown, ^message}
    end

    test "validate_message/1 validates valid messages" do
      message = %{"valid" => true, "data" => "test"}
      assert {:ok, ^message} = MockMessageHandler.validate_message(message)
    end

    test "validate_message/1 rejects invalid messages" do
      message = %{"valid" => false}
      assert {:error, :invalid_message, ^message} = MockMessageHandler.validate_message(message)
    end

    test "validate_message/1 handles unknown formats" do
      message = %{"something_else" => true}
      assert {:error, :unknown_format, ^message} = MockMessageHandler.validate_message(message)
    end

    test "message_type/1 extracts message type" do
      message = %{"type" => "update"}
      assert "update" = MockMessageHandler.message_type(message)
    end

    test "message_type/1 handles messages without type" do
      message = %{"no_type" => true}
      assert :unknown = MockMessageHandler.message_type(message)
    end

    test "encode_message/2 encodes heartbeat messages", %{state: state} do
      assert {:ok, :text, json} = MockMessageHandler.encode_message(:heartbeat, state)
      assert Jason.decode!(json) == %{"type" => "heartbeat"}
    end

    test "encode_message/2 encodes subscription messages", %{state: state} do
      assert {:ok, :text, json} = MockMessageHandler.encode_message({:subscribe, "trades"}, state)
      assert Jason.decode!(json) == %{"type" => "subscribe", "channel" => "trades"}
    end

    test "encode_message/2 handles unknown message types", %{state: state} do
      assert {:error, :unknown_message_type} = MockMessageHandler.encode_message(:unknown, state)
    end
  end
end
