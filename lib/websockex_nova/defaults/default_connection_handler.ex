defmodule WebsockexNova.Defaults.DefaultConnectionHandler do
  @moduledoc """
  Default implementation of the ConnectionHandler behavior.

  This module provides sensible default implementations for all ConnectionHandler
  callbacks, including:

  * Basic connection tracking
  * Automatic ping/pong handling
  * Reconnection attempt management
  * Connection state maintenance

  ## Usage

  You can use this module directly or as a starting point for your own implementation:

      defmodule MyApp.CustomHandler do
        use WebsockexNova.Defaults.DefaultConnectionHandler

        # Override specific callbacks as needed
        def handle_frame(:text, frame_data, conn) do
          # Custom text frame handling
          {:ok, conn}
        end
      end

  ## Configuration

  The default handler supports the following configuration in the adapter_state:

  * `:max_reconnect_attempts` - Maximum number of reconnection attempts (default: 5)
  * `:reconnect_attempts` - Current number of reconnection attempts (default: 0)
  * `:ping_interval` - Interval in milliseconds between ping frames (default: 30000)
  """

  @behaviour WebsockexNova.Behaviours.ConnectionHandler

  alias WebsockexNova.ClientConn

  @default_max_reconnect_attempts 5

  @impl true
  @doc """
  Initializes the handler state as a ClientConn struct.
  Any unknown fields are placed in adapter_state.
  """
  def init(opts) do
    opts_map =
      case opts do
        opts when is_list(opts) -> Map.new(opts)
        opts when is_map(opts) -> opts
        _ -> %{}
      end

    # Split known fields and custom fields
    known_keys = MapSet.new(Map.keys(%ClientConn{}))
    {known, custom} = Enum.split_with(opts_map, fn {k, _v} -> MapSet.member?(known_keys, k) end)
    known_map = Map.new(known)
    custom_map = Map.new(custom)

    conn = struct(ClientConn, known_map)

    # Store custom fields in adapter_state instead of connection_handler_settings
    adapter_state = Map.merge(conn.adapter_state || %{}, custom_map)

    # Initialize with reconnect_attempts = 0 if not present
    adapter_state = Map.put_new(adapter_state, :reconnect_attempts, 0)

    conn = %{conn | adapter_state: adapter_state}
    {:ok, conn}
  end

  @impl true
  def handle_connect(conn_info, %ClientConn{} = conn) do
    # Get current adapter_state or initialize empty map
    adapter_state = conn.adapter_state || %{}

    # Store in adapter_state instead of top-level fields
    updated_adapter_state =
      adapter_state
      |> Map.put(:reconnect_attempts, 0)
      |> Map.put(:connected_at, System.system_time(:millisecond))

    updated_conn = %{
      conn
      | connection_info: conn_info,
        adapter_state: updated_adapter_state
    }

    {:ok, updated_conn}
  end

  @impl true
  def handle_disconnect({:local, _code, _message} = reason, %ClientConn{} = conn) do
    # Get current adapter_state or initialize empty map
    adapter_state = conn.adapter_state || %{}

    # Store last_disconnect_reason in adapter_state
    updated_adapter_state = Map.put(adapter_state, :last_disconnect_reason, reason)
    updated_conn = %{conn | adapter_state: updated_adapter_state}

    {:ok, updated_conn}
  end

  def handle_disconnect(reason, %ClientConn{} = conn) do
    # Get current adapter_state or initialize empty map
    adapter_state = conn.adapter_state || %{}

    # Get current attempts and max attempts from adapter_state
    current_attempts = Map.get(adapter_state, :reconnect_attempts, 0)
    max_attempts = Map.get(adapter_state, :max_reconnect_attempts, @default_max_reconnect_attempts)

    # Store last_disconnect_reason in adapter_state
    updated_adapter_state = Map.put(adapter_state, :last_disconnect_reason, reason)
    updated_conn = %{conn | adapter_state: updated_adapter_state}

    if current_attempts < max_attempts do
      # Increment reconnect_attempts in adapter_state
      updated_adapter_state = Map.put(updated_adapter_state, :reconnect_attempts, current_attempts + 1)
      updated_conn = %{updated_conn | adapter_state: updated_adapter_state}
      {:reconnect, updated_conn}
    else
      {:ok, updated_conn}
    end
  end

  @impl true
  def handle_frame(:ping, frame_data, %ClientConn{} = conn) do
    {:reply, :pong, frame_data, conn}
  end

  def handle_frame(:pong, _frame_data, %ClientConn{} = conn) do
    # Get current adapter_state or initialize empty map
    adapter_state = conn.adapter_state || %{}

    # Store last_pong_received in adapter_state, remove last_ping_sent
    updated_adapter_state =
      adapter_state
      |> Map.put(:last_pong_received, System.monotonic_time(:millisecond))
      |> Map.delete(:last_ping_sent)

    updated_conn = %{conn | adapter_state: updated_adapter_state}

    {:ok, updated_conn}
  end

  def handle_frame(_frame_type, _frame_data, %ClientConn{} = conn) do
    {:ok, conn}
  end

  @impl true
  def handle_timeout(%ClientConn{} = conn) do
    # Get current adapter_state or initialize empty map
    adapter_state = conn.adapter_state || %{}

    # Get current attempts and max attempts from adapter_state
    current_attempts = Map.get(adapter_state, :reconnect_attempts, 0)
    max_attempts = Map.get(adapter_state, :max_reconnect_attempts, @default_max_reconnect_attempts)

    if current_attempts < max_attempts do
      # Increment reconnect_attempts in adapter_state
      updated_adapter_state = Map.put(adapter_state, :reconnect_attempts, current_attempts + 1)
      updated_conn = %{conn | adapter_state: updated_adapter_state}
      {:reconnect, updated_conn}
    else
      {:stop, :max_reconnect_attempts_reached, conn}
    end
  end

  @impl true
  def ping(_stream_ref, %ClientConn{} = conn) do
    {:ok, conn}
  end

  @impl true
  def status(_stream_ref, %ClientConn{} = conn) do
    {:ok, :ok, conn}
  end

  @impl true
  def connection_info(_opts) do
    {:error, :not_implemented}
  end
end
