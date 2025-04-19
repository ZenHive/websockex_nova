defmodule MyApp.AdvancedClient do
  @moduledoc false
  use GenServer

  alias WebsockexNova.Client
  alias WebsockexNova.Connection

  @adapter WebsockexNova.Platform.Echo.Adapter

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    # Start a connection to the Echo adapter
    {:ok, conn_pid} = Connection.start_link(adapter: @adapter)
    {:ok, %{conn: conn_pid}}
  end

  @doc """
  Send a text message and get the reply (synchronously).
  """
  def echo_json(json) do
    GenServer.call(__MODULE__, {:echo_json, json})
  end

  @doc """
  Send a text message and get the reply (synchronously).
  """
  def echo_text(text) do
    GenServer.call(__MODULE__, {:echo_text, text})
  end

  @impl true
  def handle_call({:echo_text, text}, _from, %{conn: conn} = state) do
    reply = Client.send_text(conn, text)
    {:reply, reply, state}
  end

  @impl true
  def handle_call({:echo_json, json}, _from, %{conn: conn} = state) do
    reply = Client.send_json(conn, json)
    {:reply, reply, state}
  end
end
