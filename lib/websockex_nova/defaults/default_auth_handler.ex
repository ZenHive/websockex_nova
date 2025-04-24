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
  Returns {:ok, %WebsockexNova.ClientConn{}} or {:error, reason, %WebsockexNova.ClientConn{}}
  Any unknown fields are placed in auth_handler_settings.
  """
  @spec auth_init(map() | keyword()) ::
          {:ok, WebsockexNova.ClientConn.t()} | {:error, atom() | String.t(), WebsockexNova.ClientConn.t()}
  def auth_init(options) when is_map(options) or is_list(options) do
    opts_map = if is_list(options), do: Map.new(options), else: options
    # Split known fields and custom fields
    known_keys = MapSet.new(Map.keys(%WebsockexNova.ClientConn{}))
    {known, custom} = Enum.split_with(opts_map, fn {k, _v} -> MapSet.member?(known_keys, k) end)
    known_map = Map.new(known)
    custom_map = Map.new(custom)
    # Build struct with defaults and provided options
    conn = struct(WebsockexNova.ClientConn, known_map)

    conn = %{
      conn
      | auth_status: Map.get(opts_map, :auth_status, :unauthenticated),
        auth_refresh_threshold: Map.get(opts_map, :auth_refresh_threshold, 60),
        auth_handler_settings: Map.merge(conn.auth_handler_settings || %{}, custom_map)
    }

    if has_valid_credentials?(conn) do
      {:ok, conn}
    else
      {:error, :invalid_credentials, conn}
    end
  end

  @impl true
  def generate_auth_data(%WebsockexNova.ClientConn{} = conn) do
    with true <- has_valid_credentials?(conn),
         %{credentials: credentials} <- conn do
      auth_data = build_auth_data(credentials, conn)
      {:ok, auth_data, conn}
    else
      false ->
        {:error, :missing_credentials, conn}

      _error ->
        {:error, :invalid_state, conn}
    end
  end

  @impl true
  def handle_auth_response(response, %WebsockexNova.ClientConn{} = conn) do
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
  def needs_reauthentication?(%WebsockexNova.ClientConn{} = conn) do
    threshold = conn.auth_refresh_threshold || @default_auth_refresh_threshold

    cond do
      conn.auth_status == :failed -> true
      conn.auth_status != :authenticated -> false
      is_nil(conn.auth_expires_at) -> false
      conn.auth_expires_at < System.system_time(:second) + threshold -> true
      true -> false
    end
  end

  @impl true
  def authenticate(_stream_ref, credentials, %WebsockexNova.ClientConn{} = conn) when is_map(credentials) do
    updated_conn = %{conn | credentials: credentials}
    {:ok, updated_conn}
  end

  # Private helper functions

  defp handle_auth_success(response, %WebsockexNova.ClientConn{} = conn) do
    expires_at =
      case response do
        %{"expires_at" => expires_at} when is_integer(expires_at) -> expires_at
        %{"expires_in" => expires_in} when is_integer(expires_in) -> System.system_time(:second) + expires_in
        _ -> System.system_time(:second) + @default_auth_timeout
      end

    token = Map.get(response, "token")

    updated_conn =
      conn
      |> Map.put(:auth_status, :authenticated)
      |> Map.put(:auth_expires_at, expires_at)
      |> maybe_put_token(token)

    {:ok, updated_conn}
  end

  defp handle_auth_error(reason, %WebsockexNova.ClientConn{} = conn) do
    Logger.warning("Authentication error: #{reason}")

    updated_conn =
      conn
      |> Map.put(:auth_status, :failed)
      |> Map.put(:auth_error, reason)

    {:error, reason, updated_conn}
  end

  defp has_valid_credentials?(%WebsockexNova.ClientConn{credentials: %{api_key: api_key, secret: secret}})
       when is_binary(api_key) and is_binary(secret) and api_key != "" and secret != "" do
    true
  end

  defp has_valid_credentials?(%WebsockexNova.ClientConn{credentials: %{token: token}})
       when is_binary(token) and token != "" do
    true
  end

  defp has_valid_credentials?(_), do: false

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

  defp maybe_put_token(conn, nil), do: conn

  defp maybe_put_token(%WebsockexNova.ClientConn{credentials: creds} = conn, token) do
    new_creds = Map.put(creds || %{}, :token, token)
    %{conn | credentials: new_creds}
  end
end
