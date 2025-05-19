defmodule WebsockexNova.ClientMacro do
  @moduledoc """
  Macro for building WebsockexNova client modules with minimal boilerplate.

  This macro provides a convenient way to create domain-specific WebSocket client modules
  that wrap the generic WebsockexNova.Client with service-specific functionality.

  ## Basic Usage

      defmodule MyApp.MyClient do
        use WebsockexNova.ClientMacro, adapter: MyApp.MyAdapter

        # Add domain-specific methods:
        def subscribe_to_custom_channel(conn, instrument_id, opts \\ nil) do
          channel = "custom.\#{instrument_id}.events"
          subscribe(conn, channel, opts)
        end
      end

  ## What this macro does

  - Injects all common client functions (connect, authenticate, send_json, subscribe, etc.)
  - Configures the client to use your specified adapter
  - Provides default connection options that can be overridden
  - Enables dependency injection for testing via application config
  - Allows you to add domain-specific helper methods

  ## Options

  - `:adapter` (required) - The adapter module to use for connections
  - `:default_options` (optional) - Default connection options as a map

  ## Examples

  ### Trading client with custom methods

      defmodule MyApp.TradingClient do
        use WebsockexNova.ClientMacro, 
          adapter: MyApp.TradingAdapter,
          default_options: %{
            heartbeat_interval: 10_000,
            reconnect_delay: 1_000
          }

        def place_order(conn, order_params) do
          send_json(conn, %{
            method: "place_order",
            params: order_params
          })
        end

        def subscribe_to_orderbook(conn, symbol, depth \\ 10) do
          subscribe(conn, "orderbook.\#{symbol}", %{depth: depth})
        end

        def subscribe_to_trades(conn, symbol) do
          subscribe(conn, "trades.\#{symbol}", %{})
        end
      end

      # Usage:
      {:ok, conn} = MyApp.TradingClient.connect()
      {:ok, _} = MyApp.TradingClient.authenticate(conn, %{api_key: "key", api_secret: "secret"})
      {:ok, _} = MyApp.TradingClient.subscribe_to_orderbook(conn, "BTC-USD")

  ### Chat client with typed message sending

      defmodule MyApp.ChatClient do
        use WebsockexNova.ClientMacro,
          adapter: MyApp.ChatAdapter

        def send_chat_message(conn, room_id, message) do
          send_json(conn, %{
            type: "message",
            room: room_id,
            text: message,
            timestamp: DateTime.utc_now()
          })
        end

        def join_room(conn, room_id) do
          send_json(conn, %{type: "join", room: room_id})
        end

        def leave_room(conn, room_id) do
          send_json(conn, %{type: "leave", room: room_id})
        end

        def set_typing_status(conn, room_id, is_typing) do
          send_json(conn, %{
            type: "typing",
            room: room_id,
            typing: is_typing
          })
        end
      end

  ### IoT client with device management

      defmodule MyApp.IoTClient do
        use WebsockexNova.ClientMacro,
          adapter: MyApp.IoTAdapter,
          default_options: %{
            transport: :tcp,
            port: 8883,
            protocol: "mqtt-websocket"
          }

        def register_device(conn, device_id, metadata) do
          send_json(conn, %{
            action: "register",
            device_id: device_id,
            metadata: metadata
          })
        end

        def send_telemetry(conn, device_id, data) do
          send_json(conn, %{
            action: "telemetry",
            device_id: device_id,
            data: data,
            timestamp: System.system_time(:second)
          })
        end

        def update_device_shadow(conn, device_id, desired_state) do
          send_json(conn, %{
            action: "update_shadow",
            device_id: device_id,
            state: %{desired: desired_state}
          })
        end
      end

  ## Testing Support

  The macro supports dependency injection for testing by allowing you to configure
  the underlying client module:

      # In config/test.exs
      config :websockex_nova, :client_module, MyApp.MockClient

      # In your test
      defmodule MyApp.TradingClientTest do
        use ExUnit.Case

        test "places order successfully" do
          {:ok, conn} = MyApp.TradingClient.connect()
          {:ok, response} = MyApp.TradingClient.place_order(conn, %{symbol: "BTC-USD", size: 1})
          assert response.order_id
        end
      end

  ## Available Functions

  The following functions are automatically available in your client module:

  - `connect/0`, `connect/1` - Establish WebSocket connection
  - `close/1` - Close connection
  - `ping/1` - Send ping frame
  - `send_text/2` - Send text message
  - `send_json/2` - Send JSON-encoded message
  - `send_binary/2` - Send binary message
  - `send_frame/3` - Send specific frame type
  - `send_message/2` - Send via message handler
  - `subscribe/3` - Subscribe to channel
  - `unsubscribe/2` - Unsubscribe from channel
  - `authenticate/2` - Perform authentication

  ## Tips

  1. Keep domain logic in your client module, not in the adapter
  2. Use typed functions for common operations (like `subscribe_to_trades/2`)
  3. Consider adding error handling in your domain-specific methods
  4. Use default_options for environment-specific configuration
  5. Document your domain-specific methods for better usability

  See `WebsockexNova.Examples.ClientDeribitMacro` for a complete example.
  """

  defmacro __using__(opts) do
    adapter = Keyword.fetch!(opts, :adapter)
    default_options = Keyword.get(opts, :default_options, %{})

    quote do
      # Get client module from config or use WebsockexNova.Client as default
      # This allows for dependency injection in tests
      defp client_module do
        Application.get_env(:websockex_nova, :client_module, WebsockexNova.Client)
      end

      # Define the function that returns default options
      def default_opts, do: unquote(Macro.escape(default_options))

      @doc """
      Connect to WebSocket API with sensible defaults from the adapter.
      User-supplied opts override defaults.
      """
      def connect(opts \\ %{}) when is_map(opts) do
        # 1. Adapter protocol defaults
        {:ok, adapter_defaults} = unquote(adapter).connection_info(%{})
        # 2. Merge in client/app-level defaults (lowest priority after adapter)
        merged = Map.merge(adapter_defaults, default_opts())
        # 3. Merge in user opts (highest priority)
        merged_opts = Map.merge(merged, opts)
        client_module().connect(unquote(adapter), merged_opts)
      end

      @doc """
      Authenticate using credentials.
      """
      def authenticate(conn, credentials \\ %{}, opts \\ nil) do
        client_module().authenticate(conn, credentials, opts)
      end

      @doc """
      Subscribe to a channel.
      """
      def subscribe(conn, channel, opts \\ nil) do
        client_module().subscribe(conn, channel, opts)
      end

      @doc """
      Unsubscribe from a channel.
      """
      def unsubscribe(conn, channel, opts \\ nil) do
        client_module().unsubscribe(conn, channel, opts)
      end

      @doc """
      Send a JSON message.
      """
      def send_json(conn, payload, opts \\ nil) do
        client_module().send_json(conn, payload, opts)
      end

      @doc """
      Send a text message.
      """
      def send_text(conn, text, opts \\ nil) do
        client_module().send_text(conn, text, opts)
      end

      @doc """
      Send a ping and wait for pong response.
      """
      def ping(conn, opts \\ nil) do
        client_module().ping(conn, opts)
      end

      @doc """
      Get connection status.
      """
      def status(conn, opts \\ nil) do
        client_module().status(conn, opts)
      end

      @doc """
      Close the connection.
      """
      def close(conn) do
        client_module().close(conn)
      end

      # Allow clients to override default options by redefining this function
      defoverridable default_opts: 0
    end
  end
end
