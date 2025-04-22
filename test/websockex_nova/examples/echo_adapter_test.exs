defmodule WebsockexNova.Examples.EchoAdapterTest do
  use ExUnit.Case, async: true

  alias WebsockexNova.Behaviors.AuthHandler
  alias WebsockexNova.Behaviors.ConnectionHandler
  alias WebsockexNova.Behaviors.ErrorHandler
  alias WebsockexNova.Behaviors.MessageHandler
  alias WebsockexNova.Behaviors.SubscriptionHandler
  alias WebsockexNova.Examples.EchoAdapter

  describe "EchoAdapter implementation" do
    test "implements all required behaviors" do
      assert implements_behavior?(EchoAdapter, ConnectionHandler)
      assert implements_behavior?(EchoAdapter, MessageHandler)
      assert implements_behavior?(EchoAdapter, ErrorHandler)
      assert implements_behavior?(EchoAdapter, SubscriptionHandler)
      assert implements_behavior?(EchoAdapter, AuthHandler)
    end

    test "implements connection_info/1" do
      assert function_exported?(EchoAdapter, :connection_info, 1)

      {:ok, conn_info} = EchoAdapter.connection_info(%{})

      assert conn_info.host == "echo.websocket.org"
      assert conn_info.port == 443
      assert conn_info.path == "/"
      assert conn_info.transport_opts.transport == :tls
    end

    test "properly initializes state" do
      {:ok, state} = EchoAdapter.init([])

      assert is_map(state)
      assert is_list(state.messages)
      assert state.connected_at == nil
    end

    test "handles connection events" do
      conn_info = %{host: "echo.websocket.org", port: 443, path: "/"}
      state = %{messages: [], connected_at: nil}

      {:ok, new_state} = EchoAdapter.handle_connect(conn_info, state)

      assert new_state.connected_at != nil
      assert is_list(new_state.messages)
    end

    test "handles disconnection with reconnect" do
      state = %{messages: [], connected_at: System.system_time(:millisecond)}
      reason = {:remote, 1000, "normal"}

      {:reconnect, new_state} = EchoAdapter.handle_disconnect(reason, state)

      assert new_state.connected_at == state.connected_at
    end

    test "properly encodes text messages" do
      {:ok, encoded} = EchoAdapter.encode_message(:text, "Hello", %{})
      assert encoded == "Hello"

      {:ok, encoded} = EchoAdapter.encode_message(:json, %{greeting: "Hello"}, %{})
      assert is_binary(encoded)
      assert Jason.decode!(encoded) == %{"greeting" => "Hello"}
    end

    test "handles incoming text frames" do
      state = %{messages: [], connected_at: System.system_time(:millisecond)}

      # Send a text frame to the handler
      {:ok, new_state} = EchoAdapter.handle_frame(:text, "Echo this message", state)

      # The message should be stored and a response sent to the process
      assert new_state.messages == ["Echo this message"]

      # Check if the message was sent to the process
      assert_receive {:websockex_nova, :response, "Echo this message"}
    end

    test "pings are responded with pongs" do
      state = %{messages: [], connected_at: System.system_time(:millisecond)}

      {:reply, :pong, "", ^state} = EchoAdapter.handle_frame(:ping, "", state)
    end

    test "exponential backoff on reconnection" do
      {reconnect, delay} = EchoAdapter.should_reconnect?(:some_error, 0, %{})
      assert reconnect == true
      assert delay == 1000

      {reconnect, delay} = EchoAdapter.should_reconnect?(:some_error, 1, %{})
      assert reconnect == true
      assert delay == 2000

      {reconnect, delay} = EchoAdapter.should_reconnect?(:some_error, 2, %{})
      assert reconnect == true
      assert delay == 4000
    end
  end

  # Helper to check if a module implements a behavior
  defp implements_behavior?(module, behavior) do
    :attributes
    |> module.__info__()
    |> Keyword.get_values(:behaviour)
    |> List.flatten()
    |> Enum.member?(behavior)
  end
end
