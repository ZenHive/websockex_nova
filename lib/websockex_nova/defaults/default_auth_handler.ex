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

  The default handler expects the following configuration in adapter_state:

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

  @impl true
  def generate_auth_data(%WebsockexNova.ClientConn{adapter_state: adapter_state} = conn) do
    case has_valid_credentials?(adapter_state) do
      true ->
        credentials = Map.get(adapter_state, :credentials)
        auth_data = build_auth_data(credentials, conn)
        {:ok, auth_data, conn}

      false ->
        {:error, :missing_credentials, conn}

      _error ->
        {:error, :invalid_state, conn}
    end
  end

  @impl true
  def handle_auth_response(response, %WebsockexNova.ClientConn{adapter_state: _adapter_state} = conn) do
    case response do
      %{"type" => "auth_success"} = resp ->
        handle_auth_success(resp, conn)

      %{"type" => "auth_error", "reason" => reason} ->
        handle_auth_error(reason, conn)

      %{"type" => "auth_error"} = resp ->
        reason = Map.get(resp, "message", "Unknown auth error")
        handle_auth_error(reason, conn)

      _ ->
        {:ok, conn}
    end
  end

  @impl true
  def needs_reauthentication?(%WebsockexNova.ClientConn{adapter_state: adapter_state}) do
    auth_status = Map.get(adapter_state, :auth_status, :unauthenticated)
    auth_expires_at = Map.get(adapter_state, :auth_expires_at)
    threshold = Map.get(adapter_state, :auth_refresh_threshold, @default_auth_refresh_threshold)

    cond do
      auth_status == :failed -> true
      auth_status != :authenticated -> false
      is_nil(auth_expires_at) -> false
      auth_expires_at < System.system_time(:second) + threshold -> true
      true -> false
    end
  end

  @impl true
  def authenticate(_stream_ref, credentials, %WebsockexNova.ClientConn{adapter_state: adapter_state} = conn)
      when is_map(credentials) do
    updated_adapter_state = Map.put(adapter_state, :credentials, credentials)
    updated_conn = %{conn | adapter_state: updated_adapter_state}
    {:ok, updated_conn}
  end

  # Private helper functions

  defp handle_auth_success(response, %WebsockexNova.ClientConn{adapter_state: adapter_state} = conn) do
    expires_at =
      case response do
        %{"expires_at" => expires_at} when is_integer(expires_at) -> expires_at
        %{"expires_in" => expires_in} when is_integer(expires_in) -> System.system_time(:second) + expires_in
        _ -> System.system_time(:second) + @default_auth_timeout
      end

    token = Map.get(response, "token")

    updated_adapter_state =
      adapter_state
      |> Map.put(:auth_status, :authenticated)
      |> Map.put(:auth_expires_at, expires_at)
      |> maybe_put_token(token)

    updated_conn = %{conn | adapter_state: updated_adapter_state}

    {:ok, updated_conn}
  end

  defp handle_auth_error(reason, %WebsockexNova.ClientConn{adapter_state: adapter_state} = conn) do
    Logger.warning("Authentication error: #{reason}")

    updated_adapter_state =
      adapter_state
      |> Map.put(:auth_status, :failed)
      |> Map.put(:auth_error, reason)

    updated_conn = %{conn | adapter_state: updated_adapter_state}

    {:error, reason, updated_conn}
  end

  defp has_valid_credentials?(adapter_state) do
    case Map.get(adapter_state, :credentials) do
      %{api_key: api_key, secret: secret}
      when is_binary(api_key) and is_binary(secret) and api_key != "" and secret != "" ->
        true

      %{token: token} when is_binary(token) and token != "" ->
        true

      _ ->
        false
    end
  end

  defp build_auth_data(credentials, _conn) do
    timestamp = System.system_time(:second)
    base_auth_data = %{type: "auth", timestamp: timestamp}

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
    data = "#{credentials.api_key}#{timestamp}"

    :hmac
    |> :crypto.mac(:sha256, credentials.secret, data)
    |> Base.encode16(case: :lower)
  end

  defp maybe_put_token(adapter_state, nil), do: adapter_state

  defp maybe_put_token(adapter_state, token) do
    creds = Map.get(adapter_state, :credentials, %{})
    updated_creds = Map.put(creds, :token, token)
    Map.put(adapter_state, :credentials, updated_creds)
  end
end
