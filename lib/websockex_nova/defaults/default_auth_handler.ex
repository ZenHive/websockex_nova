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

  `{:ok, state}` or `{:error, reason}`
  """
  @spec init(map()) :: {:ok, map()} | {:error, atom() | String.t()}
  def init(options) when is_map(options) do
    # Add default values if not present
    state =
      options
      |> Map.put_new(:auth_status, :unauthenticated)
      |> Map.put_new(:auth_refresh_threshold, @default_auth_refresh_threshold)

    if has_valid_credentials?(state) do
      {:ok, state}
    else
      {:error, :invalid_credentials}
    end
  end

  def init(options) when is_list(options) do
    init(Map.new(options))
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
  def handle_auth_response(%{"type" => "auth_success"} = response, state) do
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

  @impl true
  def handle_auth_response(%{"type" => "auth_error", "reason" => reason}, state) do
    Logger.warning("Authentication error: #{reason}")

    updated_state =
      state
      |> Map.put(:auth_status, :failed)
      |> Map.put(:auth_error, reason)

    {:error, reason, updated_state}
  end

  @impl true
  def handle_auth_response(%{"type" => "auth_error"} = response, state) do
    reason = Map.get(response, "message", "Unknown auth error")
    Logger.warning("Authentication error: #{reason}")

    updated_state =
      state
      |> Map.put(:auth_status, :failed)
      |> Map.put(:auth_error, reason)

    {:error, reason, updated_state}
  end

  @impl true
  def handle_auth_response(_response, state) do
    {:ok, state}
  end

  @impl true
  def needs_reauthentication?(state) do
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

  # @doc """
  # Authenticate with the provided credentials.

  # This function is called by the Connection module when WebsockexNova.Client.authenticate/2 is used.
  # It delegates to the adapter's encode_auth_request/1 function to generate the appropriate auth request
  # for the platform.

  # ## Parameters

  # * `credentials` - Authentication credentials (typically %{api_key: key, secret: secret})
  # * `state` - Current state

  # ## Returns

  # * `{:reply, reply, new_state}` - Send a message back to the caller
  # * `{:noreply, new_state}` - No immediate reply
  # """
  # def authenticate(credentials, state) do
  #   case state.adapter.encode_auth_request(credentials) do
  #     {:text, request} ->
  #       # Send auth request frame to the websocket and update state
  #       send(self(), {:send_frame, {:text, request}})

  #       updated_state =
  #         state
  #         |> Map.put(:auth_status, :authenticating)
  #         |> Map.put(:credentials, credentials)

  #       {:noreply, updated_state}

  #     {:error, reason} ->
  #       # Authentication encoding failed
  #       {:error, reason, state}
  #   end
  # end

  @impl true
  def authenticate(_stream_ref, _credentials, state) do
    {:ok, state}
  end

  # Private helper functions

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
