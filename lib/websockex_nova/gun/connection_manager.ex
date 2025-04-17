defmodule WebSockexNova.Gun.ConnectionManager do
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

  require Logger
  alias WebSockexNova.Gun.ConnectionState

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
    connected: &WebSockexNova.Gun.ConnectionManager.apply_connected_effects/2,
    disconnected: &WebSockexNova.Gun.ConnectionManager.apply_disconnected_effects/2,
    error: &WebSockexNova.Gun.ConnectionManager.apply_error_effects/2
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
  def handle_reconnection(state) do
    cond do
      # Don't reconnect if in error state
      state.status == :error ->
        {:error, :terminal_error, state}

      # Don't reconnect if the disconnect reason is terminal
      terminal_error?(state.last_error) ->
        error_state = ConnectionState.update_status(state, :error)
        {:error, :terminal_error, error_state}

      # Don't reconnect if max attempts reached
      max_attempts_reached?(state) ->
        error_state = ConnectionState.update_status(state, :error)
        {:error, :max_attempts_reached, error_state}

      # Otherwise, reconnect
      true ->
        # Calculate backoff delay
        reconnect_after = calculate_backoff_delay(state)

        # Increment reconnect attempts and set state to reconnecting
        updated_state =
          state
          |> ConnectionState.increment_reconnect_attempts()
          |> ConnectionState.update_status(:reconnecting)

        {:ok, reconnect_after, updated_state}
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
    # First transition to connecting state
    case transition_to(state, :connecting) do
      {:ok, connecting_state} ->
        # Then actually open the connection
        case open_connection(connecting_state) do
          {:ok, gun_pid} ->
            # Update the state with the new gun_pid
            {:ok, ConnectionState.update_gun_pid(connecting_state, gun_pid)}

          {:error, reason} ->
            # Transition to error state on failure
            {:ok, error_state} =
              transition_to(connecting_state, :error, %{reason: reason})

            {:error, reason, error_state}
        end

      {:error, reason} ->
        {:error, reason, state}
    end
  end

  # Private functions

  @doc """
  Checks if an error is considered terminal and should prevent reconnection attempts.

  Terminal errors are severe issues that indicate reconnection attempts would likely fail
  or are not appropriate (e.g., authentication failures, connection refused).

  ## Parameters

  * `error` - The error to check

  ## Returns

  * `true` if the error is terminal
  * `false` if the error is transient and reconnection can be attempted
  """
  @spec terminal_error?(term()) :: boolean()
  def terminal_error?(error), do: is_terminal_error?(error)

  # Check if an error is considered terminal
  defp is_terminal_error?(nil), do: false

  defp is_terminal_error?(error) when is_atom(error) do
    Enum.member?(@terminal_errors, error)
  end

  # Handle complex error structures (tuples, maps)
  defp is_terminal_error?({:error, reason}) when is_atom(reason) do
    Enum.member?(@terminal_errors, reason)
  end

  defp is_terminal_error?(%{reason: reason}) when is_atom(reason) do
    Enum.member?(@terminal_errors, reason)
  end

  defp is_terminal_error?(_), do: false

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
    # Reset reconnection attempts when successful connection is established
    ConnectionState.reset_reconnect_attempts(state)
  end

  # Effect function for disconnected state
  @doc false
  def apply_disconnected_effects(state, params) do
    # Record the disconnect reason if provided
    if Map.has_key?(params, :reason) do
      ConnectionState.record_error(state, params.reason)
    else
      state
    end
  end

  # Effect function for error state
  @doc false
  def apply_error_effects(state, params) do
    # Record the error reason if provided
    if Map.has_key?(params, :reason) do
      ConnectionState.record_error(state, params.reason)
    else
      state
    end
  end

  # Establishes a connection to the server
  defp open_connection(state) do
    # Convert options from map to keyword list for gun
    gun_opts =
      %{}
      |> Map.put(:transport, state.options.transport)
      |> Map.put(:protocols, state.options.protocols)
      |> Map.put(:retry, state.options.retry)

    # Add transport_opts only if they're not empty
    gun_opts =
      if Enum.empty?(state.options.transport_opts) do
        gun_opts
      else
        Map.put(gun_opts, :transport_opts, state.options.transport_opts)
      end

    # Try to open Gun connection
    host_charlist = String.to_charlist(state.host)

    case :gun.open(host_charlist, state.port, gun_opts) do
      {:ok, pid} ->
        Logger.debug("Gun connection opened to #{state.host}:#{state.port}")

        # Wait for connection to be established
        case :gun.await_up(pid, 5000) do
          {:ok, _protocol} ->
            {:ok, pid}

          {:error, reason} ->
            :gun.close(pid)
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Calculate backoff delay based on reconnection attempts
  #
  # This function implements three backoff strategies:
  # - `:linear` - Fixed delay regardless of attempt number (fastest recovery, no penalty for repeated failures)
  # - `:exponential` - Delay grows as 2^n with a random jitter (standard backoff with retry penalty)
  # - `:jittered` - Linear increase with random jitter (balanced approach)
  #
  # The jitter is added to prevent the "thundering herd" problem where multiple clients
  # attempt to reconnect at exactly the same time following a server outage.
  defp calculate_backoff_delay(state) do
    base_backoff = Map.get(state.options, :base_backoff, 1000)
    backoff_type = Map.get(state.options, :backoff_type, :linear)

    case backoff_type do
      :linear ->
        base_backoff

      :exponential ->
        # Use a 2^n exponential backoff with a bit of jitter
        delay = base_backoff * :math.pow(2, state.reconnect_attempts)
        jitter = delay * 0.1 * :rand.uniform()
        trunc(delay + jitter)

      :jittered ->
        # Linear delay with jitter
        jitter = base_backoff * 0.2 * :rand.uniform()
        trunc(base_backoff * state.reconnect_attempts + jitter)
    end
  end

  # Check if max reconnection attempts have been reached
  defp max_attempts_reached?(%{options: %{retry: :infinity}}), do: false

  defp max_attempts_reached?(state) do
    max_attempts = state.options.retry
    state.reconnect_attempts >= max_attempts
  end
end
