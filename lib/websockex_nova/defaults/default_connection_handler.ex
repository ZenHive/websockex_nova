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

  The default handler supports the following configuration in the state:

  * `:max_reconnect_attempts` - Maximum number of reconnection attempts (default: 5)
  * `:reconnect_attempts` - Current number of reconnection attempts (default: 0)
  * `:ping_interval` - Interval in milliseconds between ping frames (default: 30000)
  """

  @behaviour WebsockexNova.Behaviors.ConnectionHandler

  alias WebsockexNova.ClientConn

  @default_max_reconnect_attempts 5

  @impl true
  @doc """
  Initializes the handler state as a ClientConn struct.
  Any unknown fields are placed in connection_handler_settings.
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
    conn = %{conn | connection_handler_settings: Map.merge(conn.connection_handler_settings || %{}, custom_map)}
    {:ok, conn}
  end

  @impl true
  def handle_connect(conn_info, %ClientConn{} = conn) do
    updated_conn = %{
      conn
      | connection_info: conn_info,
        reconnect_attempts: 0,
        extras: Map.put(conn.extras || %{}, :connected_at, System.system_time(:millisecond)),
        connection_handler_settings: Map.merge(conn.connection_handler_settings || %{}, %{})
    }

    {:ok, updated_conn}
  end

  @impl true
  def handle_disconnect({:local, _code, _message} = reason, %ClientConn{} = conn) do
    updated_conn = %{
      conn
      | extras: Map.put(conn.extras || %{}, :last_disconnect_reason, reason)
    }

    {:ok, updated_conn}
  end

  def handle_disconnect(reason, %ClientConn{} = conn) do
    current_attempts = conn.reconnect_attempts || 0
    max_attempts = Map.get(conn.extras || %{}, :max_reconnect_attempts, @default_max_reconnect_attempts)

    updated_conn = %{
      conn
      | extras: Map.put(conn.extras || %{}, :last_disconnect_reason, reason)
    }

    if current_attempts < max_attempts do
      updated_conn = %{updated_conn | reconnect_attempts: current_attempts + 1}
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
    updated_conn = %{
      conn
      | extras: Map.put(conn.extras || %{}, :last_pong_received, System.monotonic_time(:millisecond))
    }

    # Remove last_ping_sent if present in extras
    updated_conn = %{
      updated_conn
      | extras: Map.delete(updated_conn.extras, :last_ping_sent)
    }

    {:ok, updated_conn}
  end

  def handle_frame(_frame_type, _frame_data, %ClientConn{} = conn) do
    {:ok, conn}
  end

  @impl true
  def handle_timeout(%ClientConn{} = conn) do
    current_attempts = conn.reconnect_attempts || 0
    max_attempts = Map.get(conn.extras || %{}, :max_reconnect_attempts, @default_max_reconnect_attempts)

    if current_attempts < max_attempts do
      updated_conn = %{conn | reconnect_attempts: current_attempts + 1}
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
