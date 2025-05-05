defmodule WebsockexNova do
  @moduledoc """
  WebsockexNova is a robust WebSocket client library for Elixir with a pluggable adapter architecture.

  ## Architecture Overview

  WebsockexNova employs a "thin adapter" architecture that separates concerns through:

  1. **Behavioral Interfaces**: Well-defined behaviours for various aspects of WebSocket handling
  2. **Default Implementations**: Ready-to-use default implementations of these behaviours
  3. **Platform Adapters**: Thin adapters that bridge to specific platforms/services
  4. **Connection Management**: Process-based connection handling with ownership semantics

  This modular design allows for maximum flexibility while minimizing boilerplate code.

  ## Key Components

  * **Connection**: The core GenServer process managing the WebSocket lifecycle
  * **Client**: A convenient API for interacting with connections
  * **Behaviours**: Interfaces for connection, message, authentication, error handling, etc.
  * **Defaults**: Ready-to-use implementations of all behaviours
  * **Platform Adapters**: Thin adapters for specific WebSocket services

  ## Basic Usage

  ```elixir
  # Start a connection to the Echo service
  {:ok, conn} = WebsockexNova.Connection.start_link(
    adapter: WebsockexNova.Platform.Echo.Adapter
  )

  # Send a message and get the response
  {:text, response} = WebsockexNova.Client.send_text(conn, "Hello")
  ```

  ## Using with Custom Handlers

  ```elixir
  # Start a connection with custom handlers
  {:ok, conn} = WebsockexNova.Connection.start_link(
    adapter: WebsockexNova.Platform.Echo.Adapter,
    message_handler: MyApp.MessageHandler,
    connection_handler: MyApp.ConnectionHandler
  )
  ```

  ## Creating a Client Module

  ```elixir
  defmodule MyApp.WebSocketClient do
    use GenServer

    def start_link(opts \\\\ []) do
      GenServer.start_link(__MODULE__, opts)
    end

    def init(opts) do
      # Start the WebSocket connection
      {:ok, conn} = WebsockexNova.Connection.start_link(
        adapter: WebsockexNova.Platform.Echo.Adapter
      )

      {:ok, %{conn: conn}}
    end

    # API functions
    def send_message(client, message) do
      GenServer.call(client, {:send, message})
    end

    # Callbacks
    def handle_call({:send, message}, _from, %{conn: conn} = state) do
      result = WebsockexNova.Client.send_text(conn, message)
      {:reply, result, state}
    end
  end
  ```

  ## Implementing Custom Handlers

  Each aspect of WebSocket communication can be customized by implementing one of
  the behaviours in `WebsockexNova.Behaviours`:

  ```elixir
  defmodule MyApp.MessageHandler do
    @behaviour WebsockexNova.Behaviours.MessageHandler

    @impl true
    def init(opts) do
      {:ok, %{messages: []}}
    end

    @impl true
    def handle_message(frame_type, data, state) do
      IO.puts("Received \#{frame_type} message: \#{inspect(data)}")
      new_state = update_in(state.messages, &[{frame_type, data} | &1])
      {:ok, new_state}
    end
  end
  ```

  ## Creating a Platform Adapter

  To support a new WebSocket service, implement the `WebsockexNova.Platform.Adapter` behavior:

  ```elixir
  defmodule MyApp.CustomAdapter do
    use WebsockexNova.Platform.Adapter,
      default_host: "api.example.com",
      default_port: 443,
      default_path: "/websocket"

    @impl true
    def handle_platform_message(message, state) do
      # Custom message handling
      {:reply, {:text, "Processed: \#{inspect(message)}"}, state}
    end

    @impl true
    def encode_auth_request(credentials) do
      {:text, Jason.encode!(%{
        type: "auth",
        key: credentials.api_key,
        secret: credentials.api_secret
      })}
    end

    @impl true
    def encode_subscription_request(channel, params) do
      {:text, Jason.encode!(%{
        type: "subscribe",
        channel: channel,
        params: params
      })}
    end

    @impl true
    def encode_unsubscription_request(channel) do
      {:text, Jason.encode!(%{
        type: "unsubscribe",
        channel: channel
      })}
    end
  end
  ```

  ## Available Behaviours

  * `ConnectionHandler`: Handle connection lifecycle events
  * `MessageHandler`: Process incoming WebSocket messages
  * `SubscriptionHandler`: Manage channel subscriptions
  * `AuthHandler`: Handle authentication
  * `ErrorHandler`: Process error scenarios
  * `RateLimitHandler`: Implement rate limiting
  * `LoggingHandler`: Provide logging functionality
  * `MetricsCollector`: Collect metrics about WebSocket operations

  Each behavior has a corresponding default implementation in the `WebsockexNova.Defaults` namespace.
  """
end
