defmodule WebsockexNova.Gun.ConnectionOptions do
  @moduledoc """
  Centralized parsing and validation for Gun connection options.

  This module merges user options with defaults, validates required fields,
  and normalizes option values for consistent downstream usage.
  """

  @default_options %{
    transport: :tcp,
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
