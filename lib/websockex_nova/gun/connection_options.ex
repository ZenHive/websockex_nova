defmodule WebsockexNova.Gun.ConnectionOptions do
  @moduledoc """
  Centralized parsing and validation for Gun connection options.

  ## Defaults and Security

  - The default transport is `:tls` (HTTPS/WSS) for secure connections.
  - For most production APIs and public WebSocket endpoints, this is required.
  - If you are connecting to a local or non-TLS endpoint (e.g., localhost:80), you must override:

      %{transport: :tcp, port: 80}

  - For self-signed certificates in development, you can use:

      %{transport: :tls, transport_opts: [verify: :verify_none]}

    **Never use `verify: :verify_none` in production!**

  ## Example Usage

      # Production (default)
      {:ok, conn} = WebsockexNova.Gun.ConnectionWrapper.open("api.example.com", 443)

      # Local development (plain HTTP)
      {:ok, conn} = WebsockexNova.Gun.ConnectionWrapper.open("localhost", 80, %{transport: :tcp})

      # Local development (self-signed HTTPS)
      {:ok, conn} = WebsockexNova.Gun.ConnectionWrapper.open("localhost", 443, %{transport_opts: [verify: :verify_none]})

  This module merges user options with defaults, validates required fields,
  and normalizes option values for consistent downstream usage.
  """

  require Logger

  @default_options %{
    transport: :tls,
    transport_opts: [],
    protocols: [:http],
    retry: 5,
    ws_opts: %{},
    backoff_type: :exponential,
    base_backoff: 1000
  }

  @spec parse_and_validate(map()) :: {:ok, map()} | {:error, String.t()}
  def parse_and_validate(opts) do
    opts = Map.merge(@default_options, opts)

    # Warn if using TLS with port 80 (common misconfiguration)
    if opts[:transport] == :tls and Map.get(opts, :port, 443) == 80 do
      Logger.warning(
        "You are connecting to port 80 with TLS. This is unusual—did you mean to use transport: :tcp?"
      )
    end

    with :ok <- validate_transport(opts),
         :ok <- validate_protocols(opts),
         :ok <- validate_retry(opts),
         :ok <- validate_backoff(opts) do
      {:ok, opts}
    end
  end

  @spec validate_transport(map()) :: :ok | {:error, String.t()}
  defp validate_transport(%{transport: t}) when t in [:tcp, :tls], do: :ok
  defp validate_transport(_), do: {:error, "Invalid or missing :transport option"}

  @spec validate_protocols(map()) :: :ok | {:error, String.t()}
  defp validate_protocols(%{protocols: protocols}) when is_list(protocols), do: :ok
  defp validate_protocols(_), do: {:error, ":protocols must be a list"}

  @spec validate_retry(map()) :: :ok | {:error, String.t()}
  defp validate_retry(%{retry: :infinity}), do: :ok
  defp validate_retry(%{retry: n}) when is_integer(n) and n >= 0, do: :ok
  defp validate_retry(_), do: {:error, ":retry must be a non-negative integer or :infinity"}

  @spec validate_backoff(map()) :: :ok | {:error, String.t()}
  defp validate_backoff(%{base_backoff: n}) when is_integer(n) and n > 0, do: :ok
  defp validate_backoff(_), do: {:error, ":base_backoff must be a positive integer"}
end
