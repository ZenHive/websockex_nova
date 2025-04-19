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
    {:ok, %{adapter: adapter, state: adapter_state}}
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

  # Stub handlers for unsupported operations (subscribe, unsubscribe, authenticate, ping, status)
  # Adapters that support these should override and handle them appropriately.
  @impl true
  def handle_info({:subscribe, _channel, _params, from}, s) do
    send(from, {:reply, {:text, ""}})
    {:noreply, s}
  end

  @impl true
  def handle_info({:unsubscribe, _channel, from}, s) do
    send(from, {:reply, {:text, ""}})
    {:noreply, s}
  end

  @impl true
  def handle_info({:authenticate, _credentials, from}, s) do
    send(from, {:reply, {:text, ""}})
    {:noreply, s}
  end

  @impl true
  def handle_info({:ping, from}, s) do
    send(from, {:reply, {:text, ""}})
    {:noreply, s}
  end

  @impl true
  def handle_info({:status, from}, s) do
    send(from, {:reply, {:text, ""}})
    {:noreply, s}
  end

  @impl true
  def terminate(reason, state) do
    Logger.debug("WebsockexNova.Connection terminating: reason=#{inspect(reason)}, state=#{inspect(state)}")
    :ok
  end
end
