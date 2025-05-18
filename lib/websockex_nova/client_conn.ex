defmodule WebsockexNova.ClientConn do
  @moduledoc """
  Canonical state for a WebSocket client connection.
  All core application/session state is explicit and top-level.
  Handler/feature-specific state is namespaced in maps (e.g., :rate_limit, :logging, :metrics).
  Adapter-specific state is kept in :adapter_state. :extras is for extensibility.

  This struct contains all the information needed to interact with a WebSocket connection,
  including the transport layer implementation, transport process, stream reference,
  adapter module, and adapter state.

  ## Fields

    * `:transport` - The transport module implementing `WebsockexNova.Transport`
    * `:transport_pid` - PID of the transport process
    * `:stream_ref` - WebSocket stream reference
    * `:adapter` - Adapter module implementing various behaviors
    * `:adapter_state` - State maintained by the adapter (stores auth status, auth tokens, credentials, subscriptions, etc.)
    * `:callback_pids` - List of PIDs registered to receive event notifications
    * `:connection_info` - Connection information and initial configuration
    * `:connection_id` - Stable identifier that persists across reconnections
    * `:rate_limit` - Rate limit configuration
    * `:logging` - Logging configuration
    * `:metrics` - Metrics configuration
    * `:reconnection` - Reconnection configuration map for error handler
    * `:connection_handler_settings` - State specific to the connection handler
    * `:auth_handler_settings` - State specific to the auth handler
    * `:subscription_handler_settings` - State specific to the subscription handler
    * `:error_handler_settings` - State specific to the error handler
    * `:message_handler_settings` - State specific to the message handler
    * `:extras` - Extensible/optional state
  """

  @typedoc "WebSocket transport module"
  @type transport :: module()

  @typedoc "WebSocket stream reference"
  @type stream_ref :: reference() | any()

  @typedoc "Adapter module implementing behaviors"
  @type adapter :: module()

  @typedoc "Client connection structure (canonical state)"
  @type t :: %__MODULE__{
          # Core connection/session state
          transport: transport(),
          transport_pid: pid(),
          stream_ref: stream_ref(),
          adapter: adapter(),
          callback_pids: MapSet.t(pid()),
          connection_info: map(),
          connection_id: reference(),
          # Handler/feature-specific state
          rate_limit: map(),
          logging: map(),
          metrics: map(),
          reconnection: map(),
          connection_handler_settings: map(),
          auth_handler_settings: map(),
          subscription_handler_settings: map(),
          error_handler_settings: map(),
          message_handler_settings: map(),
          # Adapter-specific state
          adapter_state: map(),
          # Extensible/optional
          extras: map()
        }

  defstruct [
    :transport,
    :transport_pid,
    :stream_ref,
    :adapter,
    :connection_id,
    callback_pids: MapSet.new(),
    connection_info: %{},
    rate_limit: %{},
    logging: %{},
    metrics: %{},
    reconnection: %{},
    connection_handler_settings: %{},
    auth_handler_settings: %{},
    subscription_handler_settings: %{},
    error_handler_settings: %{},
    message_handler_settings: %{},
    adapter_state: %{},
    extras: %{}
  ]
  
  @doc """
  Get the current transport_pid for a connection.
  
  This function checks the ConnectionRegistry first using the connection_id.
  If found, it returns the current transport PID. This ensures operations
  work even after reconnection when the transport_pid might have changed.
  
  If the lookup fails, it falls back to the PID stored in the struct.
  
  ## Parameters
    - conn: The ClientConn struct
    
  ## Returns
    - pid: The current transport process PID
  """
  @spec get_current_transport_pid(t()) :: pid()
  def get_current_transport_pid(%__MODULE__{} = conn) do
    case conn.connection_id && WebsockexNova.ConnectionRegistry.get_transport_pid(conn.connection_id) do
      {:ok, pid} when is_pid(pid) -> 
        if Process.alive?(pid) do
          pid
        else
          # Process not alive, fall back to stored PID
          conn.transport_pid
        end
      _ -> 
        # Fall back to the stored PID
        conn.transport_pid
    end
  end
  
  @doc """
  Get the current stream_ref for a connection.
  
  This is used alongside get_current_transport_pid to ensure operations
  use the current stream_ref, which may have changed after reconnection.
  
  ## Parameters
    - conn: The ClientConn struct
    
  ## Returns
    - stream_ref: The current stream reference
  """
  @spec get_current_stream_ref(t()) :: stream_ref()
  def get_current_stream_ref(%__MODULE__{} = conn) do
    conn.stream_ref
  end
end
