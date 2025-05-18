defmodule WebsockexNova.ConnectionRegistry do
  @moduledoc """
  Registry for WebSocket connection information.
  
  This registry maps connection IDs to transport PIDs, allowing transparent reconnection 
  without requiring client code to update connection references.
  
  The registry is used internally by the library to maintain a stable reference to
  connection processes even when the underlying transport process changes during reconnection.
  """
  
  require Logger
  
  @registry_name __MODULE__
  
  @doc """
  Returns a specification to start this module under a supervisor.
  See `Supervisor.child_spec/2` for details.
  """
  def child_spec(_args) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, []},
      type: :worker,
      restart: :permanent,
      shutdown: 500
    }
  end
  
  @doc """
  Start the connection registry.
  Should be called by the application supervisor.
  """
  def start_link(_args \\ []) do
    Registry.start_link(keys: :unique, name: @registry_name)
  end
  
  @doc """
  Register a connection_id with a transport_pid.
  If the connection_id is already registered, it updates the association.
  
  Returns `:ok`.
  """
  def register(connection_id, transport_pid) when is_reference(connection_id) and is_pid(transport_pid) do
    # Unregister any existing registration first
    unregister(connection_id)
    
    # Register the new association
    case Registry.register(@registry_name, connection_id, transport_pid) do
      {:ok, _pid} -> 
        Logger.debug("[ConnectionRegistry] Registered connection_id #{inspect(connection_id)} with transport_pid #{inspect(transport_pid)}")
        :ok
      {:error, reason} ->
        Logger.error("[ConnectionRegistry] Failed to register connection_id #{inspect(connection_id)}: #{inspect(reason)}")
        {:error, reason}
    end
  end
  
  @doc """
  Unregister a connection_id from the registry.
  
  Returns `:ok` regardless of whether the connection_id was registered.
  """
  def unregister(connection_id) when is_reference(connection_id) do
    Registry.unregister(@registry_name, connection_id)
    Logger.debug("[ConnectionRegistry] Unregistered connection_id #{inspect(connection_id)}")
    :ok
  end
  
  @doc """
  Get the current transport_pid for a connection_id.
  
  Returns `{:ok, pid}` if found, or `{:error, :not_found}` if not found.
  """
  def get_transport_pid(connection_id) when is_reference(connection_id) do
    case Registry.lookup(@registry_name, connection_id) do
      [{_pid, transport_pid}] -> 
        {:ok, transport_pid}
      [] -> 
        {:error, :not_found}
    end
  end
  
  @doc """
  Updates the transport_pid for an existing connection_id.
  This is typically used during reconnection when the transport process changes.
  
  Returns `:ok` if the update was successful, or `{:error, :not_found}` if the connection_id was not found.
  """
  def update_transport_pid(connection_id, new_transport_pid) when is_reference(connection_id) and is_pid(new_transport_pid) do
    case Registry.update_value(@registry_name, connection_id, fn _old_pid -> new_transport_pid end) do
      :error -> 
        Logger.warning("[ConnectionRegistry] Failed to update transport_pid for connection_id #{inspect(connection_id)}: Not found")
        {:error, :not_found}
      {_old_pid, _new_pid} -> 
        Logger.debug("[ConnectionRegistry] Updated transport_pid for connection_id #{inspect(connection_id)} to #{inspect(new_transport_pid)}")
        :ok
    end
  end
end