defmodule WebsockexNova.Test.Support.MockWebSockServer do
  @moduledoc """
  A WebSock-based controllable WebSocket server for integration tests.

  This module provides a WebSocket server using the WebSock behavior,
  which can be controlled by test code to simulate various scenarios
  like disconnects, delayed responses, and errors.

  ## Protocol Support

  The server supports multiple protocols and transports:

  * `:http` - Standard HTTP/1.1 (ws://)
  * `:http2` - HTTP/2 (h2c://)
  * `:tls` - HTTP/1.1 over TLS (wss://)
  * `:https2` - HTTP/2 over TLS (h2://)

  ## Example

  ```elixir
  # Start a TLS (secure WebSocket) server
  {:ok, server_pid, port} = MockWebSockServer.start_link(protocol: :tls)

  # Use ConnectionWrapper to connect with proper options
  {:ok, conn_pid} = ConnectionWrapper.open("localhost", port, %{
    transport: :tls,
    transport_opts: [verify: :verify_none]
  })
  ```
  """

  use GenServer

  alias WebsockexNova.Test.Support.CertificateHelper
  alias WebsockexNova.Test.Support.MockWebSockServer.Router

  require Logger

  # Public API

  @doc """
  Starts a mock WebSocket server on a random available port.

  ## Options

  * `:port` - (optional) Port number to use. Defaults to a random available port.
  * `:path` - (optional) WebSocket path. Defaults to "/ws".
  * `:protocol` - (optional) Protocol to use. Options:
      * `:http` - HTTP/1.1 (default)
      * `:http2` - HTTP/2
      * `:tls` - HTTP/1.1 over TLS
      * `:https2` - HTTP/2 over TLS
  * `:certfile` - (optional) Path to TLS certificate file. Auto-generated if not provided.
  * `:keyfile` - (optional) Path to TLS key file. Auto-generated if not provided.
  * `:name` - (optional) Name for the GenServer process

  ## Returns

  `{:ok, server_pid, port}` on success, where `port` is the port number the server
  is listening on, or `{:error, reason}` on failure.
  """
  def start_link(opts \\ []) do
    Logger.debug("Starting MockWebSockServer")
    name = Keyword.get(opts, :name, nil)
    genserver_opts = if name, do: [name: name], else: []

    case GenServer.start_link(__MODULE__, opts, genserver_opts) do
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
  Gets the protocol the server is using.

  Returns one of: `:http`, `:http2`, `:tls`, or `:https2`
  """
  def get_protocol(server_pid) do
    GenServer.call(server_pid, :get_protocol)
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
    server_pid |> GenServer.call(:get_clients) |> length()
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
  * `:custom` - Use a custom handler function for message processing
  """
  @spec set_scenario(pid(), atom(), function() | nil) :: :ok
  def set_scenario(server_pid, scenario, custom_handler \\ nil)
      when scenario in [:normal, :delayed_response, :drop_messages, :echo_with_error, :unstable, :custom] do
    Logger.debug("Setting server scenario to #{scenario}")
    GenServer.call(server_pid, {:set_scenario, scenario, custom_handler})
  end

  @doc """
  Forces a disconnect in test mode by sending a connection_down notification directly to the callback.
  Works together with ConnectionWrapper's test mode to simulate disconnects.
  """
  def force_test_disconnect(_server_pid, client_handler_pid) do
    Logger.info("Simulating server disconnect in test mode")

    if client_handler_pid && Process.alive?(client_handler_pid) do
      # Send a connection_down message directly to the callback handler
      send(client_handler_pid, {:websockex_nova, {:connection_down, :http, "Test disconnect"}})
      Logger.debug("Disconnect notification sent to callback")
      :ok
    else
      Logger.warning("Cannot send disconnect notification - client handler not alive")
      {:error, :client_not_alive}
    end
  end

  # GenServer callbacks

  @impl true
  def init(opts) do
    path = Keyword.get(opts, :path, "/ws")
    # 0 means use a random port
    port = Keyword.get(opts, :port, 0)
    protocol = Keyword.get(opts, :protocol, :http)

    # Check for TLS certificates or generate if needed
    {certfile, keyfile} = get_tls_files(protocol, opts)

    Logger.debug("Initializing MockWebSockServer with path: #{path}, port: #{port}, protocol: #{protocol}")

    # Create a unique name for this server instance to avoid conflicts
    server_name = :"mock_websocket_server_#{System.unique_integer([:positive])}"

    # Set the parent process for the router to reference
    Process.put(:server_parent, self())

    # Start the server with appropriate protocol options
    start_result = start_server(protocol, server_name, port, certfile, keyfile)

    case start_result do
      {:ok, _pid} ->
        # Get the actual port the server is listening on
        actual_port = :ranch.get_port(server_name)

        state = %{
          port: actual_port,
          path: path,
          protocol: protocol,
          clients: %{},
          messages: [],
          scenario: :normal,
          response_delay: 0,
          server_name: server_name,
          certfile: certfile,
          keyfile: keyfile
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
  def handle_call(:get_protocol, _from, state) do
    {:reply, state.protocol, state}
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
  def handle_call({:set_response_delay, delay_ms}, _from, state) when is_integer(delay_ms) and delay_ms >= 0 do
    {:reply, :ok, %{state | response_delay: delay_ms}}
  end

  @impl true
  def handle_call({:set_scenario, scenario, custom_handler}, _from, state) do
    new_state = %{state | scenario: scenario}

    # Store custom handler if provided
    new_state =
      if scenario == :custom && is_function(custom_handler) do
        Map.put(new_state, :custom_handler, custom_handler)
      else
        Map.put(new_state, :custom_handler, nil)
      end

    {:reply, :ok, new_state}
  end

  @impl true
  def handle_cast({:broadcast_text, text}, state) do
    client_count = map_size(state.clients)
    Logger.debug("Broadcasting text to #{client_count} clients: #{inspect(text)}")

    Enum.each(Map.keys(state.clients), fn client_pid ->
      send_text(client_pid, text, state)
    end)

    {:noreply, state}
  end

  @impl true
  def handle_cast({:broadcast_binary, data}, state) do
    client_count = map_size(state.clients)
    Logger.debug("Broadcasting binary to #{client_count} clients: #{byte_size(data)} bytes")

    Enum.each(Map.keys(state.clients), fn client_pid ->
      send_binary(client_pid, data, state)
    end)

    {:noreply, state}
  end

  @impl true
  def handle_cast({:disconnect_all, code, reason}, state) do
    client_count = map_size(state.clients)
    Logger.debug("Disconnecting #{client_count} clients with code: #{code}, reason: #{reason}")

    Enum.each(Map.keys(state.clients), fn client_pid ->
      send(client_pid, {:disconnect, code, reason})
    end)

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
    message_info =
      case type do
        :text -> "TEXT: #{inspect(message)}"
        :binary -> "BINARY: #{byte_size(message)} bytes"
      end

    Logger.debug("Received WS message from #{inspect(client_pid)}: #{message_info}")
    messages = [{client_pid, type, message} | state.messages]

    scenario_response = handle_scenario(state.scenario, client_pid, type, message, state)

    Logger.debug("Message handled with scenario #{state.scenario}, action: #{scenario_response}")
    {:noreply, %{state | messages: messages}}
  end

  @impl true
  def handle_info({:delayed_echo, client_pid, type, message}, state) do
    Logger.debug("Processing delayed echo for client: #{inspect(client_pid)}")
    echo_message(client_pid, type, message, state)
    {:noreply, state}
  end

  @impl true
  def handle_info({:set_token_expired, value}, state) when is_boolean(value) do
    Process.put(:token_expired, value)
    {:noreply, state}
  end

  # Private functions

  # Start server with appropriate protocol
  defp start_server(:http, server_name, port, _certfile, _keyfile) do
    Logger.debug("Starting HTTP server (ws://) on port #{port}")
    Plug.Cowboy.http(Router, [server_pid: self()], port: port, ref: server_name)
  end

  defp start_server(:http2, server_name, port, _certfile, _keyfile) do
    Logger.debug("Starting HTTP/2 server (h2c://) on port #{port}")
    # HTTP/2 cleartext (h2c) with fallback to HTTP/1.1
    Plug.Cowboy.http(Router, [server_pid: self()],
      port: port,
      ref: server_name,
      protocol_options: [versions: [:h2, :"http/1.1"]]
    )
  end

  defp start_server(:tls, server_name, port, certfile, keyfile) do
    Logger.debug("Starting HTTPS server (wss://) on port #{port}")
    # HTTPS with TLS
    Plug.Cowboy.https(Router, [server_pid: self()],
      port: port,
      ref: server_name,
      keyfile: keyfile,
      certfile: certfile
    )
  end

  defp start_server(:https2, server_name, port, certfile, keyfile) do
    Logger.debug("Starting HTTP/2 over TLS server (h2://) on port #{port}")
    # HTTP/2 over TLS (h2) with fallback to HTTP/1.1
    Plug.Cowboy.https(Router, [server_pid: self()],
      port: port,
      ref: server_name,
      keyfile: keyfile,
      certfile: certfile,
      protocol_options: [versions: [:h2, :"http/1.1"]]
    )
  end

  # Get or generate TLS certificate and key files
  defp get_tls_files(protocol, opts) when protocol in [:tls, :https2] do
    certfile = Keyword.get(opts, :certfile)
    keyfile = Keyword.get(opts, :keyfile)

    if certfile && keyfile do
      # Use provided files
      {certfile, keyfile}
    else
      # Generate temporary self-signed certificate
      Logger.debug("No TLS certificates provided, generating temporary self-signed certificates")
      CertificateHelper.generate_self_signed_certificate()
    end
  end

  defp get_tls_files(_protocol, _opts), do: {nil, nil}

  # Handle scenarios based on the configuration
  defp handle_scenario(:normal, client_pid, type, message, state) do
    # Echo the message back after any configured delay
    maybe_delay_response(client_pid, type, message, state)
    :echo
  end

  defp handle_scenario(:delayed_response, client_pid, type, message, state) do
    # Always delay by the configured amount
    if state.response_delay > 0 do
      Process.send_after(self(), {:delayed_echo, client_pid, type, message}, state.response_delay)
      :delayed
    else
      maybe_delay_response(client_pid, type, message, state)
      :echo
    end
  end

  defp handle_scenario(:drop_messages, _client_pid, _type, _message, _state) do
    # Don't respond at all
    :drop
  end

  defp handle_scenario(:echo_with_error, client_pid, type, message, state) do
    # Randomly send an error message instead of echo
    if :rand.uniform(10) <= 3 do
      # 30% chance of error
      send(client_pid, {:send_error, "Random server error"})
      :error
    else
      maybe_delay_response(client_pid, type, message, state)
      :echo
    end
  end

  defp handle_scenario(:unstable, client_pid, _type, _message, _state) do
    # Randomly disconnect
    if :rand.uniform(10) <= 2 do
      # 20% chance of disconnect
      send(client_pid, {:disconnect, 1001, "Random server disconnect"})
      :disconnect
    else
      # Otherwise just echo
      echo_message(client_pid, :text, "Server is unstable", nil)
      :echo
    end
  end

  defp handle_scenario(:custom, client_pid, type, message, state) do
    # Use the custom handler if defined
    if is_function(state.custom_handler, 3) do
      state.custom_handler.(client_pid, type, message)
      :custom
    else
      # Fallback to normal behavior
      maybe_delay_response(client_pid, type, message, state)
      :echo
    end
  end

  defp handle_scenario(other, client_pid, type, message, state) do
    Logger.warning("Unknown scenario #{inspect(other)}, falling back to normal")
    maybe_delay_response(client_pid, type, message, state)
    :echo
  end

  defp maybe_delay_response(client_pid, type, message, state) do
    echo_message(client_pid, type, message, state)
  end

  defp echo_message(client_pid, :text, message, state), do: send_text(client_pid, message, state)
  defp echo_message(client_pid, :binary, message, state), do: send_binary(client_pid, message, state)

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
      Logger.debug("Sending BINARY frame to client #{inspect(client_pid)}: #{byte_size(data)} bytes")

      send(client_pid, {:send_binary, data})
    else
      Logger.debug("Cannot send BINARY to dead client: #{inspect(client_pid)}")
    end
  end
end
