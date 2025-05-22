defmodule WebsockexNew.Reconnection do
  @moduledoc """
  Simple exponential backoff reconnection logic without GenServer.
  """

  alias WebsockexNew.{Client, Config}

  @doc """
  Calculate exponential backoff delay.
  """
  @spec calculate_delay(non_neg_integer(), pos_integer()) :: pos_integer()
  def calculate_delay(attempt, base_delay) do
    min(base_delay * :math.pow(2, attempt), 30_000) |> round()
  end

  @doc """
  Attempt reconnection with exponential backoff.
  """
  @spec reconnect(Config.t(), non_neg_integer(), list()) :: {:ok, Client.t()} | {:error, :max_retries}
  def reconnect(config, attempt \\ 0, subscriptions \\ [])

  def reconnect(%Config{retry_count: max_retries}, attempt, _subscriptions) 
      when attempt >= max_retries do
    {:error, :max_retries}
  end

  def reconnect(%Config{} = config, attempt, subscriptions) do
    case Client.connect(config) do
      {:ok, client} ->
        restore_subscriptions(client, subscriptions)
        {:ok, client}
      
      {:error, _reason} ->
        delay = calculate_delay(attempt, config.retry_delay)
        :timer.sleep(delay)
        reconnect(config, attempt + 1, subscriptions)
    end
  end

  @doc """
  Restore subscriptions after reconnection.
  """
  @spec restore_subscriptions(Client.t(), list()) :: :ok
  def restore_subscriptions(_client, []), do: :ok
  def restore_subscriptions(client, subscriptions) when is_list(subscriptions) do
    Client.subscribe(client, subscriptions)
    :ok
  end

  @doc """
  Check if reconnection should be attempted.
  """
  @spec should_reconnect?(non_neg_integer(), non_neg_integer()) :: boolean()
  def should_reconnect?(attempt, max_retries) do
    attempt < max_retries
  end
end