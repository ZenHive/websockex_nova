defmodule WebsockexNova.Behaviors.ConnectionHandler do
  @moduledoc """
  Behaviour for connection handlers.
  All state is a map. All arguments and return values are explicit and documented.

  ## Reconnection Policy
  - The connection handler should NOT return `{:reconnect, state}` from any callback.
  - All reconnection policy is handled exclusively by the error handler.
  - On disconnect, simply return `{:ok, state}` or `{:stop, reason, state}` as appropriate.
  """

  @typedoc "Handler state"
  @type state :: map()

  @typedoc "Connection info map"
  @type conn_info :: map()

  @typedoc "Disconnect reason"
  @type disconnect_reason :: term()

  @typedoc "Frame type"
  @type frame_type :: :text | :binary | :ping | :pong | :close

  @doc """
  Initialize the handler's state.
  """
  @callback init(opts :: term()) :: {:ok, state} | {:error, term()}

  @doc """
  Handle connection establishment.
  Returns:
    - `{:ok, state}`
    - `{:reply, frame_type, data, state}`
    - `{:close, code, reason, state}`
    - `{:stop, reason, state}`
  """
  @callback handle_connect(conn_info, state) ::
              {:ok, state}
              | {:reply, frame_type, binary(), state}
              | {:close, integer(), String.t(), state}
              | {:stop, term(), state}

  @doc """
  Handle disconnect event.
  Returns:
    - `{:ok, state}`
    - `{:stop, reason, state}`
  """
  @callback handle_disconnect(disconnect_reason, state) ::
              {:ok, state}
              | {:stop, term(), state}

  @doc """
  Handle a received WebSocket frame.
  Returns:
    - `{:ok, state}`
    - `{:reply, frame_type, binary(), state}`
    - `{:close, code, reason, state}`
    | {:stop, reason, state}
  """
  @callback handle_frame(frame_type, binary(), state) ::
              {:ok, state}
              | {:reply, frame_type, binary(), state}
              | {:close, integer(), String.t(), state}
              | {:stop, term(), state}

  @doc """
  Optional: handle connection timeout.
  Returns:
    - `{:ok, state}`
    - `{:stop, reason, state}`
  """
  @callback handle_timeout(state) ::
              {:ok, state}
              | {:stop, term(), state}

  @doc """
  Ping the connection or stream.
  Returns:
    - `{:ok, state}`
    - `{:error, reason, state}`
  """
  @callback ping(stream_ref :: term(), state) ::
              {:ok, state}
              | {:error, term(), state}

  @doc """
  Query the status of the connection or stream.
  Returns:
    - `{:ok, status, state}`
    - `{:error, reason, state}`
  """
  @callback status(stream_ref :: term(), state) ::
              {:ok, term(), state}
              | {:error, term(), state}

  @doc """
  Returns connection information for establishing a WebSocket connection.
  Returns:
    - `{:ok, conn_info}`
    - `{:error, reason}`
  """
  @callback connection_info(opts :: map() | keyword()) :: {:ok, conn_info} | {:error, term()}
end
