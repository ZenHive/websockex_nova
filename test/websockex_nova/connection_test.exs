defmodule WebsockexNova.ConnectionTest do
  use ExUnit.Case, async: true

  import Mox

  alias WebsockexNova.ClientConn
  alias WebsockexNova.Connection

  # Minimal mock transport GenServer
  defmodule MockTransportServer do
    @moduledoc false
    use GenServer

    def start_link(opts \\ []) do
      GenServer.start_link(__MODULE__, opts)
    end

    def init(_opts), do: {:ok, %{status: :connected}}

    def handle_call(:get_state, _from, state), do: {:reply, state, state}
  end

  setup :verify_on_exit!

  setup do
    Mox.set_mox_global()
    {:ok, transport_pid} = MockTransportServer.start_link([])
    {:ok, transport_pid: transport_pid}
  end

  defp default_opts(overrides, transport_pid) do
    [
      adapter: WebsockexNova.TestAdapter,
      connection_handler: WebsockexNova.ConnectionHandlerMock,
      message_handler: WebsockexNova.MessageHandlerMock,
      subscription_handler: WebsockexNova.SubscriptionHandlerMock,
      auth_handler: WebsockexNova.AuthHandlerMock,
      error_handler: WebsockexNova.ErrorHandlerMock,
      rate_limit_handler: WebsockexNova.RateLimitHandlerMock,
      logging_handler: WebsockexNova.LoggingHandlerMock,
      metrics_collector: WebsockexNova.MetricsCollectorMock,
      transport_mod: WebsockexNova.TransportMock,
      transport_state: transport_pid,
      host: "localhost"
    ] ++ overrides
  end

  describe "connection lifecycle" do
    test "successful connection and message send/receive", %{transport_pid: transport_pid} do
      IO.inspect(Code.ensure_loaded?(WebsockexNova.TransportMock), label: "TransportMock loaded?")
      # Arrange: set up Mox expectations for transport and handlers
      expect(WebsockexNova.TransportMock, :open, fn host, port, _opts, _supervisor ->
        assert host == "localhost"
        assert port == 80 or port == 443
        {:ok, transport_pid}
      end)

      expect(WebsockexNova.TransportMock, :upgrade_to_websocket, fn ^transport_pid, "/", _headers ->
        {:ok, :mock_stream_ref}
      end)

      expect(WebsockexNova.TransportMock, :send_frame, fn ^transport_pid, :mock_stream_ref, {:text, "hello"} ->
        :ok
      end)

      # Handler mocks: connection_handler connection_init/handle_connect, message_handler handle_message
      expect(WebsockexNova.ConnectionHandlerMock, :connection_init, fn _opts -> {:ok, %{}} end)
      expect(WebsockexNova.ConnectionHandlerMock, :handle_connect, fn _conn_info, state -> {:ok, state} end)

      expect(WebsockexNova.MessageHandlerMock, :handle_message, fn %{"msg" => "ping"}, state ->
        {:reply, {:text, "pong"}, state}
      end)

      # Act: start the connection (integration style, expect real stream_ref)
      {:ok, %ClientConn{pid: pid, stream_ref: stream_ref}} =
        Connection.start_link(default_opts([], transport_pid))

      # Simulate websocket connected event to trigger handler callbacks
      send(pid, {:websocket_connected, %{}})

      assert stream_ref == :mock_stream_ref

      # Simulate a message event (as if received from the platform)
      send(pid, {:message_event, %{"msg" => "ping"}, self()})

      # Assert: should receive a reply with {:text, "pong"}
      assert_receive {:reply, {:text, "pong"}}, 100

      # Send a frame (simulate client send)
      :sent = GenServer.call(pid, {:send_request, {:text, "hello"}, nil, self()})
    end
  end

  describe "buffering and flushing requests" do
    test "buffers requests before websocket upgrade and fails them after upgrade (financial safety)", %{
      transport_pid: transport_pid
    } do
      opts = default_opts([], transport_pid)
      # Set up Mox expectations
      expect(WebsockexNova.ConnectionHandlerMock, :connection_init, fn _ -> {:ok, %{}} end)
      # In test mode, handle_connect/2 is not called, so we do not set an expectation here.
      # Use start_link_test to ensure ws_stream_ref is nil at start
      {:ok, %ClientConn{pid: pid}} = Connection.start_link_test(opts)
      IO.puts("[TEST] Sending request before upgrade")
      :buffered = GenServer.call(pid, {:send_request, {:text, "buffered"}, nil, self()})
      IO.puts("[TEST] Simulating websocket upgrade")
      send(pid, {:websocket_connected, %{}})
      IO.puts("[TEST] Waiting for error reply after buffer flush (should fail, not send)")
      # Expect error reply due to financial safety (buffered requests are not sent after upgrade)
      assert_receive {:error, :not_sent_due_to_disconnect}, 200
    end
  end

  describe "timeout and error handling" do
    test "handles request timeout and cleans up state", %{transport_pid: transport_pid} do
      opts = default_opts([], transport_pid)
      expect(WebsockexNova.TransportMock, :open, fn _, _, _, _ -> {:ok, transport_pid} end)
      expect(WebsockexNova.TransportMock, :upgrade_to_websocket, fn ^transport_pid, "/", _ -> {:ok, :mock_stream_ref} end)
      expect(WebsockexNova.TransportMock, :send_frame, fn ^transport_pid, :mock_stream_ref, {:text, "timeout"} -> :ok end)
      expect(WebsockexNova.ConnectionHandlerMock, :connection_init, fn _ -> {:ok, %{}} end)
      expect(WebsockexNova.ConnectionHandlerMock, :handle_connect, fn _, state -> {:ok, state} end)
      {:ok, %ClientConn{pid: pid}} = Connection.start_link(opts)
      send(pid, {:websocket_connected, %{}})
      IO.puts("[TEST] Sending request with timeout")
      :sent = GenServer.call(pid, {:send_request, {:text, "timeout"}, 10, self()})
      IO.puts("[TEST] Simulating request timeout event")
      send(pid, {:request_timeout, 10})
      IO.puts("[TEST] Waiting for error reply after timeout...")
      assert_receive msg, 100
      IO.inspect(msg, label: "[TEST] Received message after timeout")
      assert match?({:error, :timeout}, msg)
    end

    test "handles transport error and fails all pending requests", %{transport_pid: transport_pid} do
      opts = default_opts([], transport_pid)
      expect(WebsockexNova.TransportMock, :open, fn _, _, _, _ -> {:ok, transport_pid} end)
      expect(WebsockexNova.TransportMock, :upgrade_to_websocket, fn ^transport_pid, "/", _ -> {:ok, :mock_stream_ref} end)
      expect(WebsockexNova.TransportMock, :send_frame, fn ^transport_pid, :mock_stream_ref, {:text, "failme"} -> :ok end)
      expect(WebsockexNova.ConnectionHandlerMock, :connection_init, fn _ -> {:ok, %{}} end)
      expect(WebsockexNova.ConnectionHandlerMock, :handle_connect, fn _, state -> {:ok, state} end)
      {:ok, %ClientConn{pid: pid}} = Connection.start_link(opts)
      send(pid, {:websocket_connected, %{}})
      IO.puts("[TEST] Sending request that will fail due to transport error")
      :sent = GenServer.call(pid, {:send_request, {:text, "failme"}, nil, self()})
      IO.puts("[TEST] Simulating transport error event")
      Process.flag(:trap_exit, true)
      send(pid, {:connection_error, :some_error})
      IO.puts("[TEST] Waiting for error reply after transport error...")
      assert_receive {:EXIT, ^pid, :some_error}, 100
    end
  end

  describe "reconnection and backoff" do
    test "schedules reconnection on disconnect and transitions state", %{transport_pid: transport_pid} do
      opts = default_opts([], transport_pid)
      expect(WebsockexNova.TransportMock, :open, fn _, _, _, _ -> {:ok, transport_pid} end)
      expect(WebsockexNova.TransportMock, :upgrade_to_websocket, fn ^transport_pid, "/", _ -> {:ok, :mock_stream_ref} end)
      expect(WebsockexNova.ConnectionHandlerMock, :connection_init, fn _ -> {:ok, %{}} end)
      expect(WebsockexNova.ConnectionHandlerMock, :handle_connect, fn _, state -> {:ok, state} end)
      expect(WebsockexNova.ErrorHandlerMock, :should_reconnect?, fn _, _, _ -> {true, 10} end)
      expect(WebsockexNova.LoggingHandlerMock, :log_connection_event, fn :schedule_reconnect, _context, _state -> :ok end)

      expect(WebsockexNova.TransportMock, :schedule_reconnection, fn state, callback ->
        # Simulate immediate callback invocation for test
        callback.(10, 1)
        state
      end)

      expect(WebsockexNova.TransportMock, :start_connection, fn state ->
        state
      end)

      {:ok, %ClientConn{pid: pid}} = Connection.start_link(opts)
      send(pid, {:websocket_connected, %{}})
      IO.puts("[TEST] Simulating disconnect event (gun_down)")
      send(pid, {:connection_down, :closed})
      :timer.sleep(30)
      IO.puts("[TEST] Checked process alive after disconnect: #{inspect(Process.alive?(pid))}")
      assert Process.alive?(pid)
    end
  end

  describe "handler invocation and error propagation" do
    test "propagates handler errors to caller and updates state", %{transport_pid: transport_pid} do
      opts = default_opts([], transport_pid)
      expect(WebsockexNova.TransportMock, :open, fn _, _, _, _ -> {:ok, transport_pid} end)
      expect(WebsockexNova.TransportMock, :upgrade_to_websocket, fn ^transport_pid, "/", _ -> {:ok, :mock_stream_ref} end)
      expect(WebsockexNova.ConnectionHandlerMock, :connection_init, fn _ -> {:ok, %{}} end)
      expect(WebsockexNova.ConnectionHandlerMock, :handle_connect, fn _, state -> {:ok, state} end)

      expect(WebsockexNova.MessageHandlerMock, :handle_message, fn %{"msg" => "fail"}, state ->
        {:error, :bad_message, state}
      end)

      {:ok, %ClientConn{pid: pid, stream_ref: _stream_ref}} = Connection.start_link(opts)
      send(pid, {:websocket_connected, %{}})
      send(pid, {:message_event, %{"msg" => "fail"}, self()})
      assert_receive {:error, :bad_message}, 100
    end
  end

  # TODO: Add tests for buffering/flushing, timeout/error, reconnection, handler error propagation
end
