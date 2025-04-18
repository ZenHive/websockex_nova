defmodule WebsockexNova.Behaviors.AuthHandler do
  @moduledoc """
  Defines a behavior for handling WebSocket authentication flows.

  The `AuthHandler` behavior provides a standardized interface for authentication
  operations in WebSocket connections, including:

  - Generating authentication data to send to the server
  - Processing authentication responses from the server
  - Determining when reauthentication is needed

  ## Architecture

  WebsockexNova uses a thin adapter architecture for authentication, allowing applications
  to implement service-specific authentication logic while the core library handles
  connection and message flow.

  ## Authentication Flow

  1. The client needs to authenticate (initial connection or reauthentication)
  2. `generate_auth_data/1` is called to create authentication payload
  3. The authentication message is sent to the server
  4. Server responds with success or error
  5. `handle_auth_response/2` processes the response and updates state
  6. During connection, `needs_reauthentication?/1` periodically checks if auth renewal is needed

  ## Implementation Example

  ```elixir
  defmodule MyApp.ApiAuthHandler do
    @behaviour WebsockexNova.Behaviors.AuthHandler

    @impl true
    def generate_auth_data(state) do
      # Get API credentials from state
      %{api_key: api_key, secret: secret} = state.credentials

      # Generate timestamp and signature
      timestamp = System.system_time(:second)
      signature = generate_hmac_signature(secret, timestamp)

      # Create auth payload
      auth_data = %{
        type: "auth",
        api_key: api_key,
        timestamp: timestamp,
        signature: signature
      }

      {:ok, auth_data, state}
    end

    @impl true
    def handle_auth_response(%{"type" => "auth_success", "expires_at" => expires_at}, state) do
      # Update state with authentication status and expiration
      updated_state =
        state
        |> Map.put(:auth_status, :authenticated)
        |> Map.put(:auth_expires_at, expires_at)

      {:ok, updated_state}
    end

    @impl true
    def handle_auth_response(%{"type" => "auth_error", "reason" => reason}, state) do
      # Update state with error information
      updated_state =
        state
        |> Map.put(:auth_status, :failed)
        |> Map.put(:auth_error, reason)

      {:error, reason, updated_state}
    end

    @impl true
    def handle_auth_response(_response, state) do
      # Ignore unrelated messages
      {:ok, state}
    end

    @impl true
    def needs_reauthentication?(state) do
      cond do
        state.auth_status == :failed -> true
        not Map.has_key?(state, :auth_expires_at) -> false
        state.auth_expires_at < System.system_time(:second) + 60 -> true
        true -> false
      end
    end

    defp generate_hmac_signature(secret, timestamp) do
      # Implementation of signature generation
    end
  end
  """

  @doc """
  Generates authentication data to be sent to the WebSocket server.

  This function is called when authentication is needed, either during initial
  connection or when reauthentication is required.

  ## Parameters

  - `state`: The current state map, expected to contain authentication credentials

  ## Returns

  - `{:ok, auth_data, state}`: Authentication data generated successfully
    - `auth_data`: A map containing authentication payload to send to the server
    - `state`: Potentially updated state after generating authentication data
  - `{:error, reason, state}`: Failed to generate authentication data
    - `reason`: Atom or string describing the error
    - `state`: Potentially updated state after the error
  """
  @callback generate_auth_data(state :: map()) ::
              {:ok, auth_data :: map(), updated_state :: map()}
              | {:error, reason :: atom() | String.t(), updated_state :: map()}

  @doc """
  Processes an authentication response received from the WebSocket server.

  This function is called when a message that might be an authentication response
  is received. It should identify if the message is authentication-related and
  update the state accordingly.

  ## Parameters

  - `response`: The response message from the server, typically a map
  - `state`: The current state map

  ## Returns

  - `{:ok, updated_state}`: Authentication successful or message processed
    - `updated_state`: State updated with authentication information
  - `{:error, reason, updated_state}`: Authentication failed
    - `reason`: Atom or string describing the error
    - `updated_state`: State updated with error information
  """
  @callback handle_auth_response(response :: map(), state :: map()) ::
              {:ok, updated_state :: map()}
              | {:error, reason :: atom() | String.t(), updated_state :: map()}

  @doc """
  Determines if reauthentication is needed based on the current state.

  This function is called periodically to check if authentication needs to be renewed,
  typically due to token expiration or previous authentication failure.

  ## Parameters

  - `state`: The current state map, containing authentication status information

  ## Returns

  - `true`: Reauthentication is needed
  - `false`: Current authentication is still valid
  """
  @callback needs_reauthentication?(state :: map()) :: boolean()
end
