defmodule WebsockexNova.Gun.ConnectionManager do
  @moduledoc """
  Manages the WebSocket connection lifecycle using a state machine approach.

  This module is responsible for:
  1. Tracking connection state through well-defined state transitions
  2. Managing reconnection attempts with configurable backoff strategies
  3. Enforcing retry limits and connection policies
  4. Handling various failure scenarios

  The connection lifecycle follows this state machine:

  ```
                   ┌─────────────────┐
                   │                 │
                   ▼                 │
  ┌──────────┐     ┌──────────────┐     ┌──────────────┐     ┌────────────────┐
  │          │     │              │     │              │     │                │
  │ INITIAL  ├────►│  CONNECTING  ├────►│  CONNECTED   ├────►│  WEBSOCKET     │
  │          │     │              │     │              │     │  CONNECTED     │
  └──────────┘     └──────────────┘     └──────────────┘     └────────────────┘
                     │                   │                     │
                     │                   │                     │
                     │                   │                     │
                     ▼                   ▼                     ▼
              ┌────────────┐     ┌────────────┐     ┌─────────────────┐
              │            │     │            │     │                 │
              │ RECONNECT  │◄────┤ DISCONNECTED◄────┤ WS DISCONNECTED │
              │            │     │            │     │                 │
              └────────────┘     └────────────┘     └─────────────────┘
                     │
                     │
                     ▼
              ┌────────────┐
              │            │
              │ ERROR      │
              │            │
              └────────────┘
  ```
  """

  alias WebsockexNova.Gun.ConnectionManager
  alias WebsockexNova.Gun.ConnectionState

  require Logger

  # Define all possible connection states for reference
  # @connection_states [
  #   # Initial state before connection attempt
  #   :initialized,
  #   # Connection attempt in progress
  #   :connecting,
  #   # HTTP connection established
  #   :connected,
  #   # WebSocket upgrade successful
  #   :websocket_connected,
  #   # Connection lost/closed
  #   :disconnected,
  #   # Attempting to reconnect
  #   :reconnecting,
  #   # Terminal error state
  #   :error
  # ]

  # Terminal errors that should not trigger reconnection
  @terminal_errors [
    # Connection closed by user
    :closed,
    # Domain does not exist
    :nxdomain,
    # Connection refused
    :econnrefused,
    # Generic fatal error
    :fatal_error
  ]

  # Valid state transitions map - updating to fix test failures
  @valid_transitions %{
    :initialized => [:connecting, :error],
    :connecting => [:connected, :disconnected, :error],
    :connected => [:websocket_connected, :disconnected, :error],
    :websocket_connected => [:disconnected, :error],
    # Allow direct connecting from disconnected
    :disconnected => [:reconnecting, :connecting, :error],
    # Allow transition back to disconnected
    :reconnecting => [:connecting, :disconnected, :error],
    # Terminal state - no transitions out
    :error => []
  }

  # Map of state transitions to effect functions
  @transition_effects %{
    connected: &ConnectionManager.apply_connected_effects/2,
    disconnected: &ConnectionManager.apply_disconnected_effects/2,
    error: &ConnectionManager.apply_error_effects/2
  }

  @doc """
  Attempts to transition the state machine to a new state.

  ## Parameters

  * `state` - Current connection state
  * `to_state` - Desired new state
  * `params` - Optional parameters for the transition

  ## Returns

  * `{:ok, new_state}` on successful transition
  * `{:error, :invalid_transition}` if the transition is not allowed
  """
  @spec transition_to(ConnectionState.t(), atom(), map()) ::
          {:ok, ConnectionState.t()} | {:error, :invalid_transition}
  def transition_to(state, to_state, params \\ %{}) when is_map(params) do
    if can_transition?(state.status, to_state) do
      Logger.debug("Transitioning from #{state.status} to #{to_state}")

      # Perform any state-specific actions
      new_state =
        state
        |> ConnectionState.update_status(to_state)
        |> apply_transition_effects(to_state, params)

      # Transition successful
      {:ok, new_state}
    else
      Logger.error("Invalid transition from #{state.status} to #{to_state}")

      Logger.debug(
        "Valid transitions from #{state.status} are: #{inspect(Map.get(@valid_transitions, state.status, []))}"
      )

      {:error, :invalid_transition}
    end
  end

  @doc """
  Checks if the connection state can transition to the target state.

  ## Parameters

  * `from_state` - Current state
  * `to_state` - Target state

  ## Returns

  * `true` if the transition is allowed
  * `false` if the transition is not allowed
  """
  @spec can_transition?(atom(), atom()) :: boolean()
  def can_transition?(from_state, to_state) do
    # Special case: any state can transition to error
    if to_state == :error do
      true
    else
      # Otherwise, check valid transitions map
      valid_to_states = Map.get(@valid_transitions, from_state, [])
      Enum.member?(valid_to_states, to_state)
    end
  end

  @doc """
  Handles reconnection logic when a connection is lost.

  ## Parameters

  * `state` - Current connection state

  ## Returns

  * `{:ok, reconnect_after, updated_state}` when reconnection should be attempted
  * `{:error, reason, updated_state}` when reconnection should not be attempted
  """
  @spec handle_reconnection(ConnectionState.t()) ::
          {:ok, non_neg_integer(), ConnectionState.t()}
          | {:error, atom(), ConnectionState.t()}
  def handle_reconnection(%ConnectionState{status: :error} = state) do
    Logger.debug("Not reconnecting: already in error state")
    {:error, :terminal_error, state}
  end

  def handle_reconnection(%ConnectionState{last_error: last_error} = state) do
    if not is_nil(last_error) and terminal_error?(last_error) do
      Logger.debug("Not reconnecting: terminal error detected - #{inspect(last_error)}")
      error_state = ConnectionState.update_status(state, :error)
      {:error, :terminal_error, error_state}
    else
      handle_reconnection_attempts(state)
    end
  end

  defp handle_reconnection_attempts(state) do
    if max_attempts_reached?(state) do
      Logger.debug("Not reconnecting: max attempts reached (#{state.reconnect_attempts}/#{state.options.retry})")
      error_state = ConnectionState.update_status(state, :error)
      {:error, :max_attempts_reached, error_state}
    else
      reconnect_after = calculate_backoff_delay(state)
      Logger.debug("Reconnecting in #{reconnect_after}ms, attempt #{state.reconnect_attempts + 1}")

      updated_state =
        state
        |> ConnectionState.increment_reconnect_attempts()
        |> ConnectionState.update_status(:reconnecting)

      {:ok, reconnect_after, updated_state}
    end
  end

  @doc """
  Schedules a reconnection attempt and executes the provided callback.

  This function centralizes the reconnection scheduling logic by:
  1. Determining if reconnection should be attempted
  2. Setting the appropriate state
  3. Calculating the delay time
  4. Executing the callback function with the delay and attempt number

  ## Parameters

  * `state` - Current connection state
  * `callback` - Function to call with (delay, attempt_number) when reconnection should be attempted

  ## Returns

  * `updated_state` - The new connection state after scheduling (or not scheduling) reconnection
  """
  @spec schedule_reconnection(ConnectionState.t(), (non_neg_integer(), non_neg_integer() -> any())) ::
          ConnectionState.t()
  def schedule_reconnection(state, callback) when is_function(callback, 2) do
    Logger.debug("Scheduling reconnection for state: #{state.status}")

    case handle_reconnection(state) do
      {:ok, reconnect_after, reconnecting_state} ->
        callback.(reconnect_after, reconnecting_state.reconnect_attempts)
        reconnecting_state

      {:error, reason, error_state} ->
        Logger.debug("Not scheduling reconnection: #{inspect(reason)}")
        error_state
    end
  end

  @doc """
  Initiates a connection.

  ## Parameters

  * `state` - Current connection state

  ## Returns

  * `{:ok, updated_state}` on success
  * `{:error, reason, updated_state}` on failure
  """
  @spec initiate_connection(ConnectionState.t()) ::
          {:ok, ConnectionState.t()}
          | {:error, term(), ConnectionState.t()}
  def initiate_connection(state) do
    Logger.debug("Initiating connection from state: #{state.status}")

    case transition_to(state, :connecting) do
      {:ok, new_state} -> {:ok, new_state}
      {:error, reason} -> {:error, reason, state}
    end
  end

  @doc """
  Starts a new connection by transitioning to connecting state and opening a connection.

  This function centralizes the connection establishment process, handling both the
  state transition and the actual connection attempt.

  ## Parameters

  * `state` - Current connection state

  ## Returns

  * `{:ok, updated_state}` on success
  * `{:error, reason, updated_state}` on failure
  """
  @spec start_connection(ConnectionState.t()) ::
          {:ok, ConnectionState.t()} | {:error, term(), ConnectionState.t()}
  def start_connection(state) do
    Logger.debug("Starting connection to #{state.host}:#{state.port} from state: #{state.status}")

    with {:ok, connecting_state} <- transition_to(state, :connecting),
         {:ok, gun_pid, monitor_ref} <- open_connection(connecting_state) do
      Logger.debug("Connection successfully established with Gun pid: #{inspect(gun_pid)}")

      updated_state =
        connecting_state
        |> ConnectionState.update_gun_pid(gun_pid)
        |> update_gun_monitor_ref(monitor_ref)

      {:ok, updated_state}
    else
      {:error, reason} ->
        Logger.error("Connection failed: #{inspect(reason)}")
        {:ok, error_state} = transition_to(state, :error, %{reason: reason})
        {:error, reason, error_state}
    end
  end

  # Private functions

  @doc """
  Determines if an error should be considered terminal (non-recoverable).

  Terminal errors will prevent reconnection attempts, while non-terminal errors
  may allow reconnection based on the retry policy.

  ## Returns

  * `true` if the error is terminal
  * `false` if the error is transient and reconnection can be attempted
  """
  @spec terminal_error?(term()) :: boolean()
  def terminal_error?(nil), do: false

  def terminal_error?(error) when is_atom(error) do
    Enum.member?(@terminal_errors, error)
  end

  # Handle complex error structures (tuples, maps)
  def terminal_error?({:error, reason}) when is_atom(reason) do
    Enum.member?(@terminal_errors, reason)
  end

  def terminal_error?(%{reason: reason}) when is_atom(reason) do
    Enum.member?(@terminal_errors, reason)
  end

  def terminal_error?(_), do: false

  # Apply side effects when transitioning to specific states
  defp apply_transition_effects(state, to_state, params) do
    case Map.get(@transition_effects, to_state) do
      nil -> state
      effect_fun -> effect_fun.(state, params)
    end
  end

  # Effect function for connected state
  @doc false
  def apply_connected_effects(state, _params) do
    Logger.debug("Applying connected effects: Resetting reconnect attempts")
    # Reset reconnection attempts when successful connection is established
    ConnectionState.reset_reconnect_attempts(state)
  end

  # Effect function for disconnected state
  @doc false
  def apply_disconnected_effects(state, params) do
    # Record the disconnect reason if provided
    if Map.has_key?(params, :reason) do
      Logger.debug("Applying disconnected effects: Recording error reason - #{inspect(params.reason)}")

      ConnectionState.record_error(state, params.reason)
    else
      Logger.debug("Applying disconnected effects: No reason provided")
      state
    end
  end

  # Effect function for error state
  @doc false
  def apply_error_effects(state, params) do
    # Record the error reason if provided
    if Map.has_key?(params, :reason) do
      Logger.debug("Applying error effects: Recording error reason - #{inspect(params.reason)}")
      ConnectionState.record_error(state, params.reason)
    else
      Logger.debug("Applying error effects: No reason provided")
      state
    end
  end

  # Establishes a connection to the server
  defp open_connection(state) do
    gun_opts = build_gun_options(state)
    Logger.info("Opening Gun connection to #{state.host}:#{state.port}")
    host_charlist = String.to_charlist(state.host)

    with {:ok, pid} <- gun_open(host_charlist, state.port, gun_opts),
         {:ok, gun_monitor_ref} <- monitor_gun_process(pid),
         {:ok, protocol} <- await_gun_up(pid, gun_monitor_ref),
         :ok <- set_gun_owner(pid),
         :ok <- verify_gun_owner(pid) do
      send_gun_up_message(pid, protocol)
      {:ok, pid, gun_monitor_ref}
    else
      {:error, reason} ->
        Logger.error("Gun connection failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp build_gun_options(state) do
    base_opts =
      %{}
      |> Map.put(:transport, state.options.transport)
      |> Map.put(:protocols, state.options.protocols)
      |> Map.put(:retry, state.options.retry)

    cond do
      Enum.empty?(state.options.transport_opts) ->
        base_opts

      state.options.transport == :tls ->
        Map.put(base_opts, :tls_opts, state.options.transport_opts)

      true ->
        Map.put(base_opts, :transport_opts, state.options.transport_opts)
    end
  end

  defp gun_open(host, port, opts) do
    case :gun.open(host, port, opts) do
      {:ok, pid} ->
        {:ok, pid}

      {:error, reason} ->
        Logger.error("Gun open failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp monitor_gun_process(pid) do
    gun_monitor_ref = Process.monitor(pid)
    Logger.debug("Created monitor for Gun process: #{inspect(gun_monitor_ref)}")
    {:ok, gun_monitor_ref}
  end

  defp await_gun_up(pid, monitor_ref) do
    case :gun.await_up(pid, 5000, monitor_ref) do
      {:ok, protocol} ->
        Logger.info("Gun connection established with protocol: #{protocol}")
        {:ok, protocol}

      {:error, reason} ->
        Process.demonitor(monitor_ref)
        :gun.close(pid)
        Logger.error("Gun connection failed to come up: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp set_gun_owner(pid) do
    case :gun.set_owner(pid, self()) do
      :ok ->
        Logger.debug("Successfully set Gun connection owner to: #{inspect(self())}")
        :ok

        # dialyzer says this is unreachable
        # other ->
        #   Logger.debug("Failed to set Gun connection owner: #{inspect(other)}")
        #   {:error, :set_owner_failed}
    end
  end

  defp verify_gun_owner(pid) do
    case :gun.info(pid) do
      %{owner: owner} when owner == self() ->
        Logger.debug("Gun connection owner is correctly set to: #{inspect(owner)}")
        :ok

      _ ->
        Logger.debug("Gun connection owner info not available or not matching self()")
        :ok
    end
  end

  defp send_gun_up_message(pid, protocol) do
    send(self(), {:gun_up, pid, protocol})
    :ok
  end

  # Helper to update the gun monitor reference in the connection state
  defp update_gun_monitor_ref(state, monitor_ref) do
    ConnectionState.update_gun_monitor_ref(state, monitor_ref)
  end

  # Calculate backoff delay based on reconnection attempts
  #
  # This function uses the WebsockexNova.Transport.Reconnection module to implement
  # different backoff strategies:
  # - `:linear` - Fixed delay regardless of attempt number
  # - `:exponential` - Delay grows as 2^n with a random jitter
  # - `:jittered` - Linear increase with random jitter
  #
  # The jitter is added to prevent the "thundering herd" problem where multiple clients
  # attempt to reconnect at exactly the same time following a server outage.
  defp calculate_backoff_delay(state) do
    alias WebsockexNova.Transport.Reconnection

    # Get backoff configuration from options
    backoff_type = Map.get(state.options, :backoff_type, :linear)

    # Map the connection options to reconnection strategy options
    strategy_opts =
      case backoff_type do
        :linear ->
          [
            delay: Map.get(state.options, :base_backoff, 1000),
            max_retries: Map.get(state.options, :retry, 5)
          ]

        :exponential ->
          [
            initial_delay: Map.get(state.options, :base_backoff, 1000),
            max_delay: Map.get(state.options, :max_backoff, 30_000),
            jitter_factor: Map.get(state.options, :jitter_factor, 0.1),
            max_retries: Map.get(state.options, :retry, 5)
          ]

        :jittered ->
          [
            base_delay: Map.get(state.options, :base_backoff, 1000),
            jitter_factor: Map.get(state.options, :jitter_factor, 0.2),
            max_retries: Map.get(state.options, :retry, 5)
          ]
      end

    # Get the appropriate strategy and calculate delay
    strategy = Reconnection.get_strategy(backoff_type, strategy_opts)
    Reconnection.calculate_delay(strategy, state.reconnect_attempts + 1)
  end

  # Check if max reconnection attempts have been reached
  defp max_attempts_reached?(%{options: %{retry: :infinity}}), do: false

  defp max_attempts_reached?(state) do
    max_attempts = state.options.retry
    state.reconnect_attempts >= max_attempts
  end
end
