defmodule WebsockexNova.Defaults.DefaultAuthHandler do
  @moduledoc """
  Default implementation of the AuthHandler behavior.

  This module provides sensible default implementations for all AuthHandler
  callbacks, including:

  * Basic token-based authentication
  * Automatic token expiration tracking
  * Credential management
  * Authentication status tracking

  ## Usage

  You can use this module directly or as a starting point for your own implementation:

      defmodule MyApp.CustomAuthHandler do
        use WebsockexNova.Defaults.DefaultAuthHandler

        # Override specific callbacks as needed
        def generate_auth_data(state) do
          # Custom auth data generation
          {:ok, auth_data, state}
        end
      end

  ## Configuration

  The default handler expects the following configuration in the state:

  * `:credentials` - Map containing authentication credentials (required)
      * `:api_key` - API key or client ID
      * `:secret` - API secret or password
  * `:auth_status` - Current authentication status (default: :unauthenticated)
  * `:auth_expires_at` - Unix timestamp when the authentication token expires (optional)
  * `:auth_refresh_threshold` - Seconds before expiry to trigger reauthentication (default: 60)
  """

  @behaviour WebsockexNova.Behaviors.AuthHandler

  require Logger

  @default_auth_refresh_threshold 60
  @default_auth_timeout 3600

  @doc """
  Initializes the auth handler state.

  ## Parameters

  * `options` - Map of options for the auth handler

  ## Returns

  `{:ok, state}` or `{:error, reason, state}`
  """
  @spec auth_init(map()) :: {:ok, map()} | {:error, atom() | String.t(), map()}
  def auth_init(options) when is_map(options) do
    # Add default values if not present
    state =
      options
      |> Map.put_new(:auth_status, :unauthenticated)
      |> Map.put_new(:auth_refresh_threshold, @default_auth_refresh_threshold)

    if has_valid_credentials?(state) do
      {:ok, state}
    else
      {:error, :invalid_credentials, state}
    end
  end

  def auth_init(options) when is_list(options) do
    auth_init(Map.new(options))
  end

  @impl true
  def generate_auth_data(state) do
    with true <- has_valid_credentials?(state),
         %{credentials: credentials} <- state do
      auth_data = build_auth_data(credentials, state)
      {:ok, auth_data, state}
    else
      false ->
        {:error, :missing_credentials, state}

      _error ->
        {:error, :invalid_state, state}
    end
  end

  @impl true
  def handle_auth_response(response, state) when is_map(response) and is_map(state) do
    case response do
      %{"type" => "auth_success"} = resp ->
        handle_auth_success(resp, state)

      %{"type" => "auth_error", "reason" => reason} ->
        handle_auth_error(reason, state)

      %{"type" => "auth_error"} = resp ->
        reason = Map.get(resp, "message", "Unknown auth error")
        handle_auth_error(reason, state)

      _ ->
        {:ok, state}
    end
  end

  @impl true
  def needs_reauthentication?(state) when is_map(state) do
    threshold = Map.get(state, :auth_refresh_threshold, @default_auth_refresh_threshold)

    cond do
      # If auth status is failed, needs reauthentication
      Map.get(state, :auth_status) == :failed ->
        true

      # If not authenticated yet, doesn't need reauthentication
      Map.get(state, :auth_status) != :authenticated ->
        false

      # If no auth expiration timestamp, doesn't need reauthentication
      not Map.has_key?(state, :auth_expires_at) ->
        false

      # If auth is about to expire, needs reauthentication
      state.auth_expires_at < System.system_time(:second) + threshold ->
        true

      # Otherwise, doesn't need reauthentication
      true ->
        false
    end
  end

  @impl true
  def authenticate(stream_ref, credentials, state) when is_map(credentials) and is_map(state) do
    # Update state with credentials and generate auth data
    updated_state = Map.put(state, :credentials, credentials)

    # In a real implementation, you would use stream_ref to send authentication data
    # This is a simplified implementation
    _stream_ref = stream_ref

    {:ok, updated_state}
  end

  # Private helper functions

  defp handle_auth_success(response, state) do
    expires_at =
      case response do
        %{"expires_at" => expires_at} when is_integer(expires_at) ->
          expires_at

        %{"expires_in" => expires_in} when is_integer(expires_in) ->
          System.system_time(:second) + expires_in

        _ ->
          System.system_time(:second) + @default_auth_timeout
      end

    token =
      case response do
        %{"token" => token} -> token
        _ -> nil
      end

    updated_state =
      state
      |> Map.put(:auth_status, :authenticated)
      |> Map.put(:auth_expires_at, expires_at)
      |> maybe_put_token(token)

    {:ok, updated_state}
  end

  defp handle_auth_error(reason, state) do
    Logger.warning("Authentication error: #{reason}")

    updated_state =
      state
      |> Map.put(:auth_status, :failed)
      |> Map.put(:auth_error, reason)

    {:error, reason, updated_state}
  end

  defp has_valid_credentials?(state) do
    case state do
      %{credentials: %{api_key: api_key, secret: secret}}
      when is_binary(api_key) and is_binary(secret) and api_key != "" and secret != "" ->
        true

      %{credentials: %{token: token}}
      when is_binary(token) and token != "" ->
        true

      _ ->
        false
    end
  end

  # @doc """
  # Generates authentication data based on the provided credentials.

  # This default implementation returns a map, but custom implementations can
  # return either a map or binary data depending on the WebSocket protocol requirements.

  # Custom implementations might override this to return binary formats like:
  # - Raw binary token data
  # - Custom binary protocols
  # - Pre-encoded WebSocket frames
  # """
  defp build_auth_data(credentials, _state) do
    timestamp = System.system_time(:second)

    base_auth_data = %{
      type: "auth",
      timestamp: timestamp
    }

    cond do
      Map.has_key?(credentials, :token) ->
        Map.put(base_auth_data, :token, credentials.token)

      Map.has_key?(credentials, :api_key) ->
        signature = generate_signature(credentials, timestamp)

        base_auth_data
        |> Map.put(:api_key, credentials.api_key)
        |> Map.put(:signature, signature)

      true ->
        base_auth_data
    end
  end

  defp generate_signature(credentials, timestamp) do
    # Simple HMAC signature example - specific implementations should override this
    # with their own signature generation logic
    data = "#{credentials.api_key}#{timestamp}"

    :hmac
    |> :crypto.mac(:sha256, credentials.secret, data)
    |> Base.encode16(case: :lower)
  end

  defp maybe_put_token(state, nil), do: state
  defp maybe_put_token(state, token), do: put_in(state, [:credentials, :token], token)
end
