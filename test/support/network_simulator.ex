defmodule WebsockexNew.NetworkSimulator do
  @moduledoc """
  Simulates various network conditions for realistic WebSocket testing.
  
  Provides utilities to:
  - Simulate slow connections and high latency
  - Inject packet loss and connection interruptions
  - Test timeout scenarios
  - Simulate intermittent connectivity
  - Control connection quality dynamically
  """

  use GenServer
  require Logger

  @type condition :: :slow_connection | :packet_loss | :timeout | :intermittent | :high_latency
  
  @type simulation_config :: %{
    latency_ms: non_neg_integer(),      # Additional latency to inject
    packet_loss_rate: float(),          # 0.0 to 1.0
    disconnect_interval: pos_integer(), # Disconnect every N seconds
    timeout_rate: float(),              # Rate of timeout failures
    jitter_ms: non_neg_integer()        # Random latency variation
  }

  defstruct [
    :target_pid,
    :config,
    :timer_ref,
    :original_gun_opts,
    active: false
  ]

  @default_configs %{
    slow_connection: %{
      latency_ms: 2000,
      packet_loss_rate: 0.0,
      disconnect_interval: 0,
      timeout_rate: 0.0,
      jitter_ms: 500
    },
    
    packet_loss: %{
      latency_ms: 100,
      packet_loss_rate: 0.15,
      disconnect_interval: 0,
      timeout_rate: 0.0,
      jitter_ms: 50
    },
    
    timeout: %{
      latency_ms: 5000,
      packet_loss_rate: 0.0,
      disconnect_interval: 0,
      timeout_rate: 0.3,
      jitter_ms: 1000
    },
    
    intermittent: %{
      latency_ms: 500,
      packet_loss_rate: 0.05,
      disconnect_interval: 15,
      timeout_rate: 0.1,
      jitter_ms: 200
    },
    
    high_latency: %{
      latency_ms: 1000,
      packet_loss_rate: 0.02,
      disconnect_interval: 0,
      timeout_rate: 0.0,
      jitter_ms: 300
    }
  }

  # Public API

  @doc """
  Simulates a network condition for a specific connection process.
  
  ## Options
  - `:duration` - How long to maintain the condition (default: indefinite)
  - `:custom_config` - Override default configuration for the condition
  
  ## Examples
  
      # Simulate slow connection for 30 seconds
      NetworkSimulator.simulate_condition(client_pid, :slow_connection, duration: 30_000)
      
      # Custom packet loss configuration
      NetworkSimulator.simulate_condition(client_pid, :packet_loss, 
        custom_config: %{packet_loss_rate: 0.25})
  """
  @spec simulate_condition(pid(), condition(), keyword()) :: {:ok, pid()} | {:error, term()}
  def simulate_condition(connection_pid, condition, opts \\ []) do
    custom_config = Keyword.get(opts, :custom_config, %{})
    duration = Keyword.get(opts, :duration, :infinity)
    
    base_config = @default_configs[condition] || @default_configs[:slow_connection]
    config = Map.merge(base_config, custom_config)
    
    case GenServer.start_link(__MODULE__, {connection_pid, config}) do
      {:ok, simulator_pid} ->
        if duration != :infinity do
          Process.send_after(simulator_pid, :stop_simulation, duration)
        end
        {:ok, simulator_pid}
      
      error ->
        error
    end
  end

  @doc """
  Restores normal network conditions for a connection.
  """
  @spec restore_normal_conditions(pid()) :: :ok
  def restore_normal_conditions(connection_pid) do
    # Find and stop any active simulators for this connection
    case find_simulator_for_connection(connection_pid) do
      {:ok, simulator_pid} ->
        GenServer.stop(simulator_pid)
        :ok
      
      :error ->
        :ok
    end
  end

  @doc """
  Gets current simulation status for a connection.
  """
  @spec get_simulation_status(pid()) :: {:ok, map()} | {:error, :not_found}
  def get_simulation_status(connection_pid) do
    case find_simulator_for_connection(connection_pid) do
      {:ok, simulator_pid} ->
        status = GenServer.call(simulator_pid, :get_status)
        {:ok, status}
      
      :error ->
        {:error, :not_found}
    end
  end

  @doc """
  Updates simulation configuration at runtime.
  """
  @spec update_simulation(pid(), simulation_config()) :: :ok | {:error, :not_found}
  def update_simulation(connection_pid, new_config) do
    case find_simulator_for_connection(connection_pid) do
      {:ok, simulator_pid} ->
        GenServer.call(simulator_pid, {:update_config, new_config})
        :ok
      
      :error ->
        {:error, :not_found}
    end
  end

  @doc """
  Injects a one-time network event.
  
  Events:
  - `:disconnect` - Force disconnect the connection
  - `:delay` - Add extra delay to next message
  - `:corrupt` - Corrupt the next message
  - `:timeout` - Cause next operation to timeout
  """
  @spec inject_network_event(pid(), atom(), keyword()) :: :ok | {:error, :not_found}
  def inject_network_event(connection_pid, event, opts \\ []) do
    case find_simulator_for_connection(connection_pid) do
      {:ok, simulator_pid} ->
        GenServer.call(simulator_pid, {:inject_event, event, opts})
        :ok
      
      :error ->
        {:error, :not_found}
    end
  end

  # GenServer implementation

  @impl true
  def init({target_pid, config}) do
    # Register this simulator globally for lookup
    Registry.register(:network_simulators, target_pid, self())
    
    # Set up monitoring of target process
    Process.monitor(target_pid)
    
    state = %__MODULE__{
      target_pid: target_pid,
      config: config,
      active: true
    }
    
    # Start applying network simulation
    schedule_next_disruption(state)
    
    Logger.debug("NetworkSimulator started for #{inspect(target_pid)} with config: #{inspect(config)}")
    {:ok, state}
  end

  @impl true
  def handle_call(:get_status, _from, state) do
    status = %{
      target_pid: state.target_pid,
      config: state.config,
      active: state.active
    }
    {:reply, status, state}
  end

  def handle_call({:update_config, new_config}, _from, state) do
    updated_config = Map.merge(state.config, new_config)
    new_state = %{state | config: updated_config}
    Logger.debug("Updated simulation config: #{inspect(updated_config)}")
    {:reply, :ok, new_state}
  end

  def handle_call({:inject_event, event, opts}, _from, state) do
    handle_network_event(event, opts, state)
    {:reply, :ok, state}
  end

  @impl true
  def handle_info(:apply_disruption, state) do
    if state.active and Process.alive?(state.target_pid) do
      apply_network_disruption(state)
      schedule_next_disruption(state)
    end
    {:noreply, state}
  end

  def handle_info(:stop_simulation, state) do
    Logger.debug("Stopping network simulation for #{inspect(state.target_pid)}")
    {:stop, :normal, %{state | active: false}}
  end

  def handle_info({:DOWN, _ref, :process, pid, _reason}, %{target_pid: pid} = state) do
    Logger.debug("Target process #{inspect(pid)} terminated, stopping simulation")
    {:stop, :normal, state}
  end

  def handle_info(_message, state) do
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, _state) do
    :ok
  end

  # Private functions

  defp find_simulator_for_connection(connection_pid) do
    case Registry.lookup(:network_simulators, connection_pid) do
      [{simulator_pid, _}] -> {:ok, simulator_pid}
      [] -> :error
    end
  end

  defp schedule_next_disruption(state) do
    # Calculate next disruption time based on configuration
    base_interval = case state.config.disconnect_interval do
      0 -> 5000  # Default 5 second check interval
      interval -> interval * 1000
    end
    
    # Add jitter
    jitter = :rand.uniform(state.config.jitter_ms)
    next_interval = base_interval + jitter
    
    timer_ref = Process.send_after(self(), :apply_disruption, next_interval)
    %{state | timer_ref: timer_ref}
  end

  defp apply_network_disruption(state) do
    config = state.config
    
    # Apply packet loss
    if :rand.uniform() < config.packet_loss_rate do
      simulate_packet_loss(state.target_pid)
    end
    
    # Apply timeout
    if :rand.uniform() < config.timeout_rate do
      simulate_timeout(state.target_pid)
    end
    
    # Apply latency
    if config.latency_ms > 0 do
      actual_latency = config.latency_ms + :rand.uniform(config.jitter_ms)
      simulate_latency(state.target_pid, actual_latency)
    end
    
    # Apply intermittent disconnection
    if config.disconnect_interval > 0 do
      current_time = System.monotonic_time(:second)
      if rem(current_time, config.disconnect_interval) == 0 do
        simulate_disconnection(state.target_pid)
      end
    end
  end

  defp simulate_packet_loss(target_pid) do
    Logger.debug("Simulating packet loss for #{inspect(target_pid)}")
    
    # This is a simplified simulation - in a real implementation,
    # we would need to intercept and drop actual network packets
    # For now, we can simulate by introducing delays or errors
    
    # Send a message to the process that might cause it to think
    # a message was lost
    if Process.alive?(target_pid) do
      send(target_pid, {:network_simulation, :packet_lost})
    end
  end

  defp simulate_timeout(target_pid) do
    Logger.debug("Simulating timeout for #{inspect(target_pid)}")
    
    # Simulate a timeout by sending a timeout message
    if Process.alive?(target_pid) do
      send(target_pid, {:network_simulation, :timeout})
    end
  end

  defp simulate_latency(target_pid, latency_ms) do
    Logger.debug("Simulating #{latency_ms}ms latency for #{inspect(target_pid)}")
    
    # Introduce artificial delay
    spawn(fn ->
      Process.sleep(latency_ms)
      if Process.alive?(target_pid) do
        send(target_pid, {:network_simulation, :latency_applied, latency_ms})
      end
    end)
  end

  defp simulate_disconnection(target_pid) do
    Logger.debug("Simulating disconnection for #{inspect(target_pid)}")
    
    # Send disconnection signal
    if Process.alive?(target_pid) do
      send(target_pid, {:network_simulation, :force_disconnect})
    end
  end

  defp handle_network_event(:disconnect, _opts, state) do
    simulate_disconnection(state.target_pid)
  end

  defp handle_network_event(:delay, opts, state) do
    delay_ms = Keyword.get(opts, :delay, 1000)
    simulate_latency(state.target_pid, delay_ms)
  end

  defp handle_network_event(:corrupt, _opts, state) do
    if Process.alive?(state.target_pid) do
      send(state.target_pid, {:network_simulation, :corrupt_next_message})
    end
  end

  defp handle_network_event(:timeout, _opts, state) do
    simulate_timeout(state.target_pid)
  end

  defp handle_network_event(unknown_event, _opts, _state) do
    Logger.warning("Unknown network event: #{unknown_event}")
  end
end