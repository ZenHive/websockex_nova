defmodule WebsockexNova.ClientTest do
  use ExUnit.Case, async: true

  alias WebsockexNova.Behaviors.AuthHandler
  alias WebsockexNova.Behaviors.ConnectionHandler
  alias WebsockexNova.Behaviors.ErrorHandler
  alias WebsockexNova.Behaviors.MessageHandler
  alias WebsockexNova.Behaviors.SubscriptionHandler
  alias WebsockexNova.Client
  alias WebsockexNova.ClientConn

  # Mock transport for testing without real connections
  defmodule MockTransport do
    @moduledoc false
    @behaviour WebsockexNova.Transport

    @impl true
    def open(host, port, path, opts \\ %{}) do
      send(self(), {:open_connection, host, port, path, opts})

      {:ok,
       %WebsockexNova.ClientConn{
         transport: __MODULE__,
         transport_pid: self(),
         stream_ref: make_ref(),
         adapter: Map.get(opts, :adapter),
         adapter_state: Map.get(opts, :adapter_state),
         callback_pids: Enum.filter([Map.get(opts, :callback_pid)], & &1)
       }}
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
    def process_transport_message(_message, state) do
      {:ok, state}
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
    def encode_message(message_type, _state) do
      {:ok, :text, to_string(message_type)}
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
    def handle_auth_response(response, state), do: {:ok, response, state}

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

      {:ok, response} = Client.authenticate(conn, %{api_key: "key", api_secret: "secret"})
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

    test "register_callback/2 adds a callback process" do
      {:ok, conn} =
        Client.connect(MockAdapter, %{
          host: "example.com",
          port: 443,
          path: "/ws"
        })

      {:ok, new_conn} = Client.register_callback(conn, self())
      assert new_conn.callback_pids == [self()]
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
      assert conn_without_callback.callback_pids == []
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
