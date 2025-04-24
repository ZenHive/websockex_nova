defmodule WebsockexNova.Examples.AdapterDeribit do
  @moduledoc """
  Example Deribit adapter using `use WebsockexNova.Adapter` macro.

  This demonstrates how to build a Deribit WebSocket API adapter with minimal overrides.
  """
  use WebsockexNova.Adapter

  alias WebsockexNova.Behaviors.AuthHandler
  alias WebsockexNova.Behaviors.ConnectionHandler

  @port 443
  @path "/ws/api/v2"

  defp default_host do
    case Mix.env() do
      :test -> "test.deribit.com"
      :dev -> "test.deribit.com"
      _ -> "www.deribit.com"
    end
  end

  @impl ConnectionHandler
  def connection_info(_opts) do
    host = System.get_env("DERIBIT_HOST") || default_host()

    {:ok,
     %{
       host: host,
       port: @port,
       path: @path,
       headers: [],
       timeout: 30_000,
       transport_opts: %{transport: :tls}
     }}
  end

  @impl ConnectionHandler
  def init(_opts) do
    then(
      %{
        messages: [],
        connected_at: nil,
        auth_status: :unauthenticated,
        reconnect_attempts: 0,
        max_reconnect_attempts: 5,
        subscriptions: %{},
        subscription_requests: %{}
      },
      &{:ok, &1}
    )
  end

  @impl AuthHandler
  def generate_auth_data(state) do
    client_id = System.get_env("DERIBIT_CLIENT_ID")
    client_secret = System.get_env("DERIBIT_CLIENT_SECRET")

    payload = %{
      "jsonrpc" => "2.0",
      "id" => 42,
      "method" => "public/auth",
      "params" => %{
        "grant_type" => "client_credentials",
        "client_id" => client_id,
        "client_secret" => client_secret
      }
    }

    state = put_in(state, [:credentials], %{api_key: client_id, secret: client_secret})
    {:ok, Jason.encode!(payload), state}
  end

  @impl AuthHandler
  def handle_auth_response(%{"result" => %{"access_token" => access_token, "expires_in" => expires_in}}, state) do
    state =
      state
      |> Map.put(:auth_status, :authenticated)
      |> Map.put(:access_token, access_token)
      |> Map.put(:auth_expires_in, expires_in)

    {:ok, state}
  end

  def handle_auth_response(%{"error" => error}, state) do
    state =
      state
      |> Map.put(:auth_status, :failed)
      |> Map.put(:auth_error, error)

    {:error, error, state}
  end

  def handle_auth_response(_other, state), do: {:ok, state}

  @impl WebsockexNova.Behaviors.SubscriptionHandler
  def subscribe(channel, _params, state) do
    message = %{
      "jsonrpc" => "2.0",
      "id" => System.unique_integer([:positive]),
      "method" => "public/subscribe",
      "params" => %{"channels" => [channel]}
    }

    {:ok, Jason.encode!(message), state}
  end
end
