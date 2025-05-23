defmodule WebsockexNew.Client do
  @moduledoc """
  WebSocket client GenServer using Gun as transport layer.

  ## Overview

  The Client module is implemented as a GenServer to handle asynchronous Gun messages.
  Gun sends all WebSocket messages to the process that opens the connection, so the
  Client GenServer owns the Gun connection to receive these messages directly.

  ## Public API

  Despite being a GenServer internally, the public API returns struct-based responses
  for backward compatibility:

      {:ok, client} = Client.connect("wss://example.com")
      # client is a struct with gun_pid, stream_ref, and server_pid fields
      
      :ok = Client.send_message(client, "hello")
      Client.close(client)

  ## Connection Ownership and Reconnection

  ### Initial Connection
  When you call `connect/2`, a new Client GenServer is started which:
  1. Opens a Gun connection from within the GenServer 
  2. Receives all Gun messages (gun_ws, gun_up, gun_down, etc.)
  3. Returns a client struct containing the GenServer PID

  ### Automatic Reconnection
  On connection failure, the Client GenServer:
  1. Detects the failure via process monitoring
  2. Cleans up the old Gun connection
  3. Opens a new Gun connection from the same GenServer process
  4. Maintains Gun message ownership continuity
  5. Preserves the same Client GenServer PID throughout

  This ensures that components like HeartbeatManager continue to work seamlessly
  across reconnections without needing to track connection changes.

  The Client GenServer handles all reconnection logic internally to maintain
  Gun message ownership throughout the connection lifecycle.

  ## Core Functions
  - connect/2 - Establish connection
  - send_message/2 - Send messages  
  - close/1 - Close connection
  - subscribe/2 - Subscribe to channels
  - get_state/1 - Get connection state

  ## Configuration Options

  The `connect/2` function accepts all options from `WebsockexNew.Config`:

      # Customize reconnection behavior
      {:ok, client} = Client.connect("wss://example.com",
        retry_count: 5,              # Try reconnecting 5 times
        retry_delay: 2000,           # Start with 2 second delay
        max_backoff: 60_000,         # Cap backoff at 1 minute
        reconnect_on_error: true     # Auto-reconnect on errors
      )

      # Disable auto-reconnection for critical operations
      {:ok, client} = Client.connect("wss://example.com",
        reconnect_on_error: false
      )

  See `WebsockexNew.Config` for all available options.
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
    case WebsockexNew.Reconnection.establish_connection(config) do
      {:ok, gun_pid, stream_ref, monitor_ref} ->
        # Gun will send all messages to this GenServer process (self())
        # because we opened the connection from this process

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

  @doc false
  def handle_continue(:reconnect, %{config: config} = state) do
    # Reconnect from within the GenServer to maintain Gun ownership
    # This ensures the new Gun connection sends messages to this GenServer
    case WebsockexNew.Reconnection.establish_connection(config) do
      {:ok, gun_pid, stream_ref, monitor_ref} ->
        # New Gun connection will send messages to this GenServer
        Process.send_after(self(), {:connection_timeout, config.timeout}, config.timeout)
        {:noreply, %{state | gun_pid: gun_pid, stream_ref: stream_ref, state: :connecting, monitor_ref: monitor_ref}}

      {:error, _reason} ->
        # Schedule retry with exponential backoff
        current_attempt = Map.get(state, :retry_count, 0)

        retry_delay =
          WebsockexNew.Reconnection.calculate_backoff(
            current_attempt,
            config.retry_delay,
            config.max_backoff
          )

        Process.send_after(self(), :retry_reconnect, retry_delay)
        {:noreply, %{state | state: :disconnected, retry_count: current_attempt + 1}}
    end
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
    # TODO: Forward WebSocket frames to HeartbeatManager when implemented
    # Gun sends these messages to us because we own the connection
    {:noreply, state}
  end

  def handle_info({:connection_timeout, _timeout}, %{state: :connecting} = state) do
    handle_connection_error(state, :timeout)
  end

  def handle_info({:connection_timeout, _}, state) do
    # Connection already established, ignore timeout
    {:noreply, state}
  end

  @doc false
  # Handles scheduled reconnection retry with exponential backoff
  def handle_info(:retry_reconnect, %{config: config} = state) do
    current_retries = Map.get(state, :retry_count, 0)

    if WebsockexNew.Reconnection.max_retries_exceeded?(current_retries, config.retry_count) do
      {:stop, :max_reconnection_attempts, state}
    else
      {:noreply, state, {:continue, :reconnect}}
    end
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # Private functions

  # Handles connection errors and triggers internal reconnection when appropriate.
  # This maintains Gun ownership by reconnecting from within the same GenServer.
  @spec handle_connection_error(state(), term()) :: {:noreply, state()} | {:stop, term(), state()}
  defp handle_connection_error(state, reason) do
    if Map.has_key?(state, :awaiting_connection) do
      GenServer.reply(state.awaiting_connection, {:error, reason})
    end

    if state.config.reconnect_on_error && WebsockexNew.Reconnection.should_reconnect?(reason) do
      # Clean up old connection
      if state.monitor_ref do
        Process.demonitor(state.monitor_ref, [:flush])
      end

      # Trigger reconnection from this GenServer to maintain ownership
      new_state = %{state | gun_pid: nil, stream_ref: nil, state: :disconnected, monitor_ref: nil}
      {:noreply, Map.delete(new_state, :awaiting_connection), {:continue, :reconnect}}
    else
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
