defmodule WebsockexNova.Connection do
  @moduledoc """
  Process-based connection wrapper for platform adapters (e.g., Echo).

  ## Usage

      {:ok, pid} = WebsockexNova.Connection.start_link(adapter: WebsockexNova.Platform.Echo.Adapter)
      send(pid, {:platform_message, {:text, "Hello"}, self()})
      flush()
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

  @impl true
  def terminate(reason, state) do
    Logger.debug("WebsockexNova.Connection terminating: reason=#{inspect(reason)}, state=#{inspect(state)}")
    :ok
  end
end
