defmodule WebsockexNova.Behaviors.ConnectionHandler do
  @moduledoc """
  Defines the behavior for handling WebSocket connection lifecycle events.

  The ConnectionHandler behavior defines how a WebSocket client should respond to
  connection events like connecting, disconnecting, and receiving frames. Implementing
  modules can customize behaviors like reconnection logic and frame processing.

  ## Callbacks

  * `init/1` - Initialize the handler's state
  * `handle_connect/2` - Process a successful connection
  * `handle_disconnect/2` - Handle disconnection events
  * `handle_frame/3` - Process received WebSocket frames
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

  @optional_callbacks [handle_timeout: 1]
end
