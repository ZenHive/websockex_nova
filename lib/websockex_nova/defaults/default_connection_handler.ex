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
        def handle_frame(:text, frame_data, state) do
          # Custom text frame handling
          {:ok, state}
        end
      end

  ## Configuration

  The default handler supports the following configuration in the state:

  * `:max_reconnect_attempts` - Maximum number of reconnection attempts (default: 5)
  * `:reconnect_attempts` - Current number of reconnection attempts (default: 0)
  * `:ping_interval` - Interval in milliseconds between ping frames (default: 30000)
  """

  @behaviour WebsockexNova.Behaviors.ConnectionHandler

  @default_max_reconnect_attempts 5

  @impl true
  @doc """
  Initializes the handler state.
  """
  def init(opts) do
    state =
      case opts do
        opts when is_list(opts) -> Map.new(opts)
        opts when is_map(opts) -> opts
        _ -> %{}
      end

    {:ok, state}
  end

  @impl true
  def handle_connect(conn_info, state) when is_map(conn_info) and is_map(state) do
    updated_state =
      state
      |> Map.put(:connection, conn_info)
      |> Map.put(:connected_at, System.system_time(:millisecond))
      |> Map.put(:reconnect_attempts, 0)

    {:ok, updated_state}
  end

  @impl true
  def handle_disconnect({:local, _code, _message} = reason, state) when is_map(state) do
    # No reconnection for local disconnects (client initiated)
    {:ok, Map.put(state, :last_disconnect_reason, reason)}
  end

  def handle_disconnect(reason, state) when is_map(state) do
    # For remote or error disconnects, try reconnection
    current_attempts = Map.get(state, :reconnect_attempts, 0)
    max_attempts = Map.get(state, :max_reconnect_attempts, @default_max_reconnect_attempts)

    updated_state = Map.put(state, :last_disconnect_reason, reason)

    if current_attempts < max_attempts do
      updated_state = Map.put(updated_state, :reconnect_attempts, current_attempts + 1)
      {:reconnect, updated_state}
    else
      {:ok, updated_state}
    end
  end

  @impl true
  def handle_frame(:ping, frame_data, state) when is_map(state) do
    # Automatically respond to pings with pongs
    {:reply, :pong, frame_data, state}
  end

  def handle_frame(:pong, _frame_data, state) when is_map(state) do
    # Track pong responses
    updated_state = Map.put(state, :last_pong_received, System.monotonic_time(:millisecond))

    # Delete last_ping_sent if it exists, otherwise leave state unchanged
    updated_state =
      if Map.has_key?(updated_state, :last_ping_sent) do
        Map.delete(updated_state, :last_ping_sent)
      else
        updated_state
      end

    {:ok, updated_state}
  end

  def handle_frame(_frame_type, _frame_data, state) when is_map(state) do
    # Default implementation for other frame types
    {:ok, state}
  end

  @impl true
  def handle_timeout(state) when is_map(state) do
    current_attempts = Map.get(state, :reconnect_attempts, 0)
    max_attempts = Map.get(state, :max_reconnect_attempts, @default_max_reconnect_attempts)

    if current_attempts < max_attempts do
      updated_state = Map.put(state, :reconnect_attempts, current_attempts + 1)
      {:reconnect, updated_state}
    else
      {:stop, :max_reconnect_attempts_reached, state}
    end
  end

  @impl true
  def ping(_stream_ref, state) when is_map(state) do
    {:ok, state}
  end

  @impl true
  def status(_stream_ref, state) when is_map(state) do
    {:ok, :ok, state}
  end

  @impl true
  def connection_info(_opts) do
    {:error, :not_implemented}
  end
end
