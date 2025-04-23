defmodule WebsockexNova.Client do
  @moduledoc """
  Main client API for WebsockexNova WebSocket connections.

  This module provides a high-level, user-friendly API for interacting with WebSocket connections
  using WebsockexNova. It delegates operations to the transport layer and adapter implementations
  while providing a consistent interface regardless of the underlying transport or adapter.

  ## Usage

  ```elixir
  # Connect to a WebSocket server using an adapter
  {:ok, conn} = WebsockexNova.Client.connect(MyApp.WebSocket.Adapter, %{
    host: "example.com",
    port: 443,
    path: "/ws",
    transport_opts: [transport: :tls]
  })

  # Send a JSON message
  {:ok, response} = WebsockexNova.Client.send_json(conn, %{type: "ping"})

  # Subscribe to a channel
  {:ok, subscription} = WebsockexNova.Client.subscribe(conn, "market.updates")

  # Authenticate with credentials
  {:ok, auth_result} = WebsockexNova.Client.authenticate(conn, %{api_key: "key", secret: "secret"})

  # Close the connection
  :ok = WebsockexNova.Client.close(conn)
  ```

  ## Adapter Integration

  The client API works with any adapter that implements the required behaviors:

  - `WebsockexNova.Behaviors.ConnectionHandler`
  - `WebsockexNova.Behaviors.MessageHandler`
  - `WebsockexNova.Behaviors.SubscriptionHandler`
  - `WebsockexNova.Behaviors.AuthHandler`
  - `WebsockexNova.Behaviors.ErrorHandler`

  If an adapter doesn't implement a behavior, the client falls back to using default implementations
  from the `WebsockexNova.Defaults` namespace.

  ## Custom Matcher Example

  You can pass a custom matcher function to filter or extract specific responses:

      matcher = fn
        {:websockex_nova, {:websocket_frame, _stream_ref, {:text, "special"}}} -> {:ok, "special"}
        _ -> :skip
      end

      opts = %{matcher: matcher}
      {:ok, response} = WebsockexNova.Client.send_text(conn, "ignored", opts)
      # response == "special"

  The matcher function receives each message and should return:
  - `{:ok, value}` to match and return the value
  - `:skip` to ignore and continue waiting
  """
  alias WebsockexNova.Behaviors.AuthHandler
  alias WebsockexNova.Behaviors.MessageHandler
  alias WebsockexNova.Behaviors.SubscriptionHandler
  alias WebsockexNova.Client.Handlers
  alias WebsockexNova.ClientConn
  alias WebsockexNova.Defaults.DefaultAuthHandler
  alias WebsockexNova.Defaults.DefaultMessageHandler
  alias WebsockexNova.Defaults.DefaultSubscriptionHandler

  require Logger

  # Default transport module, can be overridden in tests
  @default_transport WebsockexNova.Gun.ConnectionWrapper
  @default_timeout 30_000

  @typedoc "Connection configuration options"
  @type connect_options :: %{
          host: String.t(),
          port: pos_integer(),
          path: String.t(),
          headers: Keyword.t() | map(),
          transport_opts: map() | nil,
          timeout: pos_integer() | nil
        }

  @typedoc "Message options"
  @type message_options :: %{
          timeout: pos_integer() | nil
        }

  @typedoc "Subscribe options"
  @type subscribe_options :: %{
          timeout: pos_integer() | nil
        }

  @typedoc "Authentication options"
  @type auth_options :: %{
          timeout: pos_integer() | nil
        }

  @typedoc "Connection response"
  @type connection_result :: {:ok, ClientConn.t()} | {:error, term()}

  @typedoc "Message response"
  @type message_result :: {:ok, term()} | {:error, term()}

  @typedoc "Subscription response"
  @type subscription_result :: {:ok, term()} | {:error, term()}

  @typedoc "Authentication response"
  @type auth_result :: {:ok, term()} | {:error, term()}

  @typedoc "Status response"
  @type status_result :: {:ok, atom()} | {:error, term()}

  @doc """
  Connects to a WebSocket server using the specified adapter.

  This function initializes the adapter, retrieves connection information,
  establishes a connection using the transport layer, and upgrades to WebSocket.

  ## Parameters

  * `adapter` - Module implementing adapter behaviors
  * `options` - Connection options

  ## Options

  * `:host` - Hostname or IP address of the server (required)
  * `:port` - Port number of the server (required)
  * `:path` - WebSocket endpoint path (required)
  * `:headers` - Additional headers for the upgrade request (optional)
  * `:transport_opts` - Transport-specific options (optional)
  * `:timeout` - Connection timeout in milliseconds (default: 30,000)

  ## Returns

  * `{:ok, conn}` on success
  * `{:error, reason}` on failure
  """
  @spec connect(module(), connect_options()) :: connection_result()
  def connect(adapter, options) when is_atom(adapter) and is_map(options) do
    require Logger

    Logger.debug("[Client.connect] Initializing adapter: #{inspect(adapter)} with options: #{inspect(options)}")

    with {:ok, adapter_state} <- init_adapter(adapter),
         {:ok, connection_info} <- get_connection_info(adapter, adapter_state, options),
         {:ok, transport_opts} <- prepare_transport_options(adapter, connection_info) do
      # Ensure callback_pid is set so we get connection notifications
      transport_opts = Map.put(transport_opts, :callback_pid, self())
      transport_opts = Map.put(transport_opts, :adapter, adapter)
      transport_opts = Map.put(transport_opts, :adapter_state, adapter_state)

      Logger.debug(
        "[Client.connect] Opening connection with info: #{inspect(connection_info)}, transport_opts: #{inspect(transport_opts)}"
      )

      host = Map.fetch!(connection_info, :host)
      port = Map.fetch!(connection_info, :port)
      path = Map.fetch!(connection_info, :path)

      case transport().open(host, port, path, transport_opts) do
        {:ok, conn} ->
          Logger.debug("[Client.connect] Connection established: #{inspect(conn)}")
          {:ok, conn}

        {:error, reason} ->
          Logger.error("WebSocket connection failed: #{inspect(reason)}")
          {:error, reason}
      end
    else
      {:error, reason} ->
        Logger.error("[Client.connect] Error: #{inspect(reason)}")
        {:error, reason}

      other ->
        Logger.error("[Client.connect] Unexpected error: #{inspect(other)}")
        other
    end
  end

  @doc """
  Sends a raw WebSocket frame.

  ## Parameters

  * `conn` - Client connection struct
  * `frame` - WebSocket frame to send

  ## Returns

  * `:ok` on success
  * `{:error, reason}` on failure
  """
  @spec send_frame(ClientConn.t(), WebsockexNova.Transport.frame()) :: :ok | {:error, term()}
  def send_frame(%ClientConn{} = conn, frame) do
    conn.transport.send_frame(conn.transport_pid, conn.stream_ref, frame)
  end

  @doc """
  Sends a text message.

  ## Parameters

  * `conn` - Client connection struct
  * `text` - Text message to send
  * `options` - Message options

  ## Options

  * `:timeout` - Response timeout in milliseconds (default: 30,000)
  * `:matcher` - (optional) A function to match/filter responses. The function should accept a message and return `{:ok, response}` to match, or `:skip` to ignore and continue waiting. See module doc for examples.

  ## Returns

  * `{:ok, response}` on success
  * `{:error, reason}` on failure
  """
  @spec send_text(ClientConn.t(), String.t(), message_options() | nil) :: message_result()
  def send_text(%ClientConn{} = conn, text, options \\ nil) when is_binary(text) do
    message_handler = get_message_handler(conn.adapter)

    with {:ok, encoded} <- message_handler.encode_message(:text, text, conn.adapter_state),
         :ok <- send_frame(conn, {:text, encoded}) do
      wait_for_response(conn, options)
    end
  end

  @doc """
  Sends a JSON message.

  ## Parameters

  * `conn` - Client connection struct
  * `data` - Map to encode as JSON and send
  * `options` - Message options

  ## Options

  * `:timeout` - Response timeout in milliseconds (default: 30,000)
  * `:matcher` - (optional) A function to match/filter responses. The function should accept a message and return `{:ok, response}` to match, or `:skip` to ignore and continue waiting. See module doc for examples.

  ## Returns

  * `{:ok, response}` on success
  * `{:error, reason}` on failure
  """
  @spec send_json(ClientConn.t(), map(), message_options() | nil) :: message_result()
  def send_json(%ClientConn{} = conn, data, options \\ nil) when is_map(data) do
    message_handler = get_message_handler(conn.adapter)

    with {:ok, encoded} <- message_handler.encode_message(:json, data, conn.adapter_state),
         :ok <- send_frame(conn, {:text, encoded}) do
      wait_for_response(conn, options)
    end
  end

  @doc """
  Subscribes to a channel or topic.

  ## Parameters

  * `conn` - Client connection struct
  * `channel` - Channel or topic to subscribe to
  * `options` - Subscription options

  ## Options

  * `:timeout` - Response timeout in milliseconds (default: 30,000)
  * `:matcher` - (optional) A function to match/filter responses. The function should accept a message and return `{:ok, response}` to match, or `:skip` to ignore and continue waiting. See module doc for examples.

  ## Returns

  * `{:ok, subscription}` on success
  * `{:error, reason}` on failure
  """
  @spec subscribe(ClientConn.t(), String.t(), subscribe_options() | nil) :: subscription_result()
  def subscribe(%ClientConn{} = conn, channel, options \\ nil) when is_binary(channel) do
    subscription_handler = get_subscription_handler(conn.adapter)

    with {:ok, sub_message, new_state} <- subscription_handler.subscribe(channel, conn.adapter_state, %{}),
         {:ok, conn} <- update_adapter_state(conn, new_state),
         :ok <- send_frame(conn, {:text, sub_message}) do
      wait_for_response(conn, options)
    end
  end

  @doc """
  Unsubscribes from a channel or topic.

  ## Parameters

  * `conn` - Client connection struct
  * `channel` - Channel or topic to unsubscribe from
  * `options` - Subscription options

  ## Options

  * `:timeout` - Response timeout in milliseconds (default: 30,000)
  * `:matcher` - (optional) A function to match/filter responses. The function should accept a message and return `{:ok, response}` to match, or `:skip` to ignore and continue waiting. See module doc for examples.

  ## Returns

  * `{:ok, result}` on success
  * `{:error, reason}` on failure
  """
  @spec unsubscribe(ClientConn.t(), String.t(), subscribe_options() | nil) :: subscription_result()
  def unsubscribe(%ClientConn{} = conn, channel, options \\ nil) when is_binary(channel) do
    subscription_handler = get_subscription_handler(conn.adapter)

    with {:ok, unsub_message, new_state} <- subscription_handler.unsubscribe(channel, conn.adapter_state),
         {:ok, conn} <- update_adapter_state(conn, new_state),
         :ok <- send_frame(conn, {:text, unsub_message}) do
      wait_for_response(conn, options)
    end
  end

  @doc """
  Authenticates with the WebSocket server.

  ## Parameters

  * `conn` - Client connection struct
  * `credentials` - Authentication credentials
  * `options` - Authentication options

  ## Options

  * `:timeout` - Response timeout in milliseconds (default: 30,000)
  * `:matcher` - (optional) A function to match/filter responses. The function should accept a message and return `{:ok, response}` to match, or `:skip` to ignore and continue waiting. See module doc for examples.

  ## Returns

  * `{:ok, auth_result}` on success
  * `{:error, reason}` on failure
  """
  @spec authenticate(ClientConn.t(), map(), auth_options() | nil) :: auth_result()
  def authenticate(%ClientConn{} = conn, credentials, options \\ nil) when is_map(credentials) do
    auth_handler = get_auth_handler(conn.adapter)

    with {:ok, auth_data, new_state} <-
           auth_handler.generate_auth_data(Map.put(conn.adapter_state, :credentials, credentials)),
         {:ok, conn} <- update_adapter_state(conn, new_state),
         :ok <- send_frame(conn, {:text, auth_data}) do
      wait_for_response(conn, options)
    end
  end

  @doc """
  Sends a ping message to the WebSocket server.

  ## Parameters

  * `conn` - Client connection struct
  * `options` - Message options

  ## Options

  * `:timeout` - Response timeout in milliseconds (default: 30,000)

  ## Returns

  * `{:ok, :pong}` on success
  * `{:error, reason}` on failure
  """
  @spec ping(ClientConn.t(), message_options() | nil) :: {:ok, :pong} | {:error, term()}
  def ping(%ClientConn{} = conn, options \\ nil) do
    Logger.debug("[Client.ping] Sending ping frame to server for conn: #{inspect(conn)}")

    with :ok <- send_frame(conn, :ping) do
      timeout = get_timeout(options)
      stream_ref = conn.stream_ref
      Logger.debug("[Client.ping] Waiting for pong response (timeout: #{timeout} ms)...")

      matcher = fn
        {:websockex_nova, {:websocket_frame, ^stream_ref, {:pong, _}}} ->
          Logger.debug("[Client.ping] Received pong response from server.")
          {:ok, :pong}

        {:websockex_nova, {:websocket_frame, ^stream_ref, :pong}} ->
          Logger.debug("[Client.ping] Received pong response from server.")
          {:ok, :pong}

        {:websockex_nova, :error, reason} ->
          {:error, reason}

        _ ->
          :skip
      end

      start = System.monotonic_time(:millisecond)
      do_wait_for_response(matcher, timeout, start)
    end
  end

  @doc """
  Gets the current connection status.

  ## Parameters

  * `conn` - Client connection struct
  * `options` - Options

  ## Options

  * `:timeout` - Request timeout in milliseconds (default: 30,000)

  ## Returns

  * `{:ok, status}` on success
  * `{:error, reason}` on failure
  """
  @spec status(ClientConn.t(), map() | nil) :: status_result()
  def status(%ClientConn{} = conn, _options \\ nil) do
    GenServer.call(conn.transport_pid, :get_status, get_timeout(nil))
  end

  @doc """
  Closes the WebSocket connection.

  ## Parameters

  * `conn` - Client connection struct

  ## Returns

  * `:ok`
  """
  @spec close(ClientConn.t()) :: :ok
  def close(%ClientConn{} = conn) do
    conn.transport.close(conn.transport_pid)
  end

  @doc """
  Registers a process to receive notifications from the connection.

  ## Parameters

  * `conn` - Client connection struct
  * `pid` - Process ID to register

  ## Returns

  * `{:ok, ClientConn.t()}` with updated connection
  """
  @spec register_callback(ClientConn.t(), pid()) :: {:ok, ClientConn.t()}
  def register_callback(%ClientConn{} = conn, pid) when is_pid(pid) do
    if pid in conn.callback_pids do
      {:ok, conn}
    else
      new_conn = %{conn | callback_pids: [pid | conn.callback_pids]}

      # Notify the transport to monitor this process
      GenServer.cast(conn.transport_pid, {:register_callback, pid})

      {:ok, new_conn}
    end
  end

  @doc """
  Unregisters a process from receiving notifications.

  ## Parameters

  * `conn` - Client connection struct
  * `pid` - Process ID to unregister

  ## Returns

  * `{:ok, ClientConn.t()}` with updated connection
  """
  @spec unregister_callback(ClientConn.t(), pid()) :: {:ok, ClientConn.t()}
  def unregister_callback(%ClientConn{} = conn, pid) when is_pid(pid) do
    if pid in conn.callback_pids do
      new_conn = %{conn | callback_pids: List.delete(conn.callback_pids, pid)}

      # Notify the transport to stop monitoring this process
      GenServer.cast(conn.transport_pid, {:unregister_callback, pid})

      {:ok, new_conn}
    else
      {:ok, conn}
    end
  end

  # Private helpers

  # Initialize the adapter
  defp init_adapter(adapter) do
    if function_exported?(adapter, :init, 1) do
      adapter.init([])
    else
      {:ok, %{}}
    end
  end

  # Get connection information from the adapter or options
  defp get_connection_info(adapter, adapter_state, options) do
    if function_exported?(adapter, :connection_info, 1) do
      case adapter.connection_info(adapter_state) do
        {:ok, connection_info} ->
          # Merge connection info from adapter with options, preferring options if both exist
          {:ok, Map.merge(connection_info, options)}

        other ->
          other
      end
    else
      # Use options directly if adapter doesn't provide connection_info
      {:ok, options}
    end
  end

  # Prepare transport options with handlers configuration
  defp prepare_transport_options(adapter, connection_info) do
    base_opts = Map.get(connection_info, :transport_opts, %{})

    # Configure handlers based on the adapter
    transport_opts = Handlers.configure_handlers(adapter, base_opts)

    {:ok, transport_opts}
  end

  # Get the message handler module
  defp get_message_handler(adapter) do
    if implements?(adapter, MessageHandler) do
      adapter
    else
      DefaultMessageHandler
    end
  end

  # Get the subscription handler module
  defp get_subscription_handler(adapter) do
    if implements?(adapter, SubscriptionHandler) do
      adapter
    else
      DefaultSubscriptionHandler
    end
  end

  # Get the auth handler module
  defp get_auth_handler(adapter) do
    if implements?(adapter, AuthHandler) do
      adapter
    else
      DefaultAuthHandler
    end
  end

  # Check if a module implements a behavior
  defp implements?(module, behavior) do
    :attributes
    |> module.__info__()
    |> Keyword.get_values(:behaviour)
    |> List.flatten()
    |> Enum.member?(behavior)
  rescue
    # Handle case where module doesn't exist or doesn't have __info__
    _ -> false
  end

  # Wait for response with timeout and matcher/filter support
  defp wait_for_response(conn, options) do
    Logger.debug(
      "[Client.wait_for_response] Waiting for response with conn: #{inspect(conn)} and options: #{inspect(options)}"
    )

    timeout = get_timeout(options)
    stream_ref = conn.stream_ref

    matcher =
      if is_map(options) and Map.has_key?(options, :matcher) do
        options.matcher
      else
        fn msg ->
          stream_ref = conn.stream_ref

          case msg do
            {:websockex_nova, {:websocket_frame, ^stream_ref, {:text, response}}} ->
              Logger.debug("[Matcher] Matched text frame: #{inspect(msg)}")
              {:ok, response}

            {:websockex_nova, :response, response} ->
              Logger.debug("[Matcher] Matched legacy response: #{inspect(msg)}")
              {:ok, response}

            {:websockex_nova, :error, reason} ->
              Logger.debug("[Matcher] Matched error: #{inspect(msg)}")
              {:error, reason}

            _ ->
              Logger.debug("[Matcher] Skipped message: #{inspect(msg)}")
              :skip
          end
        end
      end

    start = System.monotonic_time(:millisecond)
    do_wait_for_response(matcher, timeout, start)
  end

  defp do_wait_for_response(matcher, timeout, start) do
    Logger.debug(
      "[Client.do_wait_for_response] Waiting for response with matcher: #{inspect(matcher)}, timeout: #{timeout}, start: #{start}"
    )

    now = System.monotonic_time(:millisecond)
    remaining = max(timeout - (now - start), 0)

    receive do
      msg ->
        case matcher.(msg) do
          {:ok, value} ->
            {:ok, value}

          {:error, reason} ->
            {:error, reason}

          :skip ->
            if remaining > 0 do
              do_wait_for_response(matcher, timeout, start)
            else
              {:error, :timeout}
            end
        end
    after
      remaining ->
        {:error, :timeout}
    end
  end

  # Update the adapter state in the connection
  defp update_adapter_state(conn, new_state) do
    {:ok, %{conn | adapter_state: new_state}}
  end

  # Get timeout value from options or use default
  defp get_timeout(options) do
    if is_map(options) do
      Map.get(options, :timeout, @default_timeout)
    else
      @default_timeout
    end
  end

  # Get the transport module, with support for test overrides
  defp transport do
    Application.get_env(:websockex_nova, :transport, @default_transport)
  end
end
