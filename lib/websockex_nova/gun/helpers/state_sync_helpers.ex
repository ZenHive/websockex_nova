defmodule WebsockexNova.Gun.Helpers.StateSyncHelpers do
  @moduledoc """
  Helpers for synchronizing state between ClientConn and ConnectionState.

  This module provides functions to ensure proper state synchronization between
  the canonical client state (`WebsockexNova.ClientConn`) and the transport-local
  state (`WebsockexNova.Gun.ConnectionState`).

  It implements the state layering principles:
  - ClientConn is the canonical source of truth for session state
  - ConnectionState only contains transport-local/process-local data
  - During transitions (reconnection, ownership transfer), state is properly synchronized

  ## Usage

      # During ownership transfer:
      updated_client_conn = StateSyncHelpers.sync_from_connection_state(client_conn, connection_state)

      # When extracting transport-only state:
      transport_state = StateSyncHelpers.extract_transport_state(client_conn)

      # When updating client conn with transport state changes:
      updated_client_conn = StateSyncHelpers.update_client_conn_from_transport(client_conn, connection_state)
  """

  alias WebsockexNova.ClientConn
  alias WebsockexNova.Gun.ConnectionState

  @doc """
  Extracts transport-level information from a ClientConn struct.

  Use this when you need to populate a ConnectionState with the configuration
  from a ClientConn, but don't want to copy user/session state.

  ## Parameters

  * `client_conn` - The ClientConn struct to extract transport info from

  ## Returns

  Map with transport-only fields that can be used to build a ConnectionState
  """
  @spec extract_transport_state(ClientConn.t()) :: map()
  def extract_transport_state(%ClientConn{} = client_conn) do
    # Extract only the connection info we need for the transport layer
    connection_info = client_conn.connection_info || %{}

    %{
      host: Map.get(connection_info, :host),
      port: Map.get(connection_info, :port),
      path: Map.get(connection_info, :path),
      transport: Map.get(connection_info, :transport, :tcp),
      ws_opts: Map.get(connection_info, :ws_opts, %{}),
      callback_pid: client_conn.callback_pids |> MapSet.to_list() |> List.first(),
      handlers: %{
        connection_handler: Map.get(connection_info, :connection_handler),
        message_handler: Map.get(connection_info, :message_handler),
        error_handler: Map.get(connection_info, :error_handler),
        logging_handler: Map.get(connection_info, :logging_handler),
        subscription_handler: Map.get(connection_info, :subscription_handler),
        auth_handler: Map.get(connection_info, :auth_handler),
        rate_limit_handler: Map.get(connection_info, :rate_limit_handler),
        metrics_collector: Map.get(connection_info, :metrics_collector)
      }
    }
  end

  @doc """
  Updates a ClientConn struct with transport state from a ConnectionState.

  This should be used when the transport layer has information that needs to be
  reflected in the canonical client state (e.g., connection status, error).

  ## Parameters

  * `client_conn` - The ClientConn struct to update
  * `conn_state` - The ConnectionState with updated transport information

  ## Returns

  Updated ClientConn struct
  """
  @spec update_client_conn_from_transport(ClientConn.t(), ConnectionState.t()) :: ClientConn.t()
  def update_client_conn_from_transport(%ClientConn{} = client_conn, %ConnectionState{} = conn_state) do
    # Create updated connection_info with new status
    connection_info = Map.put(client_conn.connection_info || %{}, :status, conn_state.status)

    # Only update last_error if there is a new error in the connection state
    client_conn =
      if conn_state.last_error do
        %{client_conn | last_error: conn_state.last_error}
      else
        client_conn
      end

    # Update the client conn with transport-specific info
    %{
      client_conn
      | connection_info: connection_info,
        transport_pid: conn_state.gun_pid,
        stream_ref: extract_main_stream_ref(conn_state)
    }
  end

  @doc """
  Synchronizes connection state information from ClientConn to ConnectionState.

  This ensures the ConnectionState has the latest configuration from ClientConn
  without copying session state. Used during reconnection and initialization.

  ## Parameters

  * `conn_state` - The ConnectionState to update
  * `client_conn` - The ClientConn with canonical configuration

  ## Returns

  Updated ConnectionState
  """
  @spec sync_connection_state_from_client(ConnectionState.t(), ClientConn.t()) :: ConnectionState.t()
  def sync_connection_state_from_client(%ConnectionState{} = conn_state, %ClientConn{} = client_conn) do
    transport_state = extract_transport_state(client_conn)

    # Update the connection state with the transport configuration
    # but preserve Gun-specific state (gun_pid, gun_monitor_ref, active_streams)
    %{
      conn_state
      | host: transport_state.host || conn_state.host,
        port: transport_state.port || conn_state.port,
        path: transport_state.path || conn_state.path,
        transport: transport_state.transport || conn_state.transport,
        ws_opts: transport_state.ws_opts || conn_state.ws_opts,
        handlers: Map.merge(conn_state.handlers, transport_state.handlers)
    }
  end

  @doc """
  Synchronizes client connection information from ConnectionState to ClientConn.

  This updates the ClientConn with the latest transport state from ConnectionState.
  Used during ownership transfer and status changes.

  ## Parameters

  * `client_conn` - The ClientConn to update
  * `conn_state` - The ConnectionState with updated transport information

  ## Returns

  Updated ClientConn struct
  """
  @spec sync_client_conn_from_connection(ClientConn.t(), ConnectionState.t()) :: ClientConn.t()
  def sync_client_conn_from_connection(%ClientConn{} = client_conn, %ConnectionState{} = conn_state) do
    # Create new connection_info with updated transport details
    connection_info =
      Map.merge(client_conn.connection_info || %{}, %{
        host: conn_state.host,
        port: conn_state.port,
        path: conn_state.path,
        status: conn_state.status
      })

    # Update the client conn with transport-specific info
    %{
      client_conn
      | connection_info: connection_info,
        transport_pid: conn_state.gun_pid,
        stream_ref: extract_main_stream_ref(conn_state),
        last_error: conn_state.last_error || client_conn.last_error
    }
  end

  @doc """
  Synchronizes handler modules between ClientConn connection_info and ConnectionState handlers.

  ## Parameters

  * `client_conn` - The ClientConn to update
  * `conn_state` - The ConnectionState with handler module information

  ## Returns

  Updated ClientConn struct
  """
  @spec sync_handler_modules(ClientConn.t(), ConnectionState.t()) :: ClientConn.t()
  def sync_handler_modules(%ClientConn{} = client_conn, %ConnectionState{} = conn_state) do
    # Get handler modules from connection state
    handler_modules = conn_state.handlers || %{}

    # Update connection_info in client_conn with handler modules
    connection_info = client_conn.connection_info || %{}

    # Add each handler module to connection_info
    connection_info =
      Enum.reduce(handler_modules, connection_info, fn {key, module}, acc ->
        if module, do: Map.put(acc, key, module), else: acc
      end)

    # Return updated client_conn
    %{client_conn | connection_info: connection_info}
  end

  @doc """
  Registers a callback PID in both the ConnectionState and ClientConn.

  ## Parameters

  * `client_conn` - The ClientConn to update
  * `conn_state` - The ConnectionState to update
  * `pid` - The PID to register

  ## Returns

  {updated_client_conn, updated_conn_state}
  """
  @spec register_callback(ClientConn.t(), ConnectionState.t(), pid()) :: {ClientConn.t(), ConnectionState.t()}
  def register_callback(%ClientConn{} = client_conn, %ConnectionState{} = conn_state, pid) when is_pid(pid) do
    updated_client_conn = %{client_conn | callback_pids: MapSet.put(client_conn.callback_pids || MapSet.new(), pid)}
    updated_conn_state = %{conn_state | callback_pid: pid}

    {updated_client_conn, updated_conn_state}
  end

  @doc """
  Unregisters a callback PID from both the ConnectionState and ClientConn.

  ## Parameters

  * `client_conn` - The ClientConn to update
  * `conn_state` - The ConnectionState to update
  * `pid` - The PID to unregister

  ## Returns

  {updated_client_conn, updated_conn_state} - ConnectionState will have nil callback_pid if the removed PID
  was the current one
  """
  @spec unregister_callback(ClientConn.t(), ConnectionState.t(), pid()) :: {ClientConn.t(), ConnectionState.t()}
  def unregister_callback(%ClientConn{} = client_conn, %ConnectionState{} = conn_state, pid) when is_pid(pid) do
    updated_client_conn = %{client_conn | callback_pids: MapSet.delete(client_conn.callback_pids || MapSet.new(), pid)}

    # If the PID being removed is the current callback_pid in conn_state, set it to nil
    updated_conn_state =
      if conn_state.callback_pid == pid do
        %{conn_state | callback_pid: nil}
      else
        conn_state
      end

    {updated_client_conn, updated_conn_state}
  end

  @doc """
  Creates a ClientConn struct from a ConnectionState and existing ClientConn.

  This is used when you need to call a behavior callback that expects a ClientConn
  but you only have ConnectionState. It preserves session data from the existing
  ClientConn while updating transport-specific fields from ConnectionState.

  ## Parameters

  * `client_conn` - The existing ClientConn struct (can be nil if creating fresh)
  * `conn_state` - The ConnectionState with transport information

  ## Returns

  A new or updated ClientConn struct
  """
  @spec create_client_conn(ClientConn.t() | nil, ConnectionState.t()) :: ClientConn.t()
  def create_client_conn(client_conn \\ nil, %ConnectionState{} = conn_state) do
    base_conn = client_conn || %ClientConn{}

    connection_info =
      Map.merge(base_conn.connection_info || %{}, %{
        host: conn_state.host,
        port: conn_state.port,
        path: conn_state.path,
        status: conn_state.status,
        # Copy handler modules to connection_info
        connection_handler: Map.get(conn_state.handlers || %{}, :connection_handler),
        message_handler: Map.get(conn_state.handlers || %{}, :message_handler),
        error_handler: Map.get(conn_state.handlers || %{}, :error_handler),
        logging_handler: Map.get(conn_state.handlers || %{}, :logging_handler),
        subscription_handler: Map.get(conn_state.handlers || %{}, :subscription_handler),
        auth_handler: Map.get(conn_state.handlers || %{}, :auth_handler),
        rate_limit_handler: Map.get(conn_state.handlers || %{}, :rate_limit_handler),
        metrics_collector: Map.get(conn_state.handlers || %{}, :metrics_collector)
      })

    # Add callback_pid to callback_pids if not already there
    callback_pids =
      if base_conn.callback_pids do
        if conn_state.callback_pid do
          MapSet.put(base_conn.callback_pids, conn_state.callback_pid)
        else
          base_conn.callback_pids
        end
      else
        if conn_state.callback_pid do
          MapSet.new([conn_state.callback_pid])
        else
          MapSet.new()
        end
      end

    # Update the client conn with the extracted info
    %{
      base_conn
      | connection_info: connection_info,
        transport_pid: conn_state.gun_pid,
        callback_pids: callback_pids,
        stream_ref: extract_main_stream_ref(conn_state),
        last_error: conn_state.last_error || base_conn.last_error
    }
  end

  # Private helpers

  # Extract the main WebSocket stream reference from ConnectionState
  defp extract_main_stream_ref(%ConnectionState{active_streams: active_streams}) do
    Enum.find_value(active_streams, nil, fn {stream_ref, stream_data} ->
      case stream_data do
        %{status: :websocket} -> stream_ref
        _ -> nil
      end
    end)
  end
end
