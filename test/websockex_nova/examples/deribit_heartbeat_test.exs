defmodule WebsockexNova.Examples.DeribitHeartbeatTest do
  use ExUnit.Case, async: true

  alias WebsockexNova.Examples.AdapterDeribit

  describe "handle_frame/3" do
    test "responds to heartbeat test_request messages" do
      # Create a test state
      state = %{
        requests: %{},
        messages: []
      }

      # Create a Deribit heartbeat test_request message
      test_request = ~s({"params":{"type":"test_request"},"method":"heartbeat","jsonrpc":"2.0"})

      # Call the handler directly
      result = AdapterDeribit.handle_frame(:text, test_request, state)

      # Verify that it returns a reply with the correct format (5-tuple with :text_frame)
      assert {:reply, :text, response, _updated_state, :text_frame} = result

      # Decode the response to verify its content
      decoded = Jason.decode!(response)

      # Verify that it's a proper Deribit test request
      assert decoded["jsonrpc"] == "2.0"
      assert decoded["method"] == "public/test"
      assert is_map(decoded["params"])
      assert is_integer(decoded["id"])
    end

    test "regular messages are handled normally" do
      # Create a test state
      state = %{
        requests: %{},
        messages: []
      }

      # Create a regular message
      regular_message = ~s({"jsonrpc":"2.0","id":123,"result":"success"})

      # Call the handler directly
      result = AdapterDeribit.handle_frame(:text, regular_message, state)

      # Verify that regular messages are processed normally (no reply)
      assert {:ok, updated_state} = result

      # The implementation stores both the raw text and the decoded message
      # so we need to check for both in the messages array
      assert Enum.any?(updated_state.messages, fn msg ->
               case msg do
                 %{"jsonrpc" => "2.0", "id" => 123, "result" => "success"} -> true
                 _ -> false
               end
             end)

      assert Enum.any?(updated_state.messages, fn msg ->
               msg == regular_message
             end)
    end

    test "non-text frames are passed through" do
      # Create a test state
      state = %{
        requests: %{},
        messages: []
      }

      # Call the handler with a binary frame
      result = AdapterDeribit.handle_frame(:binary, <<1, 2, 3>>, state)

      # Verify it's passed through with no changes
      assert {:ok, new_state} = result
      assert new_state.messages == []
      assert new_state.requests == %{}
    end

    test "malformed JSON is handled gracefully" do
      # Create a test state
      state = %{
        requests: %{},
        messages: []
      }

      # Create invalid JSON
      invalid_json = ~s({"jsonrpc":"2.0",invalid})

      # Call the handler directly
      result = AdapterDeribit.handle_frame(:text, invalid_json, state)

      # Verify that it doesn't crash and captures the raw message
      assert {:ok, updated_state} = result
      assert updated_state.messages == [invalid_json]
    end
  end
end
