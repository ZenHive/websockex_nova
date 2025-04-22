defmodule WebsockexNova.Behaviors.ConnectionHandler do
  @moduledoc """
  Defines the behavior for handling WebSocket connection lifecycle events.

  The ConnectionHandler behavior is a key component of WebsockexNova's thin adapter architecture,
  allowing client applications to customize connection handling logic while the underlying
  transport details are abstracted away.

  ## Thin Adapter Pattern

  As part of WebsockexNova's thin adapter pattern:

  1. This behavior defines a standardized interface that client applications implement
  2. The underlying connection implementation delegates lifecycle events to implementations
  3. The adapter handles the complexities of the transport layer (Gun) for you
  4. Your implementation focuses purely on business logic

  ## Delegation Flow

  When connection events occur:

  1. The Gun adapter receives the raw message
  2. The message is processed by specialized handler modules
  3. Your callback implementation is invoked with normalized parameters
  4. Your return value is processed by the adapter to update the connection state

  ## Common Implementation Patterns

  ```elixir
  defmodule MyApp.ConnectionHandler do
    @behaviour WebsockexNova.Behaviors.ConnectionHandler

    @impl true
    def init(opts) do
      initial_state = %{
        user_id: opts[:user_id],
        last_ping: nil,
        message_count: 0
      }
      {:ok, initial_state}
    end

    @impl true
    def handle_connect(conn_info, state) do
      # Log connection details and send initial handshake
      IO.puts("Connected to \#{conn_info.host}:\#{conn_info.port}")
      {:reply, :text, "{\"type\":\"hello\"}", state}
    end

    @impl true
    def handle_disconnect({:remote, code, reason}, state) do
      # Server closed the connection, attempt to reconnect
      {:reconnect, state}
    end

    @impl true
    def handle_frame(:text, data, state) do
      # Process incoming text frame
      new_state = update_in(state.message_count, &(&1 + 1))
      {:ok, new_state}
    end

    @impl true
    def handle_frame(:ping, _data, state) do
      # Respond to ping with pong (though adapter handles this automatically)
      {:reply, :pong, "", state}
    end
  end
  ```

  ## Callbacks

  * `handle_connect/2` - Process a successful connection
  * `handle_disconnect/2` - Handle disconnection events
  * `handle_frame/3` - Process received WebSocket frames
  * `handle_timeout/1` - (Optional) Handle connection timeouts
  """

  @typedoc """
  Connection information map.

  Contains details about the established connection:
  * `:host` - The remote host (string)
  * `:port` - The remote port (integer)
  * `:path` - The connection path (string)
  * `:protocol` - The negotiated WebSocket protocol (string or nil)
  * `:transport` - The transport protocol (`:tcp` or `:tls`)
  """
  @type conn_info :: %{
          host: String.t(),
          port: non_neg_integer(),
          path: String.t(),
          protocol: String.t() | nil,
          transport: :tcp | :tls
        }

  @typedoc """
  Frame types that can be received.

  * `:text` - UTF-8 encoded text frame
  * `:binary` - Binary data frame
  * `:ping` - Ping control frame
  * `:pong` - Pong control frame
  * `:close` - Connection close frame
  """
  @type frame_type :: :text | :binary | :ping | :pong | :close

  @typedoc """
  Disconnect reason.

  * `{:remote, code, reason}` - Server closed the connection with the given code and reason
  * `{:local, code, reason}` - Client closed the connection with the given code and reason
  * `{:error, reason}` - Error occurred on the connection
  """
  @type disconnect_reason ::
          {:remote, integer(), String.t()}
          | {:local, integer(), String.t()}
          | {:error, term()}

  @typedoc """
  Handler state - can be any term.
  """
  @type state :: term()

  @typedoc """
  Return values for connection callbacks.

  * `{:ok, new_state}` - Continue with the updated state
  * `{:reply, frame_type, data, new_state}` - Send a frame and continue with the updated state
  * `{:close, code, reason, new_state}` - Close the connection with the given code and reason
  * `{:reconnect, new_state}` - Reconnect with the updated state
  * `{:stop, reason, new_state}` - Stop the process with the given reason
  """
  @type handler_return ::
          {:ok, state()}
          | {:reply, frame_type(), binary(), state()}
          | {:close, integer(), String.t(), state()}
          | {:reconnect, state()}
          | {:stop, term(), state()}

  @doc """
  Initialize the handler's state.

  Called when the handler is started. The return value becomes the initial state.

  ## Parameters

  * `opts` - The options passed to the client

  ## Returns

  * `{:ok, state}` - The initialized state
  """
  @callback init(opts :: term()) :: {:ok, state()}

  @doc """
  Handle a successful WebSocket connection.

  Called when a connection is successfully established.

  ## Parameters

  * `conn_info` - Connection details
  * `state` - Current handler state

  ## Returns

  * `{:ok, new_state}` - Continue with the updated state
  * `{:reply, frame_type, data, new_state}` - Send a frame and continue
  * `{:close, code, reason, new_state}` - Close the connection
  """
  @callback handle_connect(conn_info(), state()) :: handler_return()

  @doc """
  Handle WebSocket disconnection.

  Called when the connection is closed, either by the server, client, or due to an error.

  ## Parameters

  * `reason` - The reason for disconnection
  * `state` - Current handler state

  ## Returns

  * `{:ok, new_state}` - Accept disconnection without reconnecting
  * `{:reconnect, new_state}` - Attempt to reconnect
  * `{:stop, reason, new_state}` - Stop the process with the given reason
  """
  @callback handle_disconnect(disconnect_reason(), state()) ::
              {:ok, state()}
              | {:reconnect, state()}
              | {:stop, term(), state()}

  @doc """
  Handle a received WebSocket frame.

  Called when a frame is received from the server.

  ## Parameters

  * `frame_type` - The type of frame received
  * `frame_data` - The frame payload data
  * `state` - Current handler state

  ## Returns

  * `{:ok, new_state}` - Continue with the updated state
  * `{:reply, frame_type, data, new_state}` - Send a response frame
  * `{:close, code, reason, new_state}` - Close the connection
  """
  @callback handle_frame(frame_type(), binary(), state()) :: handler_return()

  @doc """
  Optional callback for handling connection timeouts.

  Called when a connection attempt times out.

  ## Parameters

  * `state` - Current handler state

  ## Returns

  * `{:ok, new_state}` - Accept timeout without reconnecting
  * `{:reconnect, new_state}` - Attempt to reconnect
  * `{:stop, reason, new_state}` - Stop the process with the given reason
  """
  @callback handle_timeout(state()) ::
              {:ok, state()}
              | {:reconnect, state()}
              | {:stop, term(), state()}

  @doc """
  Ping the connection or stream. Used for keepalive or health checks.

  ## Parameters
  * stream_ref - The stream reference for the WebSocket connection
  * state - Current handler state

  ## Returns
  * {:ok, new_state} - Ping successful
  * {:error, reason, new_state} - Ping failed
  """
  @callback ping(stream_ref :: term(), state()) :: {:ok, state()} | {:error, term(), state()}

  @doc """
  Query the status of the connection or stream.

  ## Parameters
  * stream_ref - The stream reference for the WebSocket connection
  * state - Current handler state

  ## Returns
  * {:ok, status, new_state} - Status information and updated state
  * {:error, reason, new_state} - Status query failed
  """
  @callback status(stream_ref :: term(), state()) :: {:ok, term(), state()} | {:error, term(), state()}

  @optional_callbacks [handle_timeout: 1]
end
