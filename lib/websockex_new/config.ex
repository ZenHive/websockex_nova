defmodule WebsockexNew.Config do
  @moduledoc """
  Configuration struct for WebSocket connections.
  """

  defstruct [
    :url,
    headers: [],
    timeout: 5_000,
    retry_count: 3,
    retry_delay: 1_000,
    heartbeat_interval: 30_000
  ]

  @type t :: %__MODULE__{
    url: String.t(),
    headers: [{String.t(), String.t()}],
    timeout: pos_integer(),
    retry_count: non_neg_integer(),
    retry_delay: pos_integer(),
    heartbeat_interval: pos_integer()
  }

  @doc """
  Creates and validates a new configuration.
  """
  @spec new(String.t(), keyword()) :: {:ok, t()} | {:error, String.t()}
  def new(url, opts \\ []) when is_binary(url) do
    config = struct(__MODULE__, [{:url, url} | opts])
    validate(config)
  end

  @doc """
  Validates a configuration struct.
  """
  @spec validate(t()) :: {:ok, t()} | {:error, String.t()}
  def validate(%__MODULE__{url: url} = config) when is_binary(url) do
    cond do
      not valid_url?(url) ->
        {:error, "Invalid URL format"}
      
      config.timeout <= 0 ->
        {:error, "Timeout must be positive"}
      
      config.retry_count < 0 ->
        {:error, "Retry count must be non-negative"}
      
      config.retry_delay <= 0 ->
        {:error, "Retry delay must be positive"}
      
      config.heartbeat_interval <= 0 ->
        {:error, "Heartbeat interval must be positive"}
      
      true ->
        {:ok, config}
    end
  end
  
  def validate(_), do: {:error, "URL is required"}

  defp valid_url?(url) do
    case URI.parse(url) do
      %URI{scheme: scheme, host: host} when scheme in ["ws", "wss"] and is_binary(host) and host != "" ->
        true
      _ ->
        false
    end
  end
end