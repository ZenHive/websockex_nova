defmodule WebsockexNew.Client do
  @moduledoc """
  Simple WebSocket client using Gun as transport layer.

  Provides 5 core functions:
  - connect/2 - Establish connection
  - send_message/2 - Send messages  
  - close/1 - Close connection
  - subscribe/2 - Subscribe to channels
  - get_state/1 - Get connection state
  """

  defstruct [:gun_pid, :stream_ref, :state, :url, :monitor_ref]

  @type t :: %__MODULE__{
          gun_pid: pid() | nil,
          stream_ref: reference() | nil,
          state: :connecting | :connected | :disconnected,
          url: String.t() | nil,
          monitor_ref: reference() | nil
        }

  @spec connect(String.t() | WebsockexNew.Config.t(), keyword()) :: {:ok, t()} | {:error, term()}
  def connect(url_or_config, opts \\ [])

  def connect(url, opts) when is_binary(url) do
    case WebsockexNew.Config.new(url, opts) do
      {:ok, config} -> connect(config, [])
      error -> error
    end
  end

  def connect(%WebsockexNew.Config{} = config, _opts) do
    case connect_with_error_handling(config) do
      {:ok, client} -> {:ok, client}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec connect_with_error_handling(WebsockexNew.Config.t()) :: {:ok, t()} | {:error, term()}
  defp connect_with_error_handling(config) do
    uri = URI.parse(config.url)
    port = uri.port || if uri.scheme == "wss", do: 443, else: 80

    case :gun.open(to_charlist(uri.host), port, %{protocols: [:http]}) do
      {:ok, gun_pid} ->
        monitor_ref = Process.monitor(gun_pid)

        case :gun.await_up(gun_pid, config.timeout) do
          {:ok, _protocol} ->
            stream_ref = :gun.ws_upgrade(gun_pid, uri.path || "/", config.headers)

            client = %__MODULE__{
              gun_pid: gun_pid,
              stream_ref: stream_ref,
              state: :connecting,
              url: config.url,
              monitor_ref: monitor_ref
            }

            case wait_for_upgrade(client, config.timeout) do
              {:ok, connected_client} -> {:ok, connected_client}
              {:error, reason} -> handle_connection_error(client, reason)
            end

          {:error, reason} ->
            Process.demonitor(monitor_ref, [:flush])
            :gun.close(gun_pid)
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec handle_connection_error(t(), term()) :: {:error, term()}
  defp handle_connection_error(client, reason) do
    close(client)

    case WebsockexNew.ErrorHandler.handle_error(reason) do
      :reconnect -> {:error, {:recoverable, reason}}
      _ -> {:error, reason}
    end
  end

  @spec wait_for_upgrade(t(), integer()) :: {:ok, t()} | {:error, term()}
  def wait_for_upgrade(%__MODULE__{gun_pid: gun_pid, stream_ref: stream_ref} = client, timeout) do
    receive do
      {:gun_upgrade, ^gun_pid, ^stream_ref, ["websocket"], _headers} ->
        {:ok, %{client | state: :connected}}

      {:gun_error, ^gun_pid, ^stream_ref, reason} ->
        {:error, {:gun_error, gun_pid, stream_ref, reason}}

      {:gun_down, ^gun_pid, _, reason, _} ->
        {:error, {:gun_down, gun_pid, nil, reason, nil}}

      {:DOWN, _ref, :process, ^gun_pid, reason} ->
        {:error, {:connection_down, reason}}
    after
      timeout ->
        {:error, :timeout}
    end
  end

  @spec send_message(t(), binary()) :: :ok | {:error, term()}
  def send_message(%__MODULE__{gun_pid: gun_pid, stream_ref: stream_ref, state: :connected}, message) do
    :gun.ws_send(gun_pid, stream_ref, {:text, message})
  end

  def send_message(%__MODULE__{state: state}, _message) do
    {:error, {:not_connected, state}}
  end

  @spec close(t()) :: :ok
  def close(%__MODULE__{gun_pid: gun_pid, monitor_ref: monitor_ref}) when is_pid(gun_pid) do
    Process.demonitor(monitor_ref, [:flush])
    :gun.close(gun_pid)
  end

  def close(_client), do: :ok

  @spec subscribe(t(), list()) :: :ok | {:error, term()}
  def subscribe(client, channels) when is_list(channels) do
    message = Jason.encode!(%{method: "public/subscribe", params: %{channels: channels}})
    send_message(client, message)
  end

  @spec get_state(t()) :: :connecting | :connected | :disconnected
  def get_state(%__MODULE__{state: state}), do: state

  @spec reconnect(t()) :: {:ok, t()} | {:error, term()}
  def reconnect(%__MODULE__{url: url} = client) do
    close(client)

    case connect(url) do
      {:ok, new_client} ->
        {:ok, new_client}

      {:error, reason} ->
        if WebsockexNew.ErrorHandler.recoverable?(reason) do
          {:error, {:recoverable, reason}}
        else
          {:error, reason}
        end
    end
  end
end
