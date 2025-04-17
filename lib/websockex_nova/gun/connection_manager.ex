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
      is_terminal_error?(state.last_error) ->
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

  # Private functions

  # Apply side effects when transitioning to specific states
  defp apply_transition_effects(state, :connected, _params) do
    # Reset reconnection attempts when successful connection is established
    ConnectionState.reset_reconnect_attempts(state)
  end

  defp apply_transition_effects(state, :disconnected, params) do
    # Record the disconnect reason if provided
    if Map.has_key?(params, :reason) do
      ConnectionState.record_error(state, params.reason)
    else
      state
    end
  end

  defp apply_transition_effects(state, :error, params) do
    # Record the error reason if provided
    if Map.has_key?(params, :reason) do
      ConnectionState.record_error(state, params.reason)
    else
      state
    end
  end

  defp apply_transition_effects(state, _to_state, _params), do: state

  # Check if an error is considered terminal
  defp is_terminal_error?(nil), do: false

  defp is_terminal_error?(error) when is_atom(error) do
    Enum.member?(@terminal_errors, error)
  end

  defp is_terminal_error?(_), do: false

  # Check if max reconnection attempts have been reached
  defp max_attempts_reached?(%{options: %{retry: :infinity}}), do: false

  defp max_attempts_reached?(state) do
    max_attempts = state.options.retry
    state.reconnect_attempts >= max_attempts
  end

  # Calculate backoff delay based on reconnection attempts
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
end
