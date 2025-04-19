defmodule WebsockexNova.Auth.AuthFlow do
  @moduledoc """
  Manages authentication flows for WebSocket connections.

  The `AuthFlow` module provides standardized functions for:

  - Initial authentication when a connection is established
  - Reauthentication when tokens expire or authentication fails
  - Processing authentication responses from the server
  - Determining when reauthentication is needed

  ## Authentication Flow

  1. When a connection is established, `authenticate/2` is called
  2. The AuthHandler generates authentication data via `generate_auth_data/1`
  3. Authentication data is sent to the server
  4. Server responds with success or error
  5. `handle_auth_response/2` processes the response and updates state
  6. During connection, `check_reauthentication/2` checks if auth renewal is needed

  ## Example Usage

  ```elixir
  # During initial connection
  {:ok, state} = AuthFlow.authenticate(state, &send_frame_fn/4)

  # When a message is received that might be an auth response
  {:ok, updated_state} = AuthFlow.handle_auth_response(message, state)

  # Periodically check if reauthentication is needed
  case AuthFlow.check_reauthentication(state, &send_frame_fn/4) do
    {:ok, state} -> state # No reauthentication needed
    {:reauthenticated, state} -> state # Reauthentication initiated
  end
  ```
  """

  alias WebsockexNova.Helpers.StateHelpers

  require Logger

  @doc """
  Initiates the authentication process using the configured AuthHandler.

  This function:
  1. Retrieves the AuthHandler from the state
  2. Calls generate_auth_data/1 to get authentication data
  3. Sends the authentication data to the server
  4. Returns the updated state

  The actual authentication response will be processed later via handle_auth_response/2.

  ## Parameters

  - `state`: The current state containing authentication handler configuration
  - `send_frame_fn`: Function to send frames to the WebSocket server,
    with signature `(conn, frame_type, frame_data, stream_ref) -> :ok | {:error, reason}`

  ## Returns

  - `{:ok, updated_state}`: Authentication data sent successfully
  - `{:error, reason, updated_state}`: Error generating authentication data
  """
  @spec authenticate(map(), function()) ::
          {:ok, map()} | {:error, atom() | String.t(), map()}
  def authenticate(state, send_frame_fn) do
    with {:ok, auth_handler, auth_state} <- fetch_auth_handler(state),
         {:ok, auth_data, updated_auth_state} <- auth_handler.generate_auth_data(auth_state),
         state = StateHelpers.update_auth_handler_state(state, updated_auth_state),
         :ok <- send_auth_data(auth_data, state, send_frame_fn) do
      {:ok, state}
    else
      {:error, reason, updated_auth_state} ->
        state = StateHelpers.update_auth_handler_state(state, updated_auth_state)
        {:error, reason, state}

      {:error, reason} ->
        Logger.error("Authentication failed: #{inspect(reason)}")
        {:error, reason, state}
    end
  end

  @doc """
  Handles an authentication response from the server.

  This function:
  1. Retrieves the AuthHandler from the state
  2. Calls handle_auth_response/2 to process the authentication response
  3. Updates the state with the result

  ## Parameters

  - `response`: The response message received from the server
  - `state`: The current state containing authentication handler configuration

  ## Returns

  - `{:ok, updated_state}`: Authentication successful or message processed
  - `{:error, reason, updated_state}`: Authentication failed
  """
  @spec handle_auth_response(map(), map()) ::
          {:ok, map()} | {:error, atom() | String.t(), map()}
  def handle_auth_response(response, state) do
    case fetch_auth_handler(state) do
      {:ok, auth_handler, auth_state} ->
        case auth_handler.handle_auth_response(response, auth_state) do
          {:ok, updated_auth_state} ->
            {:ok, StateHelpers.update_auth_handler_state(state, updated_auth_state)}

          {:error, reason, updated_auth_state} ->
            {:error, reason, StateHelpers.update_auth_handler_state(state, updated_auth_state)}
        end

      _error ->
        {:ok, state}
    end
  end

  @doc """
  Checks if reauthentication is needed and initiates the process if necessary.

  This function:
  1. Retrieves the AuthHandler from the state
  2. Calls needs_reauthentication?/1 to check if reauthentication is needed
  3. If needed, initiates the authentication process

  ## Parameters

  - `state`: The current state containing authentication handler configuration
  - `send_frame_fn`: Function to send frames to the WebSocket server,
    with signature `(conn, frame_type, frame_data, stream_ref) -> :ok | {:error, reason}`

  ## Returns

  - `{:ok, state}`: No reauthentication needed
  - `{:reauthenticated, state}`: Reauthentication initiated
  - `{:error, reason, state}`: Error during reauthentication
  """
  @spec check_reauthentication(map(), function()) ::
          {:ok, map()} | {:reauthenticated, map()} | {:error, atom() | String.t(), map()}
  def check_reauthentication(state, send_frame_fn) do
    with {:ok, auth_handler, auth_state} <- fetch_auth_handler(state),
         true <- auth_handler.needs_reauthentication?(auth_state),
         {:ok, auth_data, updated_auth_state} <- auth_handler.generate_auth_data(auth_state),
         state = StateHelpers.update_auth_handler_state(state, updated_auth_state),
         :ok <- send_auth_data(auth_data, state, send_frame_fn) do
      {:reauthenticated, state}
    else
      false ->
        {:ok, state}

      {:error, reason, updated_auth_state} ->
        state = StateHelpers.update_auth_handler_state(state, updated_auth_state)
        {:error, reason, state}

      {:error, reason} ->
        Logger.error("Reauthentication failed: #{inspect(reason)}")
        {:error, reason, state}
    end
  end

  # Private helper functions

  defp fetch_auth_handler(%{handlers: %{auth_handler: mod} = handlers}) when is_atom(mod) do
    case Map.fetch(handlers, {:auth_handler, :state}) do
      {:ok, st} when not is_nil(st) -> {:ok, mod, st}
      _ -> {:error, :no_auth_handler}
    end
  end

  defp fetch_auth_handler(_), do: {:error, :no_auth_handler}

  defp send_auth_data(auth_data, _state, send_frame_fn) do
    # Encode auth data to JSON
    case Jason.encode(auth_data) do
      {:ok, encoded_data} ->
        # Send the authentication frame
        case send_frame_fn.(nil, :text, encoded_data, nil) do
          :ok -> :ok
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        Logger.error("Failed to encode authentication data: #{inspect(reason)}")
        {:error, :encode_error}
    end
  end
end
