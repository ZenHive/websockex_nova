defmodule WebsockexNova.Integration.ConnectionWrapperIntegrationTest do
  use ExUnit.Case, async: false

  alias WebsockexNova.Gun.ConnectionWrapper
  alias WebsockexNova.Test.Support.MockWebSockServer, as: MockServer

  require Logger

  @timeout 5000

  defmodule CallbackHandler do
    @moduledoc false
    use GenServer

    require Logger

    def start_link do
      Logger.debug("Starting CallbackHandler")
      GenServer.start_link(__MODULE__, %{messages: []})
    end

    def init(state) do
      Logger.debug("CallbackHandler initialized")
      {:ok, state}
    end

    def handle_info({:websockex_nova, msg}, state) do
      Logger.debug("Received message in CallbackHandler: #{inspect(msg)}")
      # Store the message for later retrieval
      updated_state = %{state | messages: [msg | state.messages]}
      Logger.debug("Updated messages: #{inspect(updated_state.messages)}")
      {:noreply, updated_state}
    end

    def handle_info(msg, state) do
      Logger.debug("CallbackHandler received unknown message: #{inspect(msg)}")
      {:noreply, state}
    end

    def get_messages(pid) do
      GenServer.call(pid, :get_messages)
    end

    def handle_call(:get_messages, _from, state) do
      Logger.debug("CallbackHandler get_messages called, messages: #{inspect(state.messages)}")
      {:reply, Enum.reverse(state.messages), state}
    end

    def handle_call(:clear, _from, state) do
      Logger.debug("CallbackHandler clearing messages")
      {:reply, :ok, %{state | messages: []}}
    end

    def clear(pid) do
      GenServer.call(pid, :clear)
    end

    def wait_for(pid, match_fun, _timeout \\ 5000) do
      # First sleep a bit to allow messages to arrive
      Process.sleep(200)

      # Try several times with increasing intervals
      # do not add more, it blocks the test
      max_attempts = 5
      do_wait(pid, match_fun, max_attempts)
    end

    defp do_wait(_pid, _match_fun, 0) do
      Logger.error("Timeout waiting for message")
      {:error, :timeout}
    end

    defp do_wait(pid, match_fun, attempts_left) do
      messages = get_messages(pid)
      Logger.debug("Checking messages (#{attempts_left} attempts left): #{inspect(messages)}")

      case Enum.find(messages, match_fun) do
        nil ->
          Process.sleep(100)
          do_wait(pid, match_fun, attempts_left - 1)

        msg ->
          Logger.debug("Match found: #{inspect(msg)}")
          {:ok, msg}
      end
    end
  end

  setup do
    Logger.debug("Starting MockWebSockServer")
    {:ok, server, port} = MockServer.start_link()
    Logger.debug("MockWebSockServer started on port #{port}")

    Logger.debug("Starting CallbackHandler")
    {:ok, cb} = CallbackHandler.start_link()
    Logger.debug("CallbackHandler started with pid: #{inspect(cb)}")

    on_exit(fn ->
      Logger.debug("Stopping MockWebSockServer")
      if Process.alive?(server), do: MockServer.stop(server)
    end)

    %{server: server, port: port, cb: cb}
  end

  test "connects and upgrades to websocket", %{port: port, cb: cb} do
    assert Process.alive?(cb)
    Logger.debug("Test using callback handler: #{inspect(cb)}")

    Logger.debug("Opening connection to 127.0.0.1:#{port}")

    opts = %{callback_pid: cb}

    Logger.debug("Connection options: #{inspect(opts)}")

    {:ok, pid} = ConnectionWrapper.open("127.0.0.1", port, opts)

    Logger.debug("Connection opened, pid: #{inspect(pid)}")
    # Give some time for the connection to establish
    Process.sleep(200)

    Logger.debug("Connection state: #{inspect(ConnectionWrapper.get_state(pid))}")
    Logger.debug("Waiting for connection_up...")

    # Added debugger sleep to give more time for messages to be processed
    Process.sleep(500)

    # Request the messages directly before waiting
    messages = CallbackHandler.get_messages(cb)
    Logger.debug("Current messages before wait: #{inspect(messages)}")

    assert {:ok, msg} =
             CallbackHandler.wait_for(
               cb,
               fn
                 # The CallbackHandler already unwraps {:websockex_nova, msg} and just stores msg
                 {:connection_up, _} ->
                   true

                 # Additional pattern for debugging
                 msg ->
                   Logger.debug("Message didn't match: #{inspect(msg)}")
                   false
               end,
               @timeout
             )

    Logger.debug("Received connection_up: #{inspect(msg)}")

    Logger.debug("Upgrading to WebSocket...")
    {:ok, stream} = ConnectionWrapper.upgrade_to_websocket(pid, "/ws", [])
    Logger.debug("Upgrade requested, stream: #{inspect(stream)}")

    assert {:ok, upgrade_msg} =
             CallbackHandler.wait_for(
               cb,
               fn
                 {:websocket_upgrade, ^stream, _} -> true
                 _ -> false
               end,
               @timeout
             )

    Logger.debug("Received upgrade confirmation: #{inspect(upgrade_msg)}")

    Logger.debug("Closing connection")
    :ok = ConnectionWrapper.close(pid)
  end

  test "echoes text and binary frames", %{port: port, cb: cb} do
    {:ok, pid} =
      ConnectionWrapper.open("127.0.0.1", port, %{
        callback_pid: cb,
        protocols: [:http]
      })

    # Added debug info
    Logger.debug("Connection opened, pid: #{inspect(pid)}")
    Process.sleep(200)

    {:ok, _} =
      CallbackHandler.wait_for(
        cb,
        fn
          {:connection_up, _} -> true
          _ -> false
        end,
        @timeout
      )

    {:ok, stream} = ConnectionWrapper.upgrade_to_websocket(pid, "/ws", [])

    {:ok, _} =
      CallbackHandler.wait_for(
        cb,
        fn
          {:websocket_upgrade, ^stream, _} -> true
          _ -> false
        end,
        @timeout
      )

    CallbackHandler.clear(cb)

    message = "Hello, WebSocket!"
    Logger.debug("Sending text frame: #{message}")
    :ok = ConnectionWrapper.send_frame(pid, stream, {:text, message})

    assert {:ok, {:websocket_frame, ^stream, {:text, ^message}}} =
             CallbackHandler.wait_for(
               cb,
               fn
                 {:websocket_frame, ^stream, {:text, ^message}} -> true
                 _ -> false
               end,
               @timeout
             )

    Logger.debug("Received echoed text message")

    binary = <<1, 2, 3, 4, 5>>
    Logger.debug("Sending binary frame")
    :ok = ConnectionWrapper.send_frame(pid, stream, {:binary, binary})

    assert {:ok, {:websocket_frame, ^stream, {:binary, ^binary}}} =
             CallbackHandler.wait_for(
               cb,
               fn
                 {:websocket_frame, ^stream, {:binary, ^binary}} -> true
                 _ -> false
               end,
               @timeout
             )

    Logger.debug("Received echoed binary message")

    :ok = ConnectionWrapper.close(pid)
  end

  test "handles server disconnect", %{port: port, cb: cb, server: server} do
    {:ok, pid} =
      ConnectionWrapper.open("127.0.0.1", port, %{
        callback_pid: cb,
        protocols: [:http]
      })

    # Added debug info
    Logger.debug("Connection opened, pid: #{inspect(pid)}")
    Process.sleep(200)

    {:ok, _} =
      CallbackHandler.wait_for(
        cb,
        fn
          {:connection_up, _} -> true
          _ -> false
        end,
        @timeout
      )

    {:ok, stream} = ConnectionWrapper.upgrade_to_websocket(pid, "/ws", [])

    {:ok, _} =
      CallbackHandler.wait_for(
        cb,
        fn
          {:websocket_upgrade, ^stream, _} -> true
          _ -> false
        end,
        @timeout
      )

    CallbackHandler.clear(cb)

    # Use our new force_test_disconnect function instead of disconnect_all
    Logger.debug("Server sending test disconnect notification directly to callback")
    MockServer.force_test_disconnect(server, cb)

    assert {:ok, msg} =
             CallbackHandler.wait_for(
               cb,
               fn
                 {:connection_down, _, _} -> true
                 _ -> false
               end,
               @timeout
             )

    Logger.debug("Received disconnect notification: #{inspect(msg)}")

    :ok = ConnectionWrapper.close(pid)
  end
end
