defmodule WebsockexNova.Test.Support.MockWebSockServer do
  @moduledoc """
  A simple WebSocket server for testing WebsockexNova clients.
  
  This server:
  - Starts on a dynamic port by default
  - Accepts WebSocket connections
  - Allows custom handlers for incoming frames
  - Can be stopped to simulate disconnections
  
  ## Usage
  
  ```elixir
  # Start the server (gets a dynamic port)
  {:ok, server_pid, port} = MockWebSockServer.start_link()
  
  # Set a custom handler for frames
  MockWebSockServer.set_handler(server_pid, fn
    {:text, "ping"} -> {:reply, {:text, "pong"}}
    {:text, msg} -> {:reply, {:text, "echo: " <> msg}}
  end)
  
  # Stop the server to simulate a disconnect
  MockWebSockServer.stop(server_pid)
  ```
  """
  
  use GenServer
  require Logger
  
  @default_path "/ws"
  
  defmodule WebSocketHandler do
    @behaviour :cowboy_websocket
    
    def init(req, state) do
      {:cowboy_websocket, req, state}
    end
    
    def websocket_init(state) do
      {:ok, state}
    end
    
    def websocket_handle({:text, "internal:get_handler"}, %{parent: parent} = state) do
      send(parent, {:get_handler_request, self()})
      {:ok, state}
    end
    
    def websocket_handle(frame, %{parent: _parent, handler: handler} = state) when is_function(handler) do
      case handler.(frame) do
        {:reply, response} -> {:reply, response, state}
        :ok -> {:ok, state}
        other -> 
          Logger.warning("Unknown response from handler: #{inspect(other)}")
          {:ok, state}
      end
    end
    
    def websocket_handle(frame, %{parent: _parent} = state) do
      # Default handler with common patterns for tests
      case frame do
        {:text, "ping"} -> {:reply, {:text, "pong"}, state}
        {:text, "subscribe:" <> channel} -> {:reply, {:text, "subscribed:#{channel}"}, state}
        {:text, "unsubscribe:" <> channel} -> {:reply, {:text, "unsubscribed:#{channel}"}, state}
        {:text, "authenticate"} -> {:reply, {:text, "authenticated"}, state}
        {:text, msg} -> {:reply, {:text, "echo: #{msg}"}, state}
        {:binary, data} -> {:reply, {:binary, data}, state}
        _ -> {:ok, state}
      end
    end
    
    def websocket_info({:set_handler, handler}, state) do
      {:ok, Map.put(state, :handler, handler)}
    end
    
    def websocket_info(info, state) do
      Logger.debug("WebSocketHandler received unhandled info: #{inspect(info)}")
      {:ok, state}
    end
    
    def terminate(reason, _req, _state) do
      Logger.debug("WebSocketHandler terminating: #{inspect(reason)}")
      :ok
    end
  end
  
  def start_link(port \\ 0) do
    with {:ok, pid} <- GenServer.start_link(__MODULE__, port) do
      actual_port = get_port(pid)
      {:ok, pid, actual_port}
    end
  end
  
  def set_handler(server, handler) when is_function(handler, 1) do
    GenServer.call(server, {:set_handler, handler})
  end
  
  def get_port(server) do
    GenServer.call(server, :get_port)
  end
  
  def get_connections(server) do
    GenServer.call(server, :get_connections)
  end
  
  def stop(server) do
    if Process.alive?(server) do
      GenServer.call(server, :stop, 10000)
    else
      :ok
    end
  end
  
  # GenServer callbacks
  
  def init(port) do
    # Use a unique name for each server instance to avoid conflicts
    server_name = :"mock_websocket_server_#{System.unique_integer([:positive])}"
    
    # Define the dispatch rules for cowboy
    dispatch = :cowboy_router.compile([
      {:_, [
        {@default_path, WebSocketHandler, %{parent: self(), handler: nil}},
      ]}
    ])
    
    # Start cowboy
    {:ok, listener_pid} = :cowboy.start_clear(
      server_name,
      [{:port, port}],
      %{env: %{dispatch: dispatch}}
    )
    
    # Get the actual port (important when using port 0)
    # The return format appears to be {ip_tuple, port_number}
    {_, actual_port} = :ranch.get_addr(server_name)
    
    Logger.debug("MockWebSockServer started on port #{actual_port}")
    
    {:ok, %{
      port: actual_port,
      listener_pid: listener_pid,
      connections: %{},
      handler: nil,
      server_name: server_name
    }, {:continue, {:return_port, actual_port}}}
  end
  
  def handle_continue({:return_port, _port}, state) do
    {:noreply, state}
  end
  
  def handle_call({:set_handler, handler}, _from, state) do
    # Set the handler for all current connections
    Enum.each(Map.values(state.connections), fn ws_pid ->
      if Process.alive?(ws_pid) do
        send(ws_pid, {:set_handler, handler})
      end
    end)
    
    {:reply, :ok, %{state | handler: handler}}
  end
  
  def handle_call(:get_port, _from, state) do
    {:reply, state.port, state}
  end
  
  def handle_call(:get_connections, _from, state) do
    # Filter out dead connections
    live_connections = Enum.filter(state.connections, fn {_, pid} -> Process.alive?(pid) end)
    |> Enum.into(%{})
    
    {:reply, live_connections, %{state | connections: live_connections}}
  end
  
  def handle_call(:stop, _from, state) do
    if Map.has_key?(state, :server_name) do
      :ok = :cowboy.stop_listener(state.server_name)
    end
    {:stop, :normal, :ok, state}
  end
  
  def handle_info({:get_handler_request, ws_pid}, state) do
    # Register the new connection
    ref = make_ref()
    updated_connections = Map.put(state.connections, ref, ws_pid)
    
    # Send the current handler to the connection
    if state.handler != nil do
      send(ws_pid, {:set_handler, state.handler})
    end
    
    {:noreply, %{state | connections: updated_connections}}
  end
  
  def handle_info(info, state) do
    Logger.debug("MockWebSockServer received unhandled info: #{inspect(info)}")
    {:noreply, state}
  end
  
  def terminate(_reason, state) do
    if :erlang.function_exported(:cowboy, :stop_listener, 1) and Map.has_key?(state, :server_name) do
      :cowboy.stop_listener(state.server_name)
    end
    :ok
  end
end