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
  def init(opts) when is_list(opts) do
    {:ok, Map.new(opts)}
  end

  def init(state) when is_map(state) do
    {:ok, state}
  end

  @impl true
  def handle_connect(conn_info, state) do
    state =
      state
      |> Map.put(:connection, conn_info)
      |> Map.put(:connected_at, System.system_time(:millisecond))
      |> Map.put(:reconnect_attempts, 0)

    {:ok, state}
  end

  @impl true
  def handle_disconnect(reason = {:local, _code, _message}, state) do
    # No reconnection for local disconnects (client initiated)
    {:ok, Map.put(state, :last_disconnect_reason, reason)}
  end

  def handle_disconnect(reason, state) do
    # For remote or error disconnects, try reconnection
    current_attempts = Map.get(state, :reconnect_attempts, 0)
    max_attempts = Map.get(state, :max_reconnect_attempts, @default_max_reconnect_attempts)

    state = Map.put(state, :last_disconnect_reason, reason)

    if current_attempts < max_attempts do
      state = Map.put(state, :reconnect_attempts, current_attempts + 1)
      {:reconnect, state}
    else
      {:ok, state}
    end
  end

  @impl true
  def handle_frame(:ping, frame_data, state) do
    # Automatically respond to pings with pongs
    {:reply, :pong, frame_data, state}
  end

  def handle_frame(:pong, _frame_data, state) do
    # Track pong responses
    state =
      state
      |> Map.put(:last_pong_received, System.monotonic_time(:millisecond))

    # Delete last_ping_sent if it exists, otherwise leave state unchanged
    state =
      if Map.has_key?(state, :last_ping_sent) do
        Map.delete(state, :last_ping_sent)
      else
        state
      end

    {:ok, state}
  end

  def handle_frame(_frame_type, _frame_data, state) do
    # Default implementation for other frame types
    {:ok, state}
  end

  @impl true
  def handle_timeout(state) do
    current_attempts = Map.get(state, :reconnect_attempts, 0)
    max_attempts = Map.get(state, :max_reconnect_attempts, @default_max_reconnect_attempts)

    if current_attempts < max_attempts do
      state = Map.put(state, :reconnect_attempts, current_attempts + 1)
      {:reconnect, state}
    else
      {:stop, :max_reconnect_attempts_reached, state}
    end
  end
end
