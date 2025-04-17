defmodule WebsockexNova.Gun.DummyClient do
  @moduledoc """
  A dummy Gun client module for testing the supervisor functionality.

  This module implements a simple GenServer that simulates a Gun client connection.
  It will be replaced by the actual Gun connection wrapper implementation in tasks T2.3 and T2.4.
  """

  use GenServer
  require Logger

  @doc """
  Starts a new dummy Gun client process.

  ## Parameters

  * `opts` - A map containing client options
  * `name` - Optional name to register the client process

  ## Returns

  Returns `{:ok, pid}` if successful, or `{:error, reason}` if there's an error.
  """
  def start_link(opts, name \\ nil) do
    if name,
      do: GenServer.start_link(__MODULE__, opts, name: name),
      else: GenServer.start_link(__MODULE__, opts)
  end

  @impl true
  def init(opts) do
    Logger.debug("Starting dummy Gun client with options: #{inspect(opts)}")

    # In a real implementation, we would open a Gun connection here
    state = %{
      # This would be the actual Gun connection pid
      gun_pid: nil,
      options: opts,
      status: :initialized,
      stream_ref: nil
    }

    # Simulate connection startup
    Process.send_after(self(), :connect, 100)

    {:ok, state}
  end

  @impl true
  def handle_info(:connect, state) do
    Logger.debug("Dummy Gun client connecting to #{state.options.host}:#{state.options.port}")

    # In a real implementation, this would call :gun.open/3
    # For now, we'll just pretend we're connected
    new_state = %{state | status: :connected}

    # Simulate a WebSocket upgrade after connection
    Process.send_after(self(), :upgrade_websocket, 100)

    {:noreply, new_state}
  end

  def handle_info(:upgrade_websocket, state) do
    Logger.debug("Dummy Gun client upgrading to WebSocket on #{state.options.websocket_path}")

    # In a real implementation, this would call :gun.ws_upgrade/3
    # For now, we'll just pretend the upgrade succeeded
    new_state = %{state | status: :websocket_connected, stream_ref: make_ref()}

    {:noreply, new_state}
  end

  @doc """
  Simulates sending a WebSocket frame.

  ## Parameters

  * `client` - The client pid or name
  * `frame_type` - The type of WebSocket frame (:text, :binary, :ping, :pong, :close)
  * `data` - The frame payload

  ## Returns

  Returns `:ok` if successful.
  """
  def send_frame(client, frame_type, data)
      when frame_type in [:text, :binary, :ping, :pong, :close] do
    GenServer.call(client, {:send_frame, frame_type, data})
  end

  @doc """
  Returns the current state of the dummy Gun client.

  ## Parameters

  * `client` - The client pid or name

  ## Returns

  Returns the client's internal state.
  """
  def get_state(client) do
    GenServer.call(client, :get_state)
  end

  @impl true
  def handle_call({:send_frame, frame_type, data}, _from, state) do
    Logger.debug("Dummy Gun client sending #{frame_type} frame: #{inspect(data)}")

    # In a real implementation, this would call :gun.ws_send/3
    # For now, we'll just log the frame and pretend it was sent

    {:reply, :ok, state}
  end

  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def terminate(reason, _state) do
    Logger.debug("Dummy Gun client terminating: #{inspect(reason)}")

    # In a real implementation, we would close the Gun connection here
    # with :gun.close/1

    :ok
  end
end
