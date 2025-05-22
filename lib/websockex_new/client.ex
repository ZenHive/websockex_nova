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

  @spec connect(String.t(), keyword()) :: {:ok, t()} | {:error, term()}
  def connect(url, _opts \\ []) do
    uri = URI.parse(url)
    port = uri.port || if uri.scheme == "wss", do: 443, else: 80

    case :gun.open(to_charlist(uri.host), port, %{protocols: [:http]}) do
      {:ok, gun_pid} ->
        monitor_ref = Process.monitor(gun_pid)
        :gun.await_up(gun_pid, 5000)

        stream_ref = :gun.ws_upgrade(gun_pid, uri.path || "/", [])

        client = %__MODULE__{
          gun_pid: gun_pid,
          stream_ref: stream_ref,
          state: :connecting,
          url: url,
          monitor_ref: monitor_ref
        }

        {:ok, client}

      {:error, reason} ->
        {:error, reason}
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
end
