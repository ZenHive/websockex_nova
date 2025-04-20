defmodule WebsockexNova.Connection do
  @moduledoc """
  Process-based, adapter-agnostic connection wrapper for platform adapters (e.g., Echo, Deribit).

  This module provides a GenServer process that manages the lifecycle of a platform adapter connection.
  It routes messages to the adapter, supports monitoring and clean shutdown, and is intended to be used
  with the ergonomic `WebsockexNova.Client` API.

  - Adapter-agnostic: works with any adapter implementing the platform contract.
  - Use with `WebsockexNova.Client` for a safe, documented interface.
  - See the Echo adapter for a minimal example, and featureful adapters for advanced usage.

  ## Usage

      {:ok, pid} = WebsockexNova.Connection.start_link(adapter: WebsockexNova.Platform.Echo.Adapter)
      WebsockexNova.Client.send_text(pid, "Hello")
  """
  use GenServer

  alias WebsockexNova.Gun.ConnectionWrapper

  require Logger

  @doc """
  Starts a connection process for the given adapter.
  Expects opts to include :adapter (the adapter module).
  """
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @impl true
  def init(opts) do
    adapter = Keyword.fetch!(opts, :adapter)
    opts_map = Map.new(opts)
    {:ok, adapter_state} = adapter.init(opts_map)
    # ws_pid and stream_ref are nil until upgraded; frame_buffer holds frames to send once ready
    {:ok, %{adapter: adapter, state: adapter_state, ws_pid: nil, stream_ref: nil, frame_buffer: []}}
  end

  @doc """
  Called by the Gun connection wrapper when the WebSocket is established.
  Flushes any buffered frames.
  """
  def handle_info({:set_ws, ws_pid, stream_ref}, s) do
    # Flush any buffered frames
    Enum.each(Enum.reverse(s.frame_buffer), fn frame ->
      :ok = ConnectionWrapper.send_frame(ws_pid, stream_ref, frame)
    end)

    {:noreply, %{s | ws_pid: ws_pid, stream_ref: stream_ref, frame_buffer: []}}
  end

  @impl true
  def handle_info({:platform_message, message, from}, %{adapter: adapter, state: state} = s) do
    case adapter.handle_platform_message(message, state) do
      {:reply, reply, new_state} ->
        send(from, {:reply, reply})
        {:noreply, %{s | state: new_state}}

      {:ok, new_state} ->
        {:noreply, %{s | state: new_state}}

      {:noreply, new_state} ->
        {:noreply, %{s | state: new_state}}

      {:error, _error_info, new_state} ->
        {:noreply, %{s | state: new_state}}
    end
  end

  # Send a frame over the WebSocket (called by the adapter via send(self(), {:send_frame, frame}))
  @impl true
  def handle_info({:send_frame, frame}, %{ws_pid: ws_pid, stream_ref: stream_ref} = s)
      when not is_nil(ws_pid) and not is_nil(stream_ref) do
    :ok = ConnectionWrapper.send_frame(ws_pid, stream_ref, frame)
    {:noreply, s}
  end

  def handle_info({:send_frame, frame}, s) do
    # Buffer the frame until the WebSocket is ready
    {:noreply, %{s | frame_buffer: [frame | s.frame_buffer]}}
  end

  # Route incoming WebSocket frames to the adapter's handle_info/2
  @impl true
  def handle_info({:websocket_frame, frame}, %{adapter: adapter, state: state} = s) do
    case adapter.handle_info({:websocket_frame, frame}, state) do
      {:noreply, new_state} ->
        {:noreply, %{s | state: new_state}}

      other ->
        Logger.warning("Unexpected return from adapter.handle_info/2: #{inspect(other)}")
        {:noreply, s}
    end
  end

  # Subscribe
  @impl true
  def handle_info({:subscribe, channel, params, from}, %{adapter: adapter, state: state} = s) do
    if function_exported?(adapter, :subscribe, 3) do
      case adapter.subscribe(channel, params, state) do
        {:reply, reply, new_state} ->
          send(from, {:reply, reply})
          {:noreply, %{s | state: new_state}}

        {:noreply, new_state} ->
          {:noreply, %{s | state: new_state}}

        {:error, reason, new_state} ->
          send(from, {:error, reason})
          {:noreply, %{s | state: new_state}}
      end
    else
      Logger.error("Adapter #{inspect(adapter)} does not implement subscribe/3")
      send(from, {:error, :not_implemented})
      {:noreply, s}
    end
  end

  # Unsubscribe
  @impl true
  def handle_info({:unsubscribe, channel, from}, %{adapter: adapter, state: state} = s) do
    if function_exported?(adapter, :unsubscribe, 2) do
      case adapter.unsubscribe(channel, state) do
        {:reply, reply, new_state} ->
          send(from, {:reply, reply})
          {:noreply, %{s | state: new_state}}

        {:noreply, new_state} ->
          {:noreply, %{s | state: new_state}}

        {:error, reason, new_state} ->
          send(from, {:error, reason})
          {:noreply, %{s | state: new_state}}
      end
    else
      Logger.error("Adapter #{inspect(adapter)} does not implement unsubscribe/2")
      send(from, {:error, :not_implemented})
      {:noreply, s}
    end
  end

  # Authenticate
  @impl true
  def handle_info({:authenticate, credentials, from}, %{adapter: adapter, state: state} = s) do
    if function_exported?(adapter, :authenticate, 2) do
      case adapter.authenticate(credentials, state) do
        {:reply, reply, new_state} ->
          send(from, {:reply, reply})
          {:noreply, %{s | state: new_state}}

        {:noreply, new_state} ->
          {:noreply, %{s | state: new_state}}

        {:error, reason, new_state} ->
          send(from, {:error, reason})
          {:noreply, %{s | state: new_state}}
      end
    else
      Logger.error("Adapter #{inspect(adapter)} does not implement authenticate/2")
      send(from, {:error, :not_implemented})
      {:noreply, s}
    end
  end

  # Ping
  @impl true
  def handle_info({:ping, from}, %{adapter: adapter, state: state} = s) do
    if function_exported?(adapter, :ping, 1) do
      case adapter.ping(state) do
        {:reply, reply, new_state} ->
          send(from, {:reply, reply})
          {:noreply, %{s | state: new_state}}

        {:noreply, new_state} ->
          {:noreply, %{s | state: new_state}}

        {:error, reason, new_state} ->
          send(from, {:error, reason})
          {:noreply, %{s | state: new_state}}
      end
    else
      Logger.error("Adapter #{inspect(adapter)} does not implement ping/1")
      send(from, {:error, :not_implemented})
      {:noreply, s}
    end
  end

  # Status
  @impl true
  def handle_info({:status, from}, %{adapter: adapter, state: state} = s) do
    if function_exported?(adapter, :status, 1) do
      case adapter.status(state) do
        {:reply, reply, new_state} ->
          send(from, {:reply, reply})
          {:noreply, %{s | state: new_state}}

        {:noreply, new_state} ->
          {:noreply, %{s | state: new_state}}

        {:error, reason, new_state} ->
          send(from, {:error, reason})
          {:noreply, %{s | state: new_state}}
      end
    else
      Logger.error("Adapter #{inspect(adapter)} does not implement status/1")
      send(from, {:error, :not_implemented})
      {:noreply, s}
    end
  end

  # Catch-all for unexpected messages: log and crash (let it crash philosophy)
  @impl true
  def handle_info(msg, state) do
    Logger.error("Unexpected message in WebsockexNova.Connection: #{inspect(msg)} | state: #{inspect(state)}")
    raise "Unexpected message in WebsockexNova.Connection: #{inspect(msg)}"
  end

  @impl true
  def terminate(reason, state) do
    Logger.debug("WebsockexNova.Connection terminating: reason=#{inspect(reason)}, state=#{inspect(state)}")
    :ok
  end
end
