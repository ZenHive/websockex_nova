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

  use GenServer

  defstruct [:gun_pid, :stream_ref, :state, :url, :monitor_ref, :server_pid]

  @type t :: %__MODULE__{
          gun_pid: pid() | nil,
          stream_ref: reference() | nil,
          state: :connecting | :connected | :disconnected,
          url: String.t() | nil,
          monitor_ref: reference() | nil,
          server_pid: pid() | nil
        }

  @type state :: %{
          gun_pid: pid() | nil,
          stream_ref: reference() | nil,
          state: :connecting | :connected | :disconnected,
          url: String.t() | nil,
          monitor_ref: reference() | nil
        }

  # Public API

  @spec connect(String.t() | WebsockexNew.Config.t(), keyword()) :: {:ok, t()} | {:error, term()}
  def connect(url_or_config, opts \\ [])

  def connect(url, opts) when is_binary(url) do
    case WebsockexNew.Config.new(url, opts) do
      {:ok, config} -> connect(config, [])
      error -> error
    end
  end

  def connect(%WebsockexNew.Config{} = config, _opts) do
    case GenServer.start(__MODULE__, config) do
      {:ok, server_pid} ->
        # Add a bit more time for GenServer overhead
        timeout = max(config.timeout + 100, 1000)

        try do
          case GenServer.call(server_pid, :await_connection, timeout) do
            {:ok, state} ->
              {:ok, build_client_struct(state, server_pid)}

            {:error, reason} ->
              GenServer.stop(server_pid)
              {:error, reason}
          end
        catch
          :exit, {:timeout, _} ->
            GenServer.stop(server_pid)
            {:error, :timeout}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec send_message(t(), binary()) :: :ok | {:error, term()}
  def send_message(%__MODULE__{server_pid: server_pid}, message) when is_pid(server_pid) do
    GenServer.call(server_pid, {:send_message, message})
  end

  def send_message(%__MODULE__{gun_pid: gun_pid, stream_ref: stream_ref, state: :connected}, message) do
    :gun.ws_send(gun_pid, stream_ref, {:text, message})
  end

  def send_message(%__MODULE__{state: state}, _message) do
    {:error, {:not_connected, state}}
  end

  @spec close(t()) :: :ok
  def close(%__MODULE__{server_pid: server_pid}) when is_pid(server_pid) do
    if Process.alive?(server_pid) do
      GenServer.stop(server_pid)
    end

    :ok
  end

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
  def get_state(%__MODULE__{server_pid: server_pid}) when is_pid(server_pid) do
    GenServer.call(server_pid, :get_state)
  end

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

  # GenServer callbacks

  @impl true
  def init(%WebsockexNew.Config{} = config) do
    {:ok, %{config: config, gun_pid: nil, stream_ref: nil, state: :disconnected, monitor_ref: nil, url: config.url},
     {:continue, :connect}}
  end

  @impl true
  def handle_continue(:connect, %{config: config} = state) do
    case connect_with_error_handling(config) do
      {:ok, gun_pid, stream_ref, monitor_ref} ->
        # Schedule timeout check
        Process.send_after(self(), {:connection_timeout, config.timeout}, config.timeout)
        {:noreply, %{state | gun_pid: gun_pid, stream_ref: stream_ref, state: :connecting, monitor_ref: monitor_ref}}

      {:error, reason} ->
        {:noreply, %{state | state: :disconnected}, {:continue, {:connection_failed, reason}}}
    end
  end

  def handle_continue({:connection_failed, _reason}, state) do
    {:noreply, state}
  end

  @impl true
  def handle_call(:await_connection, _from, %{state: :connected} = state) do
    {:reply, {:ok, state}, state}
  end

  def handle_call(:await_connection, from, %{state: :connecting} = state) do
    {:noreply, Map.put(state, :awaiting_connection, from)}
  end

  def handle_call(:await_connection, _from, state) do
    {:reply, {:error, :connection_failed}, state}
  end

  def handle_call({:send_message, message}, _from, %{gun_pid: gun_pid, stream_ref: stream_ref, state: :connected} = state) do
    result = :gun.ws_send(gun_pid, stream_ref, {:text, message})
    {:reply, result, state}
  end

  def handle_call({:send_message, _message}, _from, %{state: conn_state} = state) do
    {:reply, {:error, {:not_connected, conn_state}}, state}
  end

  def handle_call(:get_state, _from, %{state: conn_state} = state) do
    {:reply, conn_state, state}
  end

  @impl true
  def handle_info(
        {:gun_upgrade, gun_pid, stream_ref, ["websocket"], _headers},
        %{gun_pid: gun_pid, stream_ref: stream_ref} = state
      ) do
    new_state = %{state | state: :connected}

    if Map.has_key?(state, :awaiting_connection) do
      GenServer.reply(state.awaiting_connection, {:ok, new_state})
      {:noreply, Map.delete(new_state, :awaiting_connection)}
    else
      {:noreply, new_state}
    end
  end

  def handle_info({:gun_error, gun_pid, stream_ref, reason}, %{gun_pid: gun_pid, stream_ref: stream_ref} = state) do
    handle_connection_error(state, {:gun_error, gun_pid, stream_ref, reason})
  end

  def handle_info({:gun_down, gun_pid, _, reason, _}, %{gun_pid: gun_pid} = state) do
    handle_connection_error(state, {:gun_down, gun_pid, nil, reason, nil})
  end

  def handle_info({:DOWN, ref, :process, gun_pid, reason}, %{gun_pid: gun_pid, monitor_ref: ref} = state) do
    handle_connection_error(state, {:connection_down, reason})
  end

  def handle_info({:gun_ws, gun_pid, stream_ref, _frame}, %{gun_pid: gun_pid, stream_ref: stream_ref} = state) do
    # Forward WebSocket frames to HeartbeatManager when implemented
    {:noreply, state}
  end

  def handle_info({:connection_timeout, _timeout}, %{state: :connecting} = state) do
    handle_connection_error(state, :timeout)
  end

  def handle_info({:connection_timeout, _}, state) do
    # Connection already established, ignore timeout
    {:noreply, state}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # Private functions

  @spec connect_with_error_handling(WebsockexNew.Config.t()) ::
          {:ok, pid(), reference(), reference()} | {:error, term()}
  defp connect_with_error_handling(config) do
    uri = URI.parse(config.url)
    port = uri.port || if uri.scheme == "wss", do: 443, else: 80

    case :gun.open(to_charlist(uri.host), port, %{protocols: [:http]}) do
      {:ok, gun_pid} ->
        monitor_ref = Process.monitor(gun_pid)

        case :gun.await_up(gun_pid, config.timeout) do
          {:ok, _protocol} ->
            stream_ref = :gun.ws_upgrade(gun_pid, uri.path || "/", config.headers)
            {:ok, gun_pid, stream_ref, monitor_ref}

          {:error, reason} ->
            Process.demonitor(monitor_ref, [:flush])
            :gun.close(gun_pid)
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec handle_connection_error(state(), term()) :: {:noreply, state()} | {:stop, term(), state()}
  defp handle_connection_error(state, reason) do
    if Map.has_key?(state, :awaiting_connection) do
      GenServer.reply(state.awaiting_connection, {:error, reason})
    end

    case WebsockexNew.ErrorHandler.handle_error(reason) do
      :reconnect ->
        # TODO: Trigger reconnection via Reconnection module
        {:noreply, Map.delete(%{state | state: :disconnected}, :awaiting_connection)}

      _ ->
        {:stop, reason, state}
    end
  end

  @spec build_client_struct(state(), pid()) :: t()
  defp build_client_struct(state, server_pid) do
    %__MODULE__{
      gun_pid: state.gun_pid,
      stream_ref: state.stream_ref,
      state: state.state,
      url: state.url,
      monitor_ref: state.monitor_ref,
      server_pid: server_pid
    }
  end
end
