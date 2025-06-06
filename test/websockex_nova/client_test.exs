defmodule WebsockexNova.ClientTest do
  use ExUnit.Case, async: true

  alias WebsockexNova.Behaviors.AuthHandler
  alias WebsockexNova.Behaviors.ConnectionHandler
  alias WebsockexNova.Behaviors.ErrorHandler
  alias WebsockexNova.Behaviors.MessageHandler
  alias WebsockexNova.Behaviors.SubscriptionHandler
  alias WebsockexNova.Client
  alias WebsockexNova.ClientConn
  alias WebsockexNova.Defaults.DefaultRateLimitHandler

  # Mock transport for testing without real connections
  defmodule MockTransport do
    @moduledoc false
    @behaviour WebsockexNova.Transport

    @impl true
    def open(host, port, path, opts \\ %{}) do
      transport_pid =
        spawn(fn ->
          receive_loop({host, port, path, opts})
        end)

      send(self(), {:open_connection, host, port, path, opts})

      {:ok,
       %WebsockexNova.ClientConn{
         transport: __MODULE__,
         transport_pid: transport_pid,
         stream_ref: make_ref(),
         adapter: Map.get(opts, :adapter),
         adapter_state: Map.get(opts, :adapter_state),
         callback_pids: Enum.filter([Map.get(opts, :callback_pid)], & &1)
       }}
    end

    defp receive_loop(conn_info) do
      receive do
        {:get_last_connection, from} ->
          {host, port, path, opts} = conn_info
          send(from, {:last_connection, host, port, path, opts})
          receive_loop(conn_info)

        _ ->
          receive_loop(conn_info)
      end
    end

    @impl true
    def upgrade_to_websocket(pid, path, _headers) do
      send(self(), {:upgrade_ws, pid, path})
      {:ok, make_ref()}
    end

    @impl true
    def send_frame(_pid, stream_ref, frame) do
      case frame do
        {:text, "NOECHO"} ->
          # Suppress echo for timeout test
          :ok

        {:text, content} ->
          send(self(), {:websockex_nova, {:websocket_frame, stream_ref, {:text, content}}})

        :ping ->
          send(self(), {:websockex_nova, {:websocket_frame, stream_ref, :pong}})

        _ ->
          send(self(), {:frame_received, stream_ref, frame})
      end

      :ok
    end

    @impl true
    def close(_pid) do
      send(self(), :connection_closed)
      :ok
    end

    @impl true
    def process_transport_message(message, state) do
      case message do
        {:get_last_connection, from} ->
          send(from, {:last_connection, state.host, state.port, state.path, state.options})
          {:ok, state}

        _ ->
          {:ok, state}
      end
    end

    @impl true
    def get_state(_transport_pid) do
      {:ok, %{status: :connected}}
    end

    @impl true
    def schedule_reconnection(_transport_pid, _after_time) do
      :ok
    end

    @impl true
    def start_connection(state) do
      {:ok, state}
    end
  end

  # Mock adapter for testing
  defmodule MockAdapter do
    @moduledoc false
    @behaviour AuthHandler
    @behaviour ConnectionHandler
    @behaviour ErrorHandler
    @behaviour MessageHandler
    @behaviour SubscriptionHandler

    # ConnectionHandler callbacks
    @impl ConnectionHandler
    def init(_opts), do: {:ok, %{}}

    @impl ConnectionHandler
    def handle_connect(_info, state), do: {:ok, state}

    @impl ConnectionHandler
    def handle_disconnect(_reason, state), do: {:ok, state}

    @impl ConnectionHandler
    def handle_frame(_frame_type, _frame_data, state), do: {:ok, state}

    @impl ConnectionHandler
    def handle_timeout(state), do: {:ok, state}

    @impl ConnectionHandler
    def ping(_stream_ref, state), do: {:ok, state}

    @impl ConnectionHandler
    def status(_stream_ref, state), do: {:ok, :connected, state}

    # MessageHandler callbacks
    @impl MessageHandler
    def message_init(_opts), do: {:ok, %{}}

    @impl MessageHandler
    def handle_message(message, state), do: {:ok, message, state}

    @impl MessageHandler
    def validate_message(message), do: {:ok, message}

    @impl MessageHandler
    def message_type(_message), do: :text

    @impl MessageHandler
    def encode_message(message, _state) when is_map(message) do
      {:ok, :text, message}
    end

    @impl MessageHandler
    def encode_message(message, _state) do
      {:ok, :text, to_string(message)}
    end

    # Support for the 3-parameter version
    def encode_message(message_type, message, _state) do
      case message_type do
        :text -> {:ok, message}
        :json -> {:ok, message}
        _ -> {:ok, to_string(message)}
      end
    end

    # SubscriptionHandler callbacks
    @impl SubscriptionHandler
    def subscription_init(_opts), do: {:ok, %{}}

    @impl SubscriptionHandler
    def subscribe(channel, state, _opts), do: {:ok, "{\"subscribe\":\"#{channel}\"}", state}

    @impl SubscriptionHandler
    def unsubscribe(channel, state), do: {:ok, "{\"unsubscribe\":\"#{channel}\"}", state}

    @impl SubscriptionHandler
    def handle_subscription_response(response, state), do: {:ok, response, state}

    @impl SubscriptionHandler
    def active_subscriptions(_state), do: []

    @impl SubscriptionHandler
    def find_subscription_by_channel(_channel, _state), do: nil

    # AuthHandler callbacks
    @impl AuthHandler
    def generate_auth_data(state), do: {:ok, "{\"auth\":true}", state}

    @impl AuthHandler
    def handle_auth_response(_response, state), do: {:ok, state}

    @impl AuthHandler
    def needs_reauthentication?(_state), do: false

    @impl AuthHandler
    def authenticate(_stream_ref, _credentials, state), do: {:ok, :authenticated, state}

    # ErrorHandler callbacks
    @impl ErrorHandler
    def handle_error(_error, _context, state), do: {:error, :test_error, state}

    @impl ErrorHandler
    def should_reconnect?(_error, _attempt, _state), do: {true, 0}

    @impl ErrorHandler
    def log_error(_error, _context, _state), do: :ok

    @impl ErrorHandler
    def classify_error(_error, _state), do: :recoverable

    # Connection info
    @impl ConnectionHandler
    def connection_info(_state) do
      {:ok,
       %{
         host: "test.example.com",
         port: 443,
         path: "/ws"
       }}
    end
  end

  describe "client API" do
    setup do
      # Replace the transport module in our test by dynamically overriding the transport/0 function
      # We'll use Application.put_env for this instead of meck or persistent_term
      original_transport = Application.get_env(:websockex_nova, :transport)
      Application.put_env(:websockex_nova, :transport, MockTransport)

      on_exit(fn ->
        # Restore the original transport if it existed
        if original_transport do
          Application.put_env(:websockex_nova, :transport, original_transport)
        else
          Application.delete_env(:websockex_nova, :transport)
        end
      end)

      :ok
    end

    test "connect/2 establishes a connection" do
      {:ok, conn} =
        Client.connect(MockAdapter, %{
          host: "example.com",
          port: 443,
          path: "/ws"
        })

      assert %ClientConn{} = conn
      assert conn.adapter == MockAdapter
      assert is_pid(conn.transport_pid)
      assert is_reference(conn.stream_ref)
    end

    test "connect/2 stores configuration in adapter_state" do
      defaults = %{
        # Connection/Transport
        host: "example.com",
        port: 443,
        path: "/ws",
        headers: [],
        timeout: 10_000,
        transport: :tls,
        transport_opts: %{},
        protocols: [:http],
        retry: 10,
        backoff_type: :exponential,
        base_backoff: 2_000,
        ws_opts: %{},
        callback_pid: nil,

        # Rate Limiting
        rate_limit_handler: DefaultRateLimitHandler,
        rate_limit_opts: %{
          mode: :normal,
          capacity: 120,
          refill_rate: 10,
          refill_interval: 1_000,
          queue_limit: 200,
          cost_map: %{
            subscription: 5,
            auth: 10,
            query: 1,
            order: 10
          }
        },

        # Logging
        logging_handler: WebsockexNova.Defaults.DefaultLoggingHandler,
        log_level: :info,
        log_format: :plain,

        # Metrics
        metrics_collector: nil,

        # Authentication
        auth_handler: WebsockexNova.Defaults.DefaultAuthHandler,
        credentials: %{
          api_key: "test",
          secret: "secret"
        },
        auth_refresh_threshold: 60,

        # Subscription
        subscription_handler: WebsockexNova.Defaults.DefaultSubscriptionHandler,
        subscription_timeout: 30,

        # Message
        message_handler: WebsockexNova.Defaults.DefaultMessageHandler,

        # Error Handling
        error_handler: WebsockexNova.Defaults.DefaultErrorHandler,
        max_reconnect_attempts: 5,
        reconnect_attempts: 0,
        ping_interval: 30_000
      }

      {:ok, conn} =
        Client.connect(MockAdapter, defaults)

      # Configuration should be in adapter_state
      assert conn.adapter_state.auth_status == :unauthenticated
      assert conn.adapter_state.reconnect_attempts == 0
      assert conn.adapter_state.credentials == %{api_key: "test", secret: "secret"}
      assert conn.adapter_state.auth_refresh_threshold == 60
      assert conn.adapter_state.subscription_timeout == 30
      assert Map.has_key?(conn.adapter_state, :subscriptions)

      # Verify that configuration persists across updates
      assert conn.reconnection.max_reconnect_attempts == 5
    end

    test "send_text/3 sends a text message" do
      {:ok, conn} =
        Client.connect(MockAdapter, %{
          host: "example.com",
          port: 443,
          path: "/ws"
        })

      {:ok, response} = Client.send_text(conn, "Hello, World!")
      assert response == "Hello, World!"
    end

    test "send_json/3 sends a JSON message" do
      {:ok, conn} =
        Client.connect(MockAdapter, %{
          host: "example.com",
          port: 443,
          path: "/ws"
        })

      {:ok, response} = Client.send_json(conn, %{greeting: "Hello, JSON!"})
      assert response == %{greeting: "Hello, JSON!"}
    end

    test "subscribe/3 subscribes to a channel" do
      {:ok, conn} =
        Client.connect(MockAdapter, %{
          host: "example.com",
          port: 443,
          path: "/ws"
        })

      {:ok, response} = Client.subscribe(conn, "test.channel")
      assert response == ~s({"subscribe":"test.channel"})
    end

    test "unsubscribe/3 unsubscribes from a channel" do
      {:ok, conn} =
        Client.connect(MockAdapter, %{
          host: "example.com",
          port: 443,
          path: "/ws"
        })

      {:ok, response} = Client.unsubscribe(conn, "test.channel")
      assert response == ~s({"unsubscribe":"test.channel"})
    end

    test "authenticate/3 sends authentication credentials" do
      {:ok, conn} =
        Client.connect(MockAdapter, %{
          host: "example.com",
          port: 443,
          path: "/ws"
        })

      {:ok, updated_conn, response} = Client.authenticate(conn, %{api_key: "key", api_secret: "secret"})
      assert %ClientConn{} = updated_conn
      assert response == "{\"auth\":true}"
    end

    test "ping/2 sends a ping frame" do
      {:ok, conn} =
        Client.connect(MockAdapter, %{
          host: "example.com",
          port: 443,
          path: "/ws"
        })

      {:ok, response} = Client.ping(conn)
      assert response == :pong
    end

    test "close/1 closes the connection" do
      {:ok, conn} =
        Client.connect(MockAdapter, %{
          host: "example.com",
          port: 443,
          path: "/ws"
        })

      result = Client.close(conn)
      assert result == :ok
    end

    test "connect/2 with keyword list transport_opts converts to map" do
      # Test with a keyword list that will cause errors if not converted
      transport_kw_list = [
        verify: :verify_peer,
        cacertfile: "/path/to/cert",
        server_name_indication: ~c"example.com"
      ]

      options = %{
        host: "example.com",
        port: 443,
        path: "/ws",
        transport_opts: transport_kw_list
      }

      # This should not raise - it should convert the keyword list to a map
      assert {:ok, conn} = Client.connect(MockAdapter, options)
      assert is_pid(conn.transport_pid)
    end

    test "connect/2 with empty transport_opts defaults to empty map" do
      options = %{
        host: "example.com",
        port: 443,
        path: "/ws",
        transport_opts: nil
      }

      # This should not raise - nil should be converted to empty map
      assert {:ok, conn} = Client.connect(MockAdapter, options)
      assert is_pid(conn.transport_pid)
    end

    test "connect/2 with duplicate keys in keyword list takes last value" do
      # Test edge case where keyword list has duplicate keys
      transport_kw_list = [
        verify: :verify_none,
        # This should override the first value
        verify: :verify_peer,
        server_name_indication: ~c"example.com"
      ]

      options = %{
        host: "example.com",
        port: 443,
        path: "/ws",
        transport_opts: transport_kw_list
      }

      # Should handle duplicate keys gracefully (Map.new takes last value)
      assert {:ok, conn} = Client.connect(MockAdapter, options)
      assert is_pid(conn.transport_pid)
    end

    test "register_callback/2 adds a callback process" do
      {:ok, conn} =
        Client.connect(MockAdapter, %{
          host: "example.com",
          port: 443,
          path: "/ws"
        })

      {:ok, new_conn} = Client.register_callback(conn, self())
      assert MapSet.member?(new_conn.callback_pids, self())
    end

    test "unregister_callback/2 removes a callback process" do
      {:ok, conn} =
        Client.connect(MockAdapter, %{
          host: "example.com",
          port: 443,
          path: "/ws"
        })

      {:ok, conn_with_callback} = Client.register_callback(conn, self())
      {:ok, conn_without_callback} = Client.unregister_callback(conn_with_callback, self())
      assert MapSet.size(conn_without_callback.callback_pids) == 0
    end

    test "authenticate/3 updates auth_status to :authenticated" do
      defmodule AuthStatusAdapter do
        @moduledoc false
        @behaviour AuthHandler
        @behaviour ConnectionHandler
        @behaviour ErrorHandler
        @behaviour MessageHandler
        @behaviour SubscriptionHandler

        def init(_), do: {:ok, %{}}
        def connection_info(_), do: {:ok, %{host: "example.com", port: 443, path: "/ws"}}
        def encode_message(msg, _), do: {:ok, :text, msg}
        def subscribe(_, state, _), do: {:ok, "sub", state}
        def unsubscribe(_, state), do: {:ok, "unsub", state}
        def handle_message(msg, state), do: {:ok, msg, state}
        def validate_message(msg), do: {:ok, msg}
        def message_type(_), do: :text
        def subscription_init(_), do: {:ok, %{}}
        def handle_subscription_response(resp, state), do: {:ok, resp, state}
        def active_subscriptions(_), do: []
        def find_subscription_by_channel(_, _), do: nil
        def handle_error(_, _, state), do: {:ok, state}
        def should_reconnect?(_, _, _), do: {false, 0}
        def log_error(_, _, _), do: :ok
        def classify_error(_, _), do: :normal

        def generate_auth_data(state) do
          {:ok, "{\"auth\":true}", state}
        end

        def handle_auth_response(_response, state) do
          {:ok, Map.put(state, :auth_status, :authenticated)}
        end

        def needs_reauthentication?(_), do: false
        def authenticate(_, _, state), do: {:ok, state}
      end

      Application.put_env(:websockex_nova, :transport, WebsockexNova.ClientTest.MockTransport)

      {:ok, conn} =
        WebsockexNova.Client.connect(AuthStatusAdapter, %{
          host: "example.com",
          port: 443,
          path: "/ws"
        })

      # Simulate the expected response in the mailbox
      send(self(), {:websockex_nova, {:websocket_frame, conn.stream_ref, {:text, "{\"auth\":true}"}}})

      {:ok, updated_conn, _response} = WebsockexNova.Client.authenticate(conn, %{api_key: "key", api_secret: "secret"})
      assert updated_conn.adapter_state.auth_status == :authenticated
    end
  end

  describe "wait_for_response/2 filtering and matcher" do
    setup do
      # Use the MockTransport and MockAdapter
      Application.put_env(:websockex_nova, :transport, MockTransport)
      {:ok, conn} = Client.connect(MockAdapter, %{host: "example.com", port: 443, path: "/ws"})
      %{conn: conn}
    end

    test "filters out non-user messages and returns user message", %{conn: conn} do
      stream_ref = conn.stream_ref
      # Simulate non-user messages
      send(self(), {:websockex_nova, {:connection_up, :http}})
      send(self(), {:websockex_nova, {:websocket_upgrade, stream_ref, []}})
      send(self(), {:websockex_nova, {:http_response, stream_ref, :fin, 200, []}})
      send(self(), {:websockex_nova, {:websocket_frame, stream_ref, :ping}})
      send(self(), {:websockex_nova, {:websocket_frame, stream_ref, :pong}})
      send(self(), {:websockex_nova, {:websocket_frame, stream_ref, {:binary, <<1, 2, 3>>}}})
      send(self(), {:websockex_nova, {:websocket_frame, stream_ref, {:close, 1000, "bye"}}})
      # Now send the user message
      send(self(), {:websockex_nova, {:websocket_frame, stream_ref, {:text, "user response"}}})
      assert Client.send_text(conn, "ignored") == {:ok, "user response"}
    end

    test "returns error on timeout if no user message", %{conn: conn} do
      stream_ref = conn.stream_ref
      send(self(), {:websockex_nova, {:connection_up, :http}})
      send(self(), {:websockex_nova, {:websocket_frame, stream_ref, :ping}})
      opts = %{timeout: 50}
      # Use special message to suppress echo in MockTransport
      assert Client.send_text(conn, "NOECHO", opts) == {:error, :timeout}
    end

    test "returns error if error message received", %{conn: conn} do
      send(self(), {:websockex_nova, :error, :some_error})
      assert Client.send_text(conn, "ignored") == {:error, :some_error}
    end

    test "supports custom matcher function", %{conn: conn} do
      stream_ref = conn.stream_ref
      # Custom matcher: match only websocket_frame with {:text, "special"}
      matcher = fn
        {:websockex_nova, {:websocket_frame, ^stream_ref, {:text, "special"}}} -> {:ok, "special"}
        _ -> :skip
      end

      # Send a normal user message (should be skipped)
      send(self(), {:websockex_nova, {:websocket_frame, stream_ref, {:text, "not special"}}})
      # Send the special message
      send(self(), {:websockex_nova, {:websocket_frame, stream_ref, {:text, "special"}}})
      opts = %{matcher: matcher}
      assert Client.send_text(conn, "ignored", opts) == {:ok, "special"}
    end

    test "custom matcher can match on non-standard message", %{conn: conn} do
      matcher = fn
        {:websockex_nova, {:custom, :ok}} -> {:ok, :custom}
        _ -> :skip
      end

      send(self(), {:websockex_nova, {:custom, :ok}})
      opts = %{matcher: matcher}
      # Should match custom message
      assert Client.send_text(conn, "ignored", opts) == {:ok, :custom}
    end

    test "filters out multiple non-user messages before user message", %{conn: conn} do
      stream_ref = conn.stream_ref

      for msg <- [
            {:websockex_nova, {:connection_up, :http}},
            {:websockex_nova, {:websocket_frame, stream_ref, :ping}},
            {:websockex_nova, {:websocket_frame, stream_ref, :pong}},
            {:websockex_nova, {:websocket_frame, stream_ref, {:binary, <<1, 2, 3>>}}},
            {:websockex_nova, {:websocket_frame, stream_ref, {:close, 1000, "bye"}}}
          ] do
        send(self(), msg)
      end

      send(self(), {:websockex_nova, {:websocket_frame, stream_ref, {:text, "final user msg"}}})
      assert Client.send_text(conn, "ignored") == {:ok, "final user msg"}
    end
  end
end
