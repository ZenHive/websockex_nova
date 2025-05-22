defmodule WebsockexNew.ConfigurableTestServer do
  @moduledoc """
  Enhanced test server with configurable behavior for testing
  various network conditions and server responses.
  
  Builds on MockWebSockServer with additional capabilities:
  - Configurable latency simulation
  - Error injection and failure rates
  - Protocol violations for edge case testing
  - Network condition simulation
  """

  use GenServer
  require Logger

  @type server_behavior :: %{
    latency: non_neg_integer(),           # Response delay in ms
    error_rate: float(),                  # 0.0 to 1.0
    disconnect_rate: float(),             # Random disconnection rate
    message_corruption: boolean(),        # Corrupt some messages
    protocol_violations: boolean()        # Send invalid WebSocket frames
  }

  @type server_config :: %{
    port: pos_integer(),
    behavior: server_behavior(),
    protocols: [String.t()],
    tls: boolean()
  }

  defstruct [
    :port,
    :cowboy_ref,
    :behavior,
    :protocols,
    :tls,
    connections: %{},
    message_count: 0
  ]

  @default_behavior %{
    latency: 0,
    error_rate: 0.0,
    disconnect_rate: 0.0,
    message_corruption: false,
    protocol_violations: false
  }

  # Public API

  @doc """
  Starts a configurable test server on a random available port.
  
  ## Options
  - `:behavior` - Server behavior configuration (see `@type server_behavior`)
  - `:protocols` - List of supported WebSocket subprotocols
  - `:tls` - Whether to use TLS (default: false)
  - `:port` - Specific port to use (default: random available port)
  """
  @spec start_server(keyword()) :: {:ok, pos_integer()} | {:error, term()}
  def start_server(opts \\ []) do
    behavior = Keyword.get(opts, :behavior, @default_behavior)
    protocols = Keyword.get(opts, :protocols, [])
    tls = Keyword.get(opts, :tls, false)
    port = Keyword.get(opts, :port, 0)

    config = %{
      behavior: Map.merge(@default_behavior, behavior),
      protocols: protocols,
      tls: tls,
      port: port
    }

    case GenServer.start_link(__MODULE__, config) do
      {:ok, pid} ->
        {:ok, actual_port} = GenServer.call(pid, :get_port)
        {:ok, actual_port}
      
      error ->
        error
    end
  end

  @doc """
  Updates the server behavior configuration at runtime.
  """
  @spec configure_behavior(pos_integer(), server_behavior()) :: :ok | {:error, :not_found}
  def configure_behavior(port, behavior) do
    case find_server_by_port(port) do
      {:ok, pid} ->
        GenServer.call(pid, {:configure_behavior, behavior})
        :ok
      
      :error ->
        {:error, :not_found}
    end
  end

  @doc """
  Injects a specific error condition into the server.
  
  Error types:
  - `:disconnect_all` - Disconnect all current connections
  - `:send_invalid_frame` - Send malformed WebSocket frame
  - `:timeout_responses` - Stop responding to messages
  - `:send_large_payload` - Send oversized message
  """
  @spec inject_error(pos_integer(), atom()) :: :ok | {:error, :not_found}
  def inject_error(port, error_type) do
    case find_server_by_port(port) do
      {:ok, pid} ->
        GenServer.call(pid, {:inject_error, error_type})
        :ok
      
      :error ->
        {:error, :not_found}
    end
  end

  @doc """
  Gets current server statistics.
  """
  @spec get_stats(pos_integer()) :: {:ok, map()} | {:error, :not_found}
  def get_stats(port) do
    case find_server_by_port(port) do
      {:ok, pid} ->
        {:ok, GenServer.call(pid, :get_stats)}
      
      :error ->
        {:error, :not_found}
    end
  end

  @doc """
  Stops the test server.
  """
  @spec stop_server(pos_integer()) :: :ok
  def stop_server(port) do
    case find_server_by_port(port) do
      {:ok, pid} ->
        GenServer.stop(pid)
        :ok
      
      :error ->
        :ok
    end
  end

  # GenServer implementation

  @impl true
  def init(config) do
    # Register this server process globally by port for easy lookup
    port = config.port
    
    # Start Cowboy server
    dispatch = :cowboy_router.compile([
      {:_, [
        {"/ws", ConfigurableWebSockHandler, %{server_pid: self()}},
        {:_, :cowboy_static, {:priv_file, :websockex_new, "static/index.html"}}
      ]}
    ])

    cowboy_opts = if config.tls do
      [
        port: port,
        certfile: WebsockexNew.CertificateHelper.cert_path(),
        keyfile: WebsockexNew.CertificateHelper.key_path()
      ]
    else
      [port: port]
    end

    case :cowboy.start_clear(:configurable_test_server, cowboy_opts, %{env: %{dispatch: dispatch}}) do
      {:ok, cowboy_ref} ->
        # Get actual port if 0 was specified
        actual_port = :ranch.get_port(cowboy_ref)
        
        # Register globally
        Registry.register(:configurable_servers, actual_port, self())
        
        state = %__MODULE__{
          port: actual_port,
          cowboy_ref: cowboy_ref,
          behavior: config.behavior,
          protocols: config.protocols,
          tls: config.tls
        }
        
        Logger.info("ConfigurableTestServer started on port #{actual_port}")
        {:ok, state}
      
      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_call(:get_port, _from, state) do
    {:reply, {:ok, state.port}, state}
  end

  def handle_call({:configure_behavior, behavior}, _from, state) do
    new_behavior = Map.merge(state.behavior, behavior)
    new_state = %{state | behavior: new_behavior}
    Logger.debug("Updated server behavior: #{inspect(new_behavior)}")
    {:reply, :ok, new_state}
  end

  def handle_call({:inject_error, error_type}, _from, state) do
    handle_error_injection(error_type, state)
    {:reply, :ok, state}
  end

  def handle_call(:get_stats, _from, state) do
    stats = %{
      port: state.port,
      connections: map_size(state.connections),
      message_count: state.message_count,
      behavior: state.behavior
    }
    {:reply, stats, state}
  end

  @impl true
  def handle_info({:connection_established, conn_id, pid}, state) do
    new_connections = Map.put(state.connections, conn_id, pid)
    new_state = %{state | connections: new_connections}
    Logger.debug("Connection established: #{conn_id}")
    {:noreply, new_state}
  end

  def handle_info({:connection_terminated, conn_id}, state) do
    new_connections = Map.delete(state.connections, conn_id)
    new_state = %{state | connections: new_connections}
    Logger.debug("Connection terminated: #{conn_id}")
    {:noreply, new_state}
  end

  def handle_info({:message_received, _conn_id, _message}, state) do
    new_state = %{state | message_count: state.message_count + 1}
    {:noreply, new_state}
  end

  @impl true
  def terminate(_reason, state) do
    :cowboy.stop_listener(state.cowboy_ref)
    :ok
  end

  # Private functions

  defp find_server_by_port(port) do
    case Registry.lookup(:configurable_servers, port) do
      [{pid, _}] -> {:ok, pid}
      [] -> :error
    end
  end

  defp handle_error_injection(:disconnect_all, state) do
    Enum.each(state.connections, fn {_conn_id, pid} ->
      if Process.alive?(pid) do
        send(pid, :force_disconnect)
      end
    end)
  end

  defp handle_error_injection(:send_invalid_frame, state) do
    # Send invalid frame to all connections
    Enum.each(state.connections, fn {_conn_id, pid} ->
      if Process.alive?(pid) do
        send(pid, :send_invalid_frame)
      end
    end)
  end

  defp handle_error_injection(:timeout_responses, state) do
    # Set behavior to never respond
    new_behavior = Map.put(state.behavior, :latency, :infinity)
    %{state | behavior: new_behavior}
  end

  defp handle_error_injection(:send_large_payload, state) do
    # Send extremely large message
    large_message = String.duplicate("x", 100_000_000)  # 100MB
    Enum.each(state.connections, fn {_conn_id, pid} ->
      if Process.alive?(pid) do
        send(pid, {:send_message, large_message})
      end
    end)
  end

  # Custom WebSocket handler with configurable behavior
  defmodule ConfigurableWebSockHandler do
    @behaviour WebSock

    def init(%{server_pid: server_pid}) do
      conn_id = make_ref()
      send(server_pid, {:connection_established, conn_id, self()})
      
      {:ok, %{
        server_pid: server_pid,
        conn_id: conn_id,
        timeout_ref: nil
      }}
    end

    def handle_in({message, [opcode: :text]}, state) when is_binary(message) do
      send(state.server_pid, {:message_received, state.conn_id, message})
      
      # Get current behavior from server
      {:ok, stats} = GenServer.call(state.server_pid, :get_stats)
      behavior = stats.behavior
      
      response = apply_behavior(message, behavior)
      
      case response do
        :no_response ->
          {:ok, state}
        
        {:delayed_response, delay, resp_message} ->
          timeout_ref = Process.send_after(self(), {:delayed_send, resp_message}, delay)
          {:ok, %{state | timeout_ref: timeout_ref}}
        
        resp_message ->
          {:reply, :ok, {:text, resp_message}, state}
      end
    end

    def handle_in({_message, _opts}, state) do
      {:ok, state}
    end

    def handle_info({:delayed_send, message}, state) do
      {:reply, :ok, {:text, message}, %{state | timeout_ref: nil}}
    end

    def handle_info(:force_disconnect, state) do
      {:stop, :normal, state}
    end

    def handle_info(:send_invalid_frame, state) do
      # This would require low-level frame manipulation
      # For now, just send a malformed JSON
      {:reply, :ok, {:text, "{invalid json"}, state}
    end

    def handle_info({:send_message, message}, state) do
      {:reply, :ok, {:text, message}, state}
    end

    def handle_info(_message, state) do
      {:ok, state}
    end

    def terminate(_reason, state) do
      send(state.server_pid, {:connection_terminated, state.conn_id})
      :ok
    end

    # Apply configured behavior to messages
    defp apply_behavior(message, behavior) do
      # Simulate random disconnection
      if :rand.uniform() < behavior.disconnect_rate do
        Process.exit(self(), :normal)
      end
      
      # Simulate random errors
      if :rand.uniform() < behavior.error_rate do
        "{\"error\": \"simulated_error\"}"
      else
        response = echo_response(message)
        
        # Apply message corruption
        response = if behavior.message_corruption and :rand.uniform() < 0.1 do
          corrupt_message(response)
        else
          response
        end
        
        # Apply latency
        case behavior.latency do
          0 -> response
          :infinity -> :no_response
          delay -> {:delayed_response, delay, response}
        end
      end
    end
    
    defp echo_response(message) do
      "{\"echo\": #{inspect(message)}}"
    end
    
    defp corrupt_message(message) do
      # Randomly corrupt some characters
      message
      |> String.graphemes()
      |> Enum.map(fn char ->
        if :rand.uniform() < 0.1, do: "?", else: char
      end)
      |> Enum.join()
    end
  end
end