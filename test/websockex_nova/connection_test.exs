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

  defp default_opts(overrides \\ [], transport_pid) do
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
      expect(WebsockexNova.TransportMock, :open, fn host, port, opts, _supervisor ->
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

  # TODO: Add tests for buffering/flushing, timeout/error, reconnection, handler error propagation
end
