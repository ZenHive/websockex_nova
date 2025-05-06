defmodule WebsockexNova.Transport do
  @moduledoc """
  Behaviour for pluggable WebSocket transport layers in WebsockexNova.

  This abstraction allows the connection process to interact with any transport (e.g., Gun, test mocks)
  via a consistent, testable interface.

  ## Callbacks

    * `send_frame/3` — Send a WebSocket frame on a given stream
    * `upgrade_to_websocket/3` — Upgrade an HTTP connection to WebSocket
    * `close/1` — Close the transport connection
    * `process_transport_message/2` — (Optional) Process a transport-specific message (e.g., Gun event)
    * `get_state/1` — (Optional) Retrieve the current transport state (for testability)
    * `open/4` — Open a new transport connection
    * `schedule_reconnection/2` — (Optional) Schedule a reconnection attempt after a disconnect
    * `start_connection/1` — (Optional) Start a new connection or reconnection attempt for the transport
  """

  @typedoc "Opaque transport state (implementation-defined)"
  @type state :: any()

  @typedoc "WebSocket frame type"
  @type frame ::
          {:text, binary}
          | {:binary, binary}
          | :ping
          | :pong
          | :close
          | {:close, non_neg_integer(), binary}

  @typedoc "Stream reference (opaque)"
  @type stream_ref :: reference() | any()

  @doc """
  Send a WebSocket frame on the given stream.
  Returns :ok or {:error, reason}.
  """
  @callback send_frame(state, stream_ref, frame | [frame]) :: :ok | {:error, term()}

  @doc """
  Upgrade the connection to WebSocket on the given path and headers.
  Returns {:ok, stream_ref} or {:error, reason}.
  """
  @callback upgrade_to_websocket(state, path :: binary, headers :: Keyword.t()) ::
              {:ok, stream_ref} | {:error, term()}

  @doc """
  Close the transport connection.
  Returns :ok.
  """
  @callback close(state) :: :ok

  @doc """
  (Optional) Process a transport-specific message (e.g., Gun event).
  Returns updated state or other result as needed.
  """
  @callback process_transport_message(state, message :: term()) :: any()

  @doc """
  (Optional) Retrieve the current transport state (for testability).
  """
  @callback get_state(state) :: any()

  @doc """
  Open a new transport connection.
  Returns {:ok, state} or {:error, reason}.

  ## Parameters
    * host - Hostname or IP address to connect to
    * port - Port number
    * path - WebSocket endpoint path
    * options - Transport-specific options (map or keyword)
  """
  @callback open(host :: binary, port :: pos_integer, path :: binary, options :: map | keyword) ::
              {:ok, state} | {:error, term()}

  @doc """
  (Optional) Schedule a reconnection attempt after a disconnect.
  Returns the updated transport state.
  """
  @callback schedule_reconnection(state, (non_neg_integer(), non_neg_integer() -> any())) :: state

  @doc """
  (Optional) Start a new connection or reconnection attempt for the transport.
  Returns the updated transport state.
  """
  @callback start_connection(state) :: state
end
