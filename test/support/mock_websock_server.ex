defmodule WebsockexNova.Test.Support.MockWebSockServer do
  @moduledoc """
  A WebSock-based controllable WebSocket server for integration tests.

  This module provides a WebSocket server using the WebSock behavior,
  which can be controlled by test code to simulate various scenarios
  like disconnects, delayed responses, and errors.
  """

  use GenServer
  require Logger

  # Public API

  @doc """
  Starts a mock WebSocket server on a random available port.

  ## Options

  * `:port` - (optional) Port number to use. Defaults to a random available port.
  * `:path` - (optional) WebSocket path. Defaults to "/ws".

  ## Returns

  `{:ok, server_pid, port}` on success, where `port` is the port number the server
  is listening on, or `{:error, reason}` on failure.
  """
  def start_link(opts \\ []) do
    Logger.debug("Starting MockWebSockServer")

    case GenServer.start_link(__MODULE__, opts) do
      {:ok, pid} ->
        # Get the actual port the server is listening on
        case get_port(pid) do
          {:ok, actual_port} ->
            Logger.debug("MockWebSockServer started on port #{actual_port}")
            {:ok, pid, actual_port}

          error ->
            Logger.error("Failed to get port for MockWebSockServer: #{inspect(error)}")
            error
        end

      error ->
        Logger.error("Failed to start MockWebSockServer: #{inspect(error)}")
        error
    end
  end

  @doc """
  Stops the mock WebSocket server.
  """
  def stop(server_pid) do
    Logger.debug("Stopping MockWebSockServer")
    GenServer.stop(server_pid)
  end

  @doc """
  Gets the port number the server is listening on.
  """
  def get_port(server_pid) do
    GenServer.call(server_pid, :get_port)
  end

  @doc """
  Gets all clients currently connected to the server.

  Returns a list of client PIDs.
  """
  def get_clients(server_pid) do
    GenServer.call(server_pid, :get_clients)
  end

  @doc """
  Gets the number of clients currently connected to the server.
  """
  def client_count(server_pid) do
    GenServer.call(server_pid, :get_clients) |> length()
  end

  @doc """
  Sends a WebSocket text frame to all connected clients.
  """
  def broadcast_text(server_pid, text) do
    Logger.debug("Broadcasting text to all clients: #{inspect(text)}")
    GenServer.cast(server_pid, {:broadcast_text, text})
  end

  @doc """
  Sends a WebSocket binary frame to all connected clients.
  """
  def broadcast_binary(server_pid, data) do
    Logger.debug("Broadcasting binary data to all clients: #{byte_size(data)} bytes")
    GenServer.cast(server_pid, {:broadcast_binary, data})
  end

  @doc """
  Forcibly disconnects all clients with the given close code.

  ## Parameters

  * `server_pid` - The server PID
  * `code` - WebSocket close code (default: 1000 - normal closure)
  * `reason` - Close reason (default: "Server closing connection")
  """
  def disconnect_all(server_pid, code \\ 1000, reason \\ "Server closing connection") do
    Logger.debug("Disconnecting all clients: code=#{code}, reason=#{reason}")
    GenServer.cast(server_pid, {:disconnect_all, code, reason})
  end

  @doc """
  Gets all messages received by the server from clients.

  Returns a list of `{client_pid, message_type, message}` tuples where:
  - `client_pid` is the PID of the client that sent the message
  - `message_type` is either `:text` or `:binary`
  - `message` is the actual message content
  """
  def get_received_messages(server_pid) do
    messages = GenServer.call(server_pid, :get_received_messages)
    Logger.debug("Get received messages: #{length(messages)} messages")
    messages
  end

  @doc """
  Clears the list of received messages.
  """
  def clear_messages(server_pid) do
    Logger.debug("Clearing all received messages")
    GenServer.call(server_pid, :clear_messages)
  end

  @doc """
  Sets a delay for all responses from the server.

  ## Parameters

  * `server_pid` - The server PID
  * `delay_ms` - Delay in milliseconds (0 to disable)
  """
  def set_response_delay(server_pid, delay_ms) do
    Logger.debug("Setting response delay to #{delay_ms}ms")
    GenServer.call(server_pid, {:set_response_delay, delay_ms})
  end

  @doc """
  Configures the server to simulate a specific scenario.

  ## Scenarios

  * `:normal` - Normal WebSocket operation (default)
  * `:delayed_response` - Delay responses by the configured amount (see `set_response_delay/2`)
  * `:drop_messages` - Drop all incoming messages (don't respond)
  * `:echo_with_error` - Echo messages back but occasionally send error frames
  * `:unstable` - Randomly disconnect clients
  """
  def set_scenario(server_pid, scenario)
      when scenario in [:normal, :delayed_response, :drop_messages, :echo_with_error, :unstable] do
    Logger.debug("Setting server scenario to: #{inspect(scenario)}")
    GenServer.call(server_pid, {:set_scenario, scenario})
  end

  @doc """
  Forces a disconnect in test mode by sending a connection_down notification directly to the callback.
  Works together with ConnectionWrapper's test mode to simulate disconnects.
  """
  def force_test_disconnect(server_pid, client_handler_pid) do
    Logger.info("Simulating server disconnect in test mode")

    if client_handler_pid && Process.alive?(client_handler_pid) do
      # Send a connection_down message directly to the callback handler
      send(client_handler_pid, {:websockex_nova, {:connection_down, :http, "Test disconnect"}})
      Logger.debug("Disconnect notification sent to callback")
      :ok
    else
      Logger.warn("Cannot send disconnect notification - client handler not alive")
      {:error, :client_not_alive}
    end
  end

  # GenServer callbacks

  @impl true
  def init(opts) do
    path = Keyword.get(opts, :path, "/ws")
    # 0 means use a random port
    port = Keyword.get(opts, :port, 0)

    Logger.debug("Initializing MockWebSockServer with path: #{path}, port: #{port}")

    # Create a unique name for this server instance to avoid conflicts
    server_name = :"mock_websocket_server_#{System.unique_integer([:positive])}"

    # Create a plug router for handling HTTP and WebSocket requests
    defmodule Router do
      use Plug.Router

      # Special case to make the router definable inline in this module
      @server_parent Process.get(:server_parent)
      require Logger

      plug(:match)
      plug(:dispatch)

      get "/ws" do
        Logger.debug("Router received WebSocket upgrade request")

        conn =
          WebSockAdapter.upgrade(
            conn,
            WebsockexNova.Test.Support.MockWebSockHandler,
            [parent: @server_parent],
            []
          )

        # WebSockAdapter will take over the connection from here
        conn
      end

      match _ do
        Logger.debug("Router received non-WebSocket request: #{conn.request_path}")
        send_resp(conn, 404, "Not Found")
      end
    end

    # Set the parent process for the router to reference
    Process.put(:server_parent, self())

    # Start the server
    case Plug.Cowboy.http(Router, [], port: port, ref: server_name) do
      {:ok, _pid} ->
        # Get the actual port the server is listening on
        actual_port = :ranch.get_port(server_name)

        state = %{
          port: actual_port,
          path: path,
          clients: %{},
          messages: [],
          scenario: :normal,
          response_delay: 0,
          server_name: server_name
        }

        Logger.info("MockWebSockServer started on port #{actual_port}")
        {:ok, state}

      {:error, reason} = error ->
        Logger.error("Failed to start MockWebSockServer: #{inspect(reason)}")
        {:stop, error}
    end
  end

  @impl true
  def terminate(reason, state) do
    # Stop the HTTP server
    Logger.debug("MockWebSockServer terminating. Reason: #{inspect(reason)}")
    Plug.Cowboy.shutdown(state.server_name)
    :ok
  end

  @impl true
  def handle_call(:get_port, _from, state) do
    {:reply, {:ok, state.port}, state}
  end

  @impl true
  def handle_call(:get_clients, _from, state) do
    client_list = Map.keys(state.clients)
    Logger.debug("Current clients: #{length(client_list)} connected")
    {:reply, client_list, state}
  end

  @impl true
  def handle_call(:get_received_messages, _from, state) do
    {:reply, Enum.reverse(state.messages), state}
  end

  @impl true
  def handle_call(:clear_messages, _from, state) do
    {:reply, :ok, %{state | messages: []}}
  end

  @impl true
  def handle_call({:set_response_delay, delay_ms}, _from, state)
      when is_integer(delay_ms) and delay_ms >= 0 do
    {:reply, :ok, %{state | response_delay: delay_ms}}
  end

  @impl true
  def handle_call({:set_scenario, scenario}, _from, state) do
    {:reply, :ok, %{state | scenario: scenario}}
  end

  @impl true
  def handle_cast({:broadcast_text, text}, state) do
    client_count = map_size(state.clients)
    Logger.debug("Broadcasting text to #{client_count} clients: #{inspect(text)}")

    for client_pid <- Map.keys(state.clients) do
      send_text(client_pid, text, state)
    end

    {:noreply, state}
  end

  @impl true
  def handle_cast({:broadcast_binary, data}, state) do
    client_count = map_size(state.clients)
    Logger.debug("Broadcasting binary to #{client_count} clients: #{byte_size(data)} bytes")

    for client_pid <- Map.keys(state.clients) do
      send_binary(client_pid, data, state)
    end

    {:noreply, state}
  end

  @impl true
  def handle_cast({:disconnect_all, code, reason}, state) do
    client_count = map_size(state.clients)
    Logger.debug("Disconnecting #{client_count} clients with code: #{code}, reason: #{reason}")

    for client_pid <- Map.keys(state.clients) do
      send(client_pid, {:disconnect, code, reason})
    end

    {:noreply, state}
  end

  @impl true
  def handle_info({:register_client, pid, ref}, state) do
    # Monitor the client to detect disconnects
    Logger.debug("Registering new client: #{inspect(pid)}")
    _ref = Process.monitor(pid)

    # Store client info
    clients = Map.put(state.clients, pid, ref)
    client_count = map_size(clients)
    Logger.debug("Client registered. Total clients: #{client_count}")

    {:noreply, %{state | clients: clients}}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, reason}, state) do
    # Client process died, remove it from our state
    Logger.debug("Client process DOWN: #{inspect(pid)}, reason: #{inspect(reason)}")
    clients = Map.delete(state.clients, pid)
    client_count = map_size(clients)
    Logger.debug("Client removed. Total clients: #{client_count}")

    {:noreply, %{state | clients: clients}}
  end

  @impl true
  def handle_info({:client_terminated, pid, reason}, state) do
    # Client terminated normally, remove from our state if still present
    Logger.debug("Client terminated: #{inspect(pid)}, reason: #{inspect(reason)}")
    clients = Map.delete(state.clients, pid)
    client_count = map_size(clients)
    Logger.debug("Client removed. Total clients: #{client_count}")

    {:noreply, %{state | clients: clients}}
  end

  @impl true
  def handle_info({:websocket_message, client_pid, type, message}, state) do
    # Record the message
    message_info =
      case type do
        :text -> "TEXT: #{inspect(message)}"
        :binary -> "BINARY: #{byte_size(message)} bytes"
      end

    Logger.debug("Received WS message from #{inspect(client_pid)}: #{message_info}")
    messages = [{client_pid, type, message} | state.messages]

    # Handle based on current scenario
    scenario_response =
      case state.scenario do
        :normal ->
          Logger.debug("Scenario: normal - echoing message back immediately")
          # Echo the message back
          case type do
            :text -> send_text(client_pid, message, state)
            :binary -> send_binary(client_pid, message, state)
          end

          "echo"

        :delayed_response ->
          # Delay then echo
          if state.response_delay > 0 do
            Logger.debug(
              "Scenario: delayed_response - delaying echo by #{state.response_delay}ms"
            )

            Process.send_after(
              self(),
              {:delayed_echo, client_pid, type, message},
              state.response_delay
            )

            "delayed echo"
          else
            Logger.debug("Scenario: delayed_response - no delay configured, echoing immediately")

            case type do
              :text -> send_text(client_pid, message, state)
              :binary -> send_binary(client_pid, message, state)
            end

            "echo"
          end

        :drop_messages ->
          Logger.debug("Scenario: drop_messages - ignoring message")
          # Do nothing
          "dropped"

        :echo_with_error ->
          # Randomly send error or echo
          if :rand.uniform(10) <= 3 do
            Logger.debug("Scenario: echo_with_error - sending error response")
            # Send error 30% of the time
            send(client_pid, {:send_error, "Server error"})
            "error"
          else
            Logger.debug("Scenario: echo_with_error - echoing message")
            # Echo the message back
            case type do
              :text -> send_text(client_pid, message, state)
              :binary -> send_binary(client_pid, message, state)
            end

            "echo"
          end

        :unstable ->
          # Randomly disconnect
          if :rand.uniform(10) <= 2 do
            Logger.debug("Scenario: unstable - disconnecting client")
            # Disconnect 20% of the time
            send(client_pid, {:disconnect, 1001, "Server instability"})
            "disconnect"
          else
            Logger.debug("Scenario: unstable - echoing message")
            # Echo the message back
            case type do
              :text -> send_text(client_pid, message, state)
              :binary -> send_binary(client_pid, message, state)
            end

            "echo"
          end
      end

    Logger.debug("Message handled with scenario #{state.scenario}, action: #{scenario_response}")
    {:noreply, %{state | messages: messages}}
  end

  @impl true
  def handle_info({:delayed_echo, client_pid, type, message}, state) do
    Logger.debug("Processing delayed echo to client #{inspect(client_pid)}")

    case type do
      :text -> send_text(client_pid, message, state)
      :binary -> send_binary(client_pid, message, state)
    end

    {:noreply, state}
  end

  @impl true
  def handle_info(unexpected_message, state) do
    Logger.debug("MockWebSockServer received unexpected message: #{inspect(unexpected_message)}")
    {:noreply, state}
  end

  # Helper functions

  defp send_text(client_pid, text, _state) do
    if Process.alive?(client_pid) do
      Logger.debug("Sending TEXT frame to client #{inspect(client_pid)}: #{inspect(text)}")
      send(client_pid, {:send_text, text})
    else
      Logger.debug("Cannot send TEXT to dead client: #{inspect(client_pid)}")
    end
  end

  defp send_binary(client_pid, data, _state) do
    if Process.alive?(client_pid) do
      Logger.debug(
        "Sending BINARY frame to client #{inspect(client_pid)}: #{byte_size(data)} bytes"
      )

      send(client_pid, {:send_binary, data})
    else
      Logger.debug("Cannot send BINARY to dead client: #{inspect(client_pid)}")
    end
  end
end
