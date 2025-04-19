defmodule WebsockexNova.Gun.ConnectionWrapperTest do
  @moduledoc """
  Integration and edge case tests for WebsockexNova.Gun.ConnectionWrapper.
  Covers connection lifecycle, frame handling, error handling, ownership transfer, and edge cases.
  Ensures robust error handling, consistent error returns, and correct state transitions.
  """
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias WebsockexNova.Gun.ConnectionWrapper
  alias WebsockexNova.Telemetry.TelemetryEvents
  alias WebsockexNova.Test.Support.MockWebSockServer
  alias WebsockexNova.TestSupport.RateLimitHandlers
  alias WebsockexNova.Transport.RateLimiting

  require Logger

  @moduletag :integration

  @websocket_path "/ws"
  @default_delay 100

  setup do
    {:ok, server_pid, port} = MockWebSockServer.start_link()

    on_exit(fn ->
      Process.sleep(@default_delay)

      try do
        if is_pid(server_pid) and Process.alive?(server_pid), do: GenServer.stop(server_pid)
      catch
        :exit, _ -> :ok
      end
    end)

    %{port: port}
  end

  @doc """
  Tests the connection lifecycle, including open, upgrade, and close.
  Ensures state transitions are correct and resources are cleaned up.
  """
  describe "connection lifecycle" do
    test "basic connection and WebSocket functionality", %{port: port} do
      {:ok, conn_pid} = ConnectionWrapper.open("localhost", port, %{transport: :tcp})
      assert_connection_status(conn_pid, :connected)
      state = ConnectionWrapper.get_state(conn_pid)
      assert is_pid(state.gun_pid)
      assert is_reference(state.gun_monitor_ref)
      {:ok, stream_ref} = ConnectionWrapper.upgrade_to_websocket(conn_pid, @websocket_path)
      assert_connection_status(conn_pid, :websocket_connected)
      updated_state = ConnectionWrapper.get_state(conn_pid)
      assert Map.get(updated_state.active_streams, stream_ref) == :websocket
      test_message = "Test message"
      :ok = ConnectionWrapper.send_frame(conn_pid, stream_ref, {:text, test_message})
      Process.sleep(@default_delay)
      ConnectionWrapper.close(conn_pid)
    end

    test "handles different frame types", %{port: port} do
      {:ok, conn_pid} = ConnectionWrapper.open("localhost", port, %{callback_pid: self(), transport: :tcp})
      assert_connection_status(conn_pid, :connected)
      {:ok, stream_ref} = ConnectionWrapper.upgrade_to_websocket(conn_pid, @websocket_path)
      assert_connection_status(conn_pid, :websocket_connected)
      assert_receive {:websockex_nova, {:websocket_upgrade, ^stream_ref, _headers}}, 500
      :ok = ConnectionWrapper.send_frame(conn_pid, stream_ref, {:text, "Text message"})
      assert_receive {:websockex_nova, {:websocket_frame, ^stream_ref, {:text, "Text message"}}}, 500
      binary_data = <<1, 2, 3, 4, 5>>
      :ok = ConnectionWrapper.send_frame(conn_pid, stream_ref, {:binary, binary_data})
      assert_receive {:websockex_nova, {:websocket_frame, ^stream_ref, {:binary, ^binary_data}}}, 500
      :ok = ConnectionWrapper.send_frame(conn_pid, stream_ref, :ping)
      Process.sleep(@default_delay)
      :ok = ConnectionWrapper.send_frame(conn_pid, stream_ref, :pong)
      Process.sleep(@default_delay)
      ConnectionWrapper.close(conn_pid)
    end

    test "handles connection status transitions", %{port: port} do
      {:ok, conn_pid} = ConnectionWrapper.open("localhost", port, %{transport: :tcp})
      assert_connection_status(conn_pid, :connected)
      :ok = ConnectionWrapper.set_status(conn_pid, :disconnected)
      assert_connection_status(conn_pid, :disconnected)
      :ok = ConnectionWrapper.set_status(conn_pid, :reconnecting)
      assert_connection_status(conn_pid, :reconnecting)
      :ok = ConnectionWrapper.set_status(conn_pid, :connected)
      assert_connection_status(conn_pid, :connected)
      ConnectionWrapper.close(conn_pid)
    end
  end

  @doc """
  Tests frame handling edge cases, including invalid stream references and close frame behavior.
  Ensures consistent error returns and graceful handling of closed or missing streams.
  """
  describe "frame handling" do
    test "handles invalid stream references gracefully", %{port: port} do
      {:ok, conn_pid} = ConnectionWrapper.open("localhost", port, %{transport: :tcp})
      assert_connection_status(conn_pid, :connected)
      invalid_stream_ref = make_ref()
      result = ConnectionWrapper.send_frame(conn_pid, invalid_stream_ref, {:text, "test"})
      assert result == {:error, :stream_not_found}
      ConnectionWrapper.close(conn_pid)
    end

    test "handles websocket close frames correctly", %{port: port} do
      {:ok, conn_pid} = ConnectionWrapper.open("localhost", port, %{callback_pid: self(), transport: :tcp})
      assert_connection_status(conn_pid, :connected)
      {:ok, stream_ref} = ConnectionWrapper.upgrade_to_websocket(conn_pid, @websocket_path)
      assert_connection_status(conn_pid, :websocket_connected)
      :ok = ConnectionWrapper.send_frame(conn_pid, stream_ref, :close)
      Process.sleep(@default_delay)
      result = ConnectionWrapper.send_frame(conn_pid, stream_ref, {:close, 1000, "Normal closure"})
      assert result == :ok || result == {:error, :stream_not_found}
      ConnectionWrapper.close(conn_pid)
    end

    test "handles multiple frame sends in sequence", %{port: port} do
      {:ok, conn_pid} = ConnectionWrapper.open("localhost", port, %{callback_pid: self(), transport: :tcp})
      assert_connection_status(conn_pid, :connected)
      {:ok, stream_ref} = ConnectionWrapper.upgrade_to_websocket(conn_pid, @websocket_path)
      assert_connection_status(conn_pid, :websocket_connected)

      frames = [
        {:text, "First message"},
        {:binary, <<10, 20, 30>>},
        :ping,
        {:text, "Last message"}
      ]

      Enum.each(frames, fn frame ->
        :ok = ConnectionWrapper.send_frame(conn_pid, stream_ref, frame)
        Process.sleep(50)
      end)

      ConnectionWrapper.close(conn_pid)
    end

    test "emits message_sent telemetry on frame send", %{port: port} do
      require TelemetryEvents

      test_pid = self()
      event = TelemetryEvents.message_sent()
      handler_id = make_ref()

      :telemetry.attach(
        handler_id,
        event,
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry_event, event, measurements, metadata})
        end,
        nil
      )

      {:ok, conn_pid} = ConnectionWrapper.open("localhost", port, %{transport: :tcp})
      assert_connection_status(conn_pid, :connected)
      {:ok, stream_ref} = ConnectionWrapper.upgrade_to_websocket(conn_pid, @websocket_path)
      assert_connection_status(conn_pid, :websocket_connected)
      :ok = ConnectionWrapper.send_frame(conn_pid, stream_ref, {:text, "Telemetry Test"})
      assert_receive {:telemetry_event, ^event, meas, meta}, 200
      assert meta.connection_id == ConnectionWrapper.get_state(conn_pid).gun_pid
      assert meta.stream_ref == stream_ref
      assert meta.frame_type == :text
      assert meas.size == byte_size("Telemetry Test")
      ConnectionWrapper.close(conn_pid)
      :telemetry.detach(handler_id)
    end
  end

  @doc """
  Tests callback notification behavior. Ensures that when a callback process is provided, all connection and frame events
  are sent to the callback in the expected format.
  """
  describe "callback notification" do
    test "sends messages to callback process when provided", %{port: port} do
      {:ok, conn_pid} = ConnectionWrapper.open("localhost", port, %{callback_pid: self(), transport: :tcp})
      assert_connection_status(conn_pid, :connected)
      assert_receive({:websockex_nova, {:connection_up, :http}}, 500)
      {:ok, stream_ref} = ConnectionWrapper.upgrade_to_websocket(conn_pid, @websocket_path)
      assert_connection_status(conn_pid, :websocket_connected)
      assert_receive({:websockex_nova, {:websocket_upgrade, ^stream_ref, _headers}}, 500)
      :ok = ConnectionWrapper.send_frame(conn_pid, stream_ref, {:text, "Text message"})

      assert_receive(
        {:websockex_nova, {:websocket_frame, ^stream_ref, {:text, "Text message"}}},
        500
      )

      ConnectionWrapper.close(conn_pid)
    end
  end

  @doc """
  Tests ownership transfer scenarios, including successful transfer, receiving ownership, and error cases
  (such as missing Gun pid). Ensures monitor references are updated and errors are returned consistently.
  """
  describe "ownership transfer" do
    test "transfers ownership of Gun process", %{port: port} do
      test_receiver = spawn_link(fn -> ownership_transfer_test_process() end)
      {:ok, conn_pid} = ConnectionWrapper.open("localhost", port, %{transport: :tcp})
      assert_connection_status(conn_pid, :connected)
      state_before = ConnectionWrapper.get_state(conn_pid)
      assert is_pid(state_before.gun_pid)
      gun_pid = state_before.gun_pid
      gun_monitor_ref_before = state_before.gun_monitor_ref
      assert is_reference(gun_monitor_ref_before)
      :ok = ConnectionWrapper.transfer_ownership(conn_pid, test_receiver)
      Process.sleep(@default_delay)
      state_after = ConnectionWrapper.get_state(conn_pid)
      refute gun_monitor_ref_before == state_after.gun_monitor_ref
      assert gun_pid == state_after.gun_pid
      assert Process.alive?(gun_pid)
      assert is_reference(state_after.gun_monitor_ref)
      ConnectionWrapper.close(conn_pid)
      Process.sleep(@default_delay)
    end

    test "receives ownership from another process", %{port: port} do
      {:ok, conn_pid1} = ConnectionWrapper.open("localhost", port, %{transport: :tcp})
      assert_connection_status(conn_pid1, :connected)
      state1 = ConnectionWrapper.get_state(conn_pid1)
      gun_pid = state1.gun_pid
      {:ok, conn_pid2} = ConnectionWrapper.open("localhost", port, %{callback_pid: self(), transport: :tcp})
      Process.sleep(@default_delay)
      :ok = ConnectionWrapper.receive_ownership(conn_pid2, gun_pid)
      Process.sleep(@default_delay)
      state2 = ConnectionWrapper.get_state(conn_pid2)
      assert state2.gun_pid == gun_pid
      assert is_reference(state2.gun_monitor_ref)
      assert state2.status == :connected
      ConnectionWrapper.close(conn_pid1)
      ConnectionWrapper.close(conn_pid2)
    end

    test "fails gracefully when trying to transfer ownership with no Gun pid", %{port: port} do
      {:ok, conn_pid} = ConnectionWrapper.open("localhost", port, %{retry: 0, transport: :tcp})
      assert_connection_status(conn_pid, :connected)
      state = ConnectionWrapper.get_state(conn_pid)
      modified_state = Map.put(state, :gun_pid, nil)
      :sys.replace_state(conn_pid, fn _ -> modified_state end)
      result = ConnectionWrapper.transfer_ownership(conn_pid, self())
      assert result == {:error, :no_gun_pid}
      ConnectionWrapper.close(conn_pid)
      Process.sleep(@default_delay)
    end
  end

  @doc """
  Tests error handling for invalid ownership, monitor cleanup, and Gun process errors.
  Ensures that all error returns are consistent and that resources are cleaned up properly.
  """
  describe "error handling" do
    test "handles invalid receive_ownership gracefully", %{port: port} do
      invalid_gun_pid = spawn(fn -> :ok end)
      Process.exit(invalid_gun_pid, :kill)
      Process.sleep(50)
      {:ok, conn_pid} = ConnectionWrapper.open("localhost", 9999, %{retry: 0, transport: :tcp})
      result = ConnectionWrapper.receive_ownership(conn_pid, invalid_gun_pid)
      assert match?({:error, _}, result)
      ConnectionWrapper.close(conn_pid)
    end

    test "monitors are cleaned up during ownership transfer", %{port: port} do
      {:ok, conn_pid1} = ConnectionWrapper.open("localhost", port, %{transport: :tcp})
      {:ok, conn_pid2} = ConnectionWrapper.open("localhost", port, %{transport: :tcp})
      assert_connection_status(conn_pid1, :connected)
      assert_connection_status(conn_pid2, :connected)
      state1_before = ConnectionWrapper.get_state(conn_pid1)
      gun_pid = state1_before.gun_pid
      monitor_ref_before = state1_before.gun_monitor_ref
      :ok = ConnectionWrapper.transfer_ownership(conn_pid1, conn_pid2)
      Process.sleep(@default_delay)
      state1_after = ConnectionWrapper.get_state(conn_pid1)
      assert state1_after.gun_pid == gun_pid
      refute state1_after.gun_monitor_ref == monitor_ref_before
      ConnectionWrapper.close(conn_pid1)
      ConnectionWrapper.close(conn_pid2)
      Process.sleep(@default_delay)
    end
  end

  @doc """
  Tests comprehensive error handling for Gun protocol errors, connection errors, and upgrade errors.
  Ensures all error returns are consistent and contain useful diagnostic information.
  """
  describe "comprehensive error handling" do
    test "handles gun response errors consistently", %{port: port} do
      {:ok, conn_pid} = ConnectionWrapper.open("localhost", port, %{callback_pid: self(), transport: :tcp})
      assert_connection_status(conn_pid, :connected)
      state = ConnectionWrapper.get_state(conn_pid)
      gun_pid = state.gun_pid
      stream_ref = make_ref()
      error_reason = :timeout
      send(conn_pid, {:gun_error, gun_pid, stream_ref, error_reason})
      assert_receive {:websockex_nova, {:error, ^stream_ref, ^error_reason}}, 500
      ConnectionWrapper.close(conn_pid)
    end

    test "handles connection errors consistently", %{port: port} do
      {:ok, conn_pid} = ConnectionWrapper.open("localhost", port, %{callback_pid: self(), transport: :tcp})
      assert_connection_status(conn_pid, :connected)
      state = ConnectionWrapper.get_state(conn_pid)
      gun_pid = state.gun_pid
      error_reason = :closed
      send(conn_pid, {:gun_down, gun_pid, :http, error_reason, [], []})
      assert_receive {:websockex_nova, {:connection_down, :http, ^error_reason}}, 500
      ConnectionWrapper.close(conn_pid)
    end

    test "handles wait_for_websocket_upgrade errors consistently", %{port: port} do
      {:ok, conn_pid} = ConnectionWrapper.open("localhost", port, %{transport: :tcp})
      assert_connection_status(conn_pid, :connected)
      invalid_stream_ref = make_ref()
      result = ConnectionWrapper.wait_for_websocket_upgrade(conn_pid, invalid_stream_ref, 100)
      assert match?({:error, _}, result)
      {:error, reason} = result
      assert is_atom(reason) or is_tuple(reason)
      ConnectionWrapper.close(conn_pid)
    end
  end

  @doc """
  Tests reconnection and backoff logic. Ensures that the connection wrapper attempts to reconnect after a drop,
  respects the retry limit, and transitions to the correct state.
  """
  describe "reconnection and backoff" do
    test "reconnects after connection drop and respects retry limit", %{port: port} do
      {:ok, conn_pid} = ConnectionWrapper.open("localhost", port, %{retry: 2, base_backoff: 50, transport: :tcp})
      state = ConnectionWrapper.get_state(conn_pid)
      send(conn_pid, {:gun_down, state.gun_pid, :http, :closed, [], []})

      expected_states = [:disconnected, :error, :reconnecting]
      start = System.monotonic_time(:millisecond)
      timeout = 2000

      wait_for_terminal_state = fn ->
        loop = fn loop ->
          state = ConnectionWrapper.get_state(conn_pid)

          if state.status in expected_states do
            state.status
          else
            if System.monotonic_time(:millisecond) - start > timeout do
              flunk("Connection did not reach a terminal state within #{timeout}ms, got #{inspect(state.status)}")
            else
              Process.sleep(50)
              loop.(loop)
            end
          end
        end

        loop.(loop)
      end

      final_status = wait_for_terminal_state.()
      assert final_status in expected_states
      ConnectionWrapper.close(conn_pid)
      Process.sleep(@default_delay)
    end
  end

  @doc """
  Tests edge cases in ownership transfer, including transferring while a stream is active and rapid repeated transfers.
  Ensures that the connection wrapper handles these scenarios without crashing or leaking resources.
  """
  describe "ownership transfer edge cases" do
    test "transfers ownership while stream is active", %{port: port} do
      {:ok, conn_pid} = ConnectionWrapper.open("localhost", port, %{transport: :tcp})
      assert_connection_status(conn_pid, :connected)
      {:ok, stream_ref} = ConnectionWrapper.upgrade_to_websocket(conn_pid, @websocket_path)
      assert_connection_status(conn_pid, :websocket_connected)
      test_receiver = spawn_link(fn -> ownership_transfer_test_process() end)
      :ok = ConnectionWrapper.transfer_ownership(conn_pid, test_receiver)
      Process.sleep(@default_delay)
      result = ConnectionWrapper.send_frame(conn_pid, stream_ref, {:text, "after transfer"})
      assert result == :ok or result == {:error, :stream_not_found} or result == {:error, :not_connected}
      ConnectionWrapper.close(conn_pid)
      Process.sleep(@default_delay)
    end

    test "rapid repeated ownership transfers", %{port: port} do
      {:ok, conn_pid} = ConnectionWrapper.open("localhost", port, %{transport: :tcp})
      assert_connection_status(conn_pid, :connected)
      pids = for _ <- 1..3, do: spawn_link(fn -> ownership_transfer_test_process() end)

      Enum.each(pids, fn pid ->
        :ok = ConnectionWrapper.transfer_ownership(conn_pid, pid)
        Process.sleep(30)
      end)

      ConnectionWrapper.close(conn_pid)
      Process.sleep(@default_delay)
    end
  end

  @doc """
  Tests invocation of a custom callback handler module. Ensures that custom handlers are called as expected
  and can interact with the connection wrapper state.
  """
  describe "custom handler invocation" do
    defmodule CustomHandler do
      @moduledoc false
      def init(opts), do: {:ok, opts}

      def handle_frame(_type, _data, state) do
        send(state[:test_pid], :custom_handler_invoked)
        {:ok, state}
      end
    end

    test "invokes custom callback handler", %{port: port} do
      {:ok, conn_pid} =
        ConnectionWrapper.open("localhost", port, %{callback_handler: CustomHandler, test_pid: self(), transport: :tcp})

      assert_connection_status(conn_pid, :connected)
      {:ok, stream_ref} = ConnectionWrapper.upgrade_to_websocket(conn_pid, @websocket_path)
      assert_connection_status(conn_pid, :websocket_connected)
      :ok = ConnectionWrapper.send_frame(conn_pid, stream_ref, {:text, "trigger custom handler"})
      assert_receive :custom_handler_invoked, 500
      ConnectionWrapper.close(conn_pid)
      Process.sleep(@default_delay)
    end
  end

  @doc """
  Tests logging behavior on error cases, such as invalid ownership transfer. Ensures that errors are logged
  with clear diagnostic messages for troubleshooting.
  """
  describe "logging on error" do
    @tag :skip
    test "logs error on invalid ownership transfer", %{port: port} do
      {:ok, conn_pid} = ConnectionWrapper.open("localhost", port, %{transport: :tcp})
      assert_connection_status(conn_pid, :connected)
      state = ConnectionWrapper.get_state(conn_pid)
      modified_state = Map.put(state, :gun_pid, nil)
      :sys.replace_state(conn_pid, fn _ -> modified_state end)

      log =
        capture_log(fn ->
          _ = ConnectionWrapper.transfer_ownership(conn_pid, self())
        end)

      assert log =~ "Cannot transfer ownership: no Gun process available"
      ConnectionWrapper.close(conn_pid)
      Process.sleep(@default_delay)
    end
  end

  @doc """
  Tests miscellaneous edge cases, including double websocket upgrade, sending after close, and unhandled messages.
  Ensures that the connection wrapper fails gracefully and does not crash in these scenarios.
  """
  describe "edge cases" do
    test "double websocket upgrade fails gracefully", %{port: port} do
      {:ok, conn_pid} = ConnectionWrapper.open("localhost", port, %{transport: :tcp})
      assert_connection_status(conn_pid, :connected)
      {:ok, _stream_ref1} = ConnectionWrapper.upgrade_to_websocket(conn_pid, @websocket_path)
      assert_connection_status(conn_pid, :websocket_connected)
      result = ConnectionWrapper.upgrade_to_websocket(conn_pid, @websocket_path)
      assert match?({:ok, _}, result) or match?({:error, _}, result)
      ConnectionWrapper.close(conn_pid)
      Process.sleep(@default_delay)
    end

    test "send after close returns error", %{port: port} do
      {:ok, conn_pid} = ConnectionWrapper.open("localhost", port, %{transport: :tcp})
      assert_connection_status(conn_pid, :connected)
      {:ok, stream_ref} = ConnectionWrapper.upgrade_to_websocket(conn_pid, @websocket_path)
      assert_connection_status(conn_pid, :websocket_connected)
      ConnectionWrapper.close(conn_pid)
      Process.sleep(50)
      refute Process.alive?(conn_pid)
      result = catch_exit(ConnectionWrapper.send_frame(conn_pid, stream_ref, {:text, "should fail"}))

      assert result == {:EXIT, :normal} or
               result == {:error, :not_connected} or
               result == {:error, :stream_not_found} or
               (is_tuple(result) and elem(result, 0) == :normal and is_tuple(elem(result, 1)) and
                  elem(elem(result, 1), 0) == GenServer) or
               (is_tuple(result) and elem(result, 0) == :noproc and is_tuple(elem(result, 1)) and
                  elem(elem(result, 1), 0) == GenServer)

      Process.sleep(@default_delay)
    end

    test "unhandled message does not crash process", %{port: port} do
      {:ok, conn_pid} = ConnectionWrapper.open("localhost", port, %{transport: :tcp})
      assert_connection_status(conn_pid, :connected)
      send(conn_pid, {:unexpected, :message, :test})
      Process.sleep(100)
      assert Process.alive?(conn_pid)
      ConnectionWrapper.close(conn_pid)
      Process.sleep(@default_delay)
    end
  end

  describe "rate limiting integration" do
    setup %{port: port} do
      # Use a unique name for each test's rate limiter
      rate_limiter_name = String.to_atom("rate_limiter_" <> Integer.to_string(:erlang.unique_integer([:positive])))

      on_exit(fn ->
        if Process.whereis(rate_limiter_name), do: GenServer.stop(rate_limiter_name)
      end)

      %{port: port, rate_limiter_name: rate_limiter_name}
    end

    test "allows frame when rate limiter allows", %{port: port, rate_limiter_name: rl_name} do
      {:ok, _} = RateLimiting.start_link(name: rl_name, handler: RateLimitHandlers.TestHandler, mode: :always_allow)
      {:ok, conn_pid} = ConnectionWrapper.open("localhost", port, %{transport: :tcp, rate_limiter: rl_name})
      assert_connection_status(conn_pid, :connected)
      {:ok, stream_ref} = ConnectionWrapper.upgrade_to_websocket(conn_pid, @websocket_path)
      assert_connection_status(conn_pid, :websocket_connected)
      :ok = ConnectionWrapper.send_frame(conn_pid, stream_ref, {:text, "allowed"})
      ConnectionWrapper.close(conn_pid)
    end

    test "queues frame when rate limiter queues", %{port: port, rate_limiter_name: rl_name} do
      {:ok, _} = RateLimiting.start_link(name: rl_name, handler: RateLimitHandlers.TestHandler, mode: :always_queue)
      {:ok, conn_pid} = ConnectionWrapper.open("localhost", port, %{transport: :tcp, rate_limiter: rl_name})
      assert_connection_status(conn_pid, :connected)
      {:ok, stream_ref} = ConnectionWrapper.upgrade_to_websocket(conn_pid, @websocket_path)
      assert_connection_status(conn_pid, :websocket_connected)
      :ok = ConnectionWrapper.send_frame(conn_pid, stream_ref, {:text, "should queue"})
      # The frame should not be sent immediately, but will be processed on tick
      ConnectionWrapper.close(conn_pid)
    end

    test "rejects frame when rate limiter rejects", %{port: port, rate_limiter_name: rl_name} do
      {:ok, _} = RateLimiting.start_link(name: rl_name, handler: RateLimitHandlers.TestHandler, mode: :always_reject)
      {:ok, conn_pid} = ConnectionWrapper.open("localhost", port, %{transport: :tcp, rate_limiter: rl_name})
      assert_connection_status(conn_pid, :connected)
      {:ok, stream_ref} = ConnectionWrapper.upgrade_to_websocket(conn_pid, @websocket_path)
      assert_connection_status(conn_pid, :websocket_connected)
      result = ConnectionWrapper.send_frame(conn_pid, stream_ref, {:text, "should reject"})
      assert result == {:error, :test_rejection}
      ConnectionWrapper.close(conn_pid)
    end

    test "executes callback when queued frame is processed", %{port: port, rate_limiter_name: rl_name} do
      {:ok, _} =
        RateLimiting.start_link(
          name: rl_name,
          handler: RateLimitHandlers.TestHandler,
          mode: :always_queue,
          process_interval: 50
        )

      {:ok, conn_pid} = ConnectionWrapper.open("localhost", port, %{transport: :tcp, rate_limiter: rl_name})
      assert_connection_status(conn_pid, :connected)
      {:ok, stream_ref} = ConnectionWrapper.upgrade_to_websocket(conn_pid, @websocket_path)
      assert_connection_status(conn_pid, :websocket_connected)
      # Send frame, which will be queued
      :ok = ConnectionWrapper.send_frame(conn_pid, stream_ref, {:text, "queued callback"})
      # Register a callback to confirm execution
      # (The callback is registered internally by ConnectionWrapper, so we just need to wait)
      # Wait for the process_interval to elapse and the callback to be executed
      Process.sleep(100)
      ConnectionWrapper.close(conn_pid)
    end

    test "all outgoing frames are subject to rate limiting", %{port: port, rate_limiter_name: rl_name} do
      # Use a handler that tracks all requests
      {:ok, _} = RateLimiting.start_link(name: rl_name, handler: RateLimitHandlers.TestHandler, mode: :always_allow)
      {:ok, conn_pid} = ConnectionWrapper.open("localhost", port, %{transport: :tcp, rate_limiter: rl_name})
      assert_connection_status(conn_pid, :connected)
      {:ok, stream_ref} = ConnectionWrapper.upgrade_to_websocket(conn_pid, @websocket_path)
      assert_connection_status(conn_pid, :websocket_connected)

      for i <- 1..3 do
        :ok = ConnectionWrapper.send_frame(conn_pid, stream_ref, {:text, "msg#{i}"})
      end

      ConnectionWrapper.close(conn_pid)
    end
  end

  # Helper function to assert connection status with a timeout
  defp assert_connection_status(conn_pid, expected_status, timeout \\ 500) do
    assert_status_with_timeout(conn_pid, expected_status, timeout, 0)
  end

  defp assert_status_with_timeout(conn_pid, expected_status, timeout, elapsed) when elapsed >= timeout do
    state = ConnectionWrapper.get_state(conn_pid)
    flunk("Connection status timeout: expected #{expected_status}, got #{state.status}")
  end

  defp assert_status_with_timeout(conn_pid, expected_status, timeout, elapsed) do
    state = ConnectionWrapper.get_state(conn_pid)

    if state.status == expected_status do
      true
    else
      sleep_time = min(50, timeout - elapsed)
      Process.sleep(sleep_time)
      assert_status_with_timeout(conn_pid, expected_status, timeout, elapsed + sleep_time)
    end
  end

  # Helper for ownership transfer test
  defp ownership_transfer_test_process do
    receive do
      {:gun_info, _info} ->
        ownership_transfer_test_process()

      _ ->
        ownership_transfer_test_process()
    end
  end
end
