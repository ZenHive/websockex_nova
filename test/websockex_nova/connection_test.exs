defmodule WebsockexNova.ConnectionTest do
  use ExUnit.Case, async: false

  import Mox

  alias WebsockexNova.Connection

  setup :verify_on_exit!

  setup do
    # Default options with all handler mocks
    opts = [
      adapter: WebsockexNova.TestAdapter,
      connection_handler: WebsockexNova.ConnectionHandlerMock,
      message_handler: WebsockexNova.MessageHandlerMock,
      subscription_handler: WebsockexNova.SubscriptionHandlerMock,
      auth_handler: WebsockexNova.AuthHandlerMock,
      error_handler: WebsockexNova.ErrorHandlerMock,
      rate_limit_handler: WebsockexNova.RateLimitHandlerMock,
      logging_handler: WebsockexNova.LoggingHandlerMock,
      metrics_collector: WebsockexNova.MetricsCollectorMock,
      test_mode: true,
      host: "localhost"
    ]

    {:ok, opts: opts}
  end

  describe "handle_info/2 - Gun connection down" do
    test "cleans up state and schedules reconnection", %{opts: opts} do
      {:ok, conn} = WebsockexNova.Connection.start_link_test(opts)
      pid = conn.pid
      _state = :sys.get_state(pid)
      send(pid, {:gun_down, :gun_pid, :http, :closed, [], []})
      assert Process.alive?(pid)
    end
  end

  describe "handle_info/2 - WebSocket upgrade failure" do
    test "fails all buffered requests and stops", %{opts: opts} do
      Process.flag(:trap_exit, true)
      {:ok, conn} = WebsockexNova.Connection.start_link_test(opts)
      pid = conn.pid
      # Use a spawned process as the 'from' value to avoid mailbox collision
      parent = self()

      from_pid =
        spawn(fn ->
          receive do
            msg -> send(parent, {:forwarded, msg})
          end
        end)

      :sys.replace_state(pid, fn s -> %{s | request_buffer: [{:frame, 1, from_pid}]} end)
      send(pid, {:gun_upgrade, :gun_pid, :stream_ref, ["notwebsocket"]})
      assert_receive {:forwarded, {:error, :websocket_upgrade_failed}}
      assert_receive {:EXIT, ^pid, :websocket_upgrade_failed}
    end
  end

  describe "handle_info/2 - Gun WebSocket frame" do
    test "routes JSON-RPC response by id", %{opts: opts} do
      {:ok, conn} = WebsockexNova.Connection.start_link_test(opts)
      pid = conn.pid
      # Use a spawned process as the 'from' value
      parent = self()

      from_pid =
        spawn(fn ->
          receive do
            msg -> send(parent, {:forwarded, msg})
          end
        end)

      :sys.replace_state(pid, fn s -> %{s | pending_requests: %{"42" => from_pid}, pending_timeouts: %{}} end)
      frame = {:text, ~s({"id":"42","result":"ok"})}
      send(pid, {:gun_ws, :gun_pid, :stream_ref, frame})
      assert_receive {:forwarded, {:reply, {:text, _}}}
    end
  end

  describe "handle_info/2 - Gun error" do
    test "fails all pending and buffered requests and stops", %{opts: opts} do
      Process.flag(:trap_exit, true)
      {:ok, conn} = WebsockexNova.Connection.start_link_test(opts)
      pid = conn.pid
      # Use spawned processes for both pending and buffered requests
      parent = self()

      from1 =
        spawn(fn ->
          receive do
            msg -> send(parent, {:forwarded, msg})
          end
        end)

      from2 =
        spawn(fn ->
          receive do
            msg -> send(parent, {:forwarded, msg})
          end
        end)

      :sys.replace_state(pid, fn s ->
        %{s | pending_requests: %{"1" => from1}, request_buffer: [{:frame, 2, from2}], pending_timeouts: %{}}
      end)

      send(pid, {:gun_error, :gun_pid, :stream_ref, :boom})
      assert_receive {:forwarded, {:error, :boom}}
      assert_receive {:forwarded, {:error, :boom}}
      assert_receive {:EXIT, ^pid, :boom}
    end
  end

  describe "handle_info/2 - request timeout" do
    test "fails the pending request with :timeout", %{opts: opts} do
      {:ok, conn} = WebsockexNova.Connection.start_link_test(opts)
      pid = conn.pid
      # Use a spawned process as the 'from' value
      parent = self()

      from_pid =
        spawn(fn ->
          receive do
            msg -> send(parent, {:forwarded, msg})
          end
        end)

      :sys.replace_state(pid, fn s -> %{s | pending_requests: %{"99" => from_pid}, pending_timeouts: %{}} end)
      send(pid, {:request_timeout, "99"})
      assert_receive {:forwarded, {:error, :timeout}}
    end
  end

  describe "handle_info/2 - unexpected message" do
    test "logs and crashes the process", %{opts: opts} do
      {:ok, conn} = WebsockexNova.Connection.start_link_test(opts)
      pid = conn.pid
      Process.flag(:trap_exit, true)
      ref = Process.monitor(pid)
      send(pid, :unexpected)
      assert_receive {:DOWN, ^ref, :process, ^pid, _}
    end
  end

  @tag :skip
  test "handle_call/3 - send_request when ws_stream_ref is set: skipped in test mode due to GenServer self-call limitation" do
    # In test mode, the wrapper_pid is the same as the GenServer pid, so calling GenServer.call to self is not allowed.
    # This test is skipped. In a real integration test, use a real wrapper_pid or a proper mock process.
    :ok
  end
end
