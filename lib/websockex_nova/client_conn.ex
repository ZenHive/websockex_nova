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

  @behaviour Access

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

  @doc """
  Implements the Access behaviour to enable bracket access (`conn[:field]`).

  Allows retrieving fields from the ClientConn struct using Access syntax:

  ## Examples
      
      conn[:adapter]
      Access.get(conn, :connection_info)
      conn["adapter"]
      Access.get(conn, "connection_info")
      
  ## Parameters
    - conn: The ClientConn struct
    - key: The field name to access (atom or string)
    
  ## Returns
    - {:ok, value} if the key exists
    - :error if the key doesn't exist
  """
  @impl Access
  @spec fetch(t(), atom() | String.t()) :: {:ok, any()} | :error
  def fetch(%__MODULE__{} = conn, key) when is_atom(key) do
    Map.fetch(Map.from_struct(conn), key)
  end

  # Try to convert string key to atom if it exists
  def fetch(%__MODULE__{} = conn, key) when is_binary(key) do
    atom_key = String.to_existing_atom(key)
    Map.fetch(Map.from_struct(conn), atom_key)
  rescue
    ArgumentError -> :error
  end

  @doc """
  Implements the Access behaviour for updating ClientConn fields.

  This enables functions like `Access.get_and_update/3` to work with ClientConn.

  ## Examples

      {old_value, updated_conn} = Access.get_and_update(conn, :adapter_state, fn current ->
        {current, Map.put(current, :new_key, :new_value)}
      end)
      
      {old_value, updated_conn} = Access.get_and_update(conn, "adapter_state", fn current ->
        {current, Map.put(current, :new_key, :new_value)}
      end)
      
  ## Parameters
    - conn: The ClientConn struct
    - key: The field name to update (atom or string)
    - function: Function that transforms the current value
    
  ## Returns
    - {get_value, updated_conn}
  """
  @impl Access
  @spec get_and_update(t(), atom() | String.t(), (any() -> {any(), any()} | :pop)) :: {any(), t()}
  def get_and_update(%__MODULE__{} = conn, key, fun) when is_atom(key) and is_function(fun, 1) do
    current = Map.get(conn, key)

    case fun.(current) do
      {get_value, update_value} ->
        {get_value, Map.put(conn, key, update_value)}

      :pop ->
        {current, conn}
    end
  end

  # Try to convert string key to atom if it exists
  def get_and_update(%__MODULE__{} = conn, key, fun) when is_binary(key) and is_function(fun, 1) do
    atom_key = String.to_existing_atom(key)
    get_and_update(conn, atom_key, fun)
  rescue
    ArgumentError -> {nil, conn}
  end

  @doc """
  Implements the Access behaviour to pop values from ClientConn fields.

  Since ClientConn is a struct with fixed fields, actual removal is not supported.
  For map-type fields, this can clear the value by setting it to an empty map.

  ## Examples

      {value, updated_conn} = Access.pop(conn, :extras)
      {value, updated_conn} = Access.pop(conn, "extras")
      
  ## Parameters
    - conn: The ClientConn struct
    - key: The field name to pop (atom or string)
    
  ## Returns
    - {current_value, updated_conn}
  """
  @impl Access
  @spec pop(t(), atom() | String.t()) :: {any(), t()}
  def pop(%__MODULE__{} = conn, key) when is_atom(key) do
    value = Map.get(conn, key)

    # Determine default value based on field type
    default =
      case key do
        :callback_pids ->
          MapSet.new()

        k
        when k in [
               :connection_info,
               :rate_limit,
               :logging,
               :metrics,
               :reconnection,
               :connection_handler_settings,
               :auth_handler_settings,
               :subscription_handler_settings,
               :error_handler_settings,
               :message_handler_settings,
               :adapter_state,
               :extras
             ] ->
          %{}

        _ ->
          nil
      end

    {value, Map.put(conn, key, default)}
  end

  # Try to convert string key to atom if it exists
  def pop(%__MODULE__{} = conn, key) when is_binary(key) do
    atom_key = String.to_existing_atom(key)
    pop(conn, atom_key)
  rescue
    ArgumentError -> {nil, conn}
  end
end
