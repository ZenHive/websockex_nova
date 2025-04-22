defmodule WebsockexNova.TransportTest do
  use ExUnit.Case, async: true

  import Mox

  # Define a mock for the transport behaviour
  defmock(WebsockexNova.MockTransport, for: WebsockexNova.Transport)

  setup :verify_on_exit!

  @state :mock_state
  @stream_ref :mock_stream
  @frame {:text, "hello"}
  @headers [{"authorization", "Bearer token"}]
  @path "/ws"

  describe "WebsockexNova.Transport behaviour" do
    test "requires all callbacks to be implemented" do
      assert {:module, WebsockexNova.MockTransport} =
               :code.ensure_loaded(WebsockexNova.MockTransport)

      # The following will fail if any callback is missing
      assert function_exported?(WebsockexNova.MockTransport, :send_frame, 3)
      assert function_exported?(WebsockexNova.MockTransport, :upgrade_to_websocket, 3)
      assert function_exported?(WebsockexNova.MockTransport, :close, 1)
      assert function_exported?(WebsockexNova.MockTransport, :process_transport_message, 2)
      assert function_exported?(WebsockexNova.MockTransport, :get_state, 1)
    end

    test "send_frame/3 routes to the transport and returns :ok" do
      state = @state
      stream_ref = @stream_ref
      frame = @frame
      expect(WebsockexNova.MockTransport, :send_frame, fn ^state, ^stream_ref, ^frame -> :ok end)
      assert :ok == WebsockexNova.MockTransport.send_frame(state, stream_ref, frame)
    end

    test "upgrade_to_websocket/3 routes to the transport and returns {:ok, stream_ref}" do
      state = @state
      path = @path
      headers = @headers
      stream_ref = @stream_ref
      expect(WebsockexNova.MockTransport, :upgrade_to_websocket, fn ^state, ^path, ^headers -> {:ok, stream_ref} end)
      assert {:ok, stream_ref} == WebsockexNova.MockTransport.upgrade_to_websocket(state, path, headers)
    end

    test "close/1 routes to the transport and returns :ok" do
      state = @state
      expect(WebsockexNova.MockTransport, :close, fn ^state -> :ok end)
      assert :ok == WebsockexNova.MockTransport.close(state)
    end

    test "process_transport_message/2 routes to the transport and returns a value" do
      state = @state
      expect(WebsockexNova.MockTransport, :process_transport_message, fn ^state, :some_msg -> {:handled, :some_msg} end)
      assert {:handled, :some_msg} == WebsockexNova.MockTransport.process_transport_message(state, :some_msg)
    end

    test "get_state/1 routes to the transport and returns the state" do
      state = @state
      expect(WebsockexNova.MockTransport, :get_state, fn ^state -> state end)
      assert state == WebsockexNova.MockTransport.get_state(state)
    end

    test "send_frame/3 returns error if transport returns error" do
      state = @state
      stream_ref = @stream_ref
      frame = @frame
      expect(WebsockexNova.MockTransport, :send_frame, fn ^state, ^stream_ref, ^frame -> {:error, :not_connected} end)
      assert {:error, :not_connected} == WebsockexNova.MockTransport.send_frame(state, stream_ref, frame)
    end
  end
end
