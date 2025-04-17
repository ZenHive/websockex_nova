defmodule WebSockexNova.Gun.ConnectionWrapper do
  @moduledoc """
  Wraps the Gun WebSocket connection functionality, providing a simplified interface.

  This module abstracts away the complexity of dealing with Gun directly, offering
  functions for connecting, upgrading to WebSocket, sending frames, and processing messages.

  It uses a structured state management approach and modular message handlers to improve
  maintainability and testability.
  """

  use GenServer
  require Logger

  alias WebSockexNova.Gun.ConnectionState
  alias WebSockexNova.Gun.ConnectionWrapper.MessageHandlers

  @typedoc "Connection status"
  @type status :: :initialized | :connected | :disconnected | :websocket_connected | :error

  @typedoc "WebSocket frame types"
  @type frame ::
          {:text, binary}
          | {:binary, binary}
          | :ping
          | :pong
          | :close
          | {:close, non_neg_integer(), binary}

  @typedoc "Options for connection wrapper"
  @type options :: %{
          optional(:transport) => :tcp | :tls,
          optional(:transport_opts) => Keyword.t(),
          optional(:protocols) => [:http | :http2 | :socks | :ws],
          optional(:retry) => non_neg_integer() | :infinity,
          optional(:callback_pid) => pid(),
          optional(:ws_opts) => map(),
          optional(:test_mode) => boolean()
        }

  @default_options %{
    transport: :tcp,
    transport_opts: [],
    protocols: [:http],
    retry: 5,
    ws_opts: %{},
    test_mode: false
  }

  # Client API

  @doc """
  Opens a connection to a WebSocket server.

  ## Parameters

  * `host` - Hostname or IP address of the server
  * `port` - Port number of the server (default: 80, or 443 for TLS)
  * `options` - Connection options (see `t:options/0`)
  * `supervisor` - Optional Gun client supervisor PID

  ## Options

  * `:transport` - Transport protocol (`:tcp` or `:tls`, default: `:tcp`)
  * `:transport_opts` - Options for the transport protocol
  * `:protocols` - Protocols to negotiate (`[:http | :http2 | :socks | :ws]`)
  * `:retry` - Number of times to retry connection (default: 5)
  * `:callback_pid` - Process to send WebSocket messages to
  * `:ws_opts` - WebSocket-specific options
  * `:test_mode` - Whether to operate in test mode (default: false)

  ## Returns

  * `{:ok, pid}` on success
  * `{:error, reason}` on failure
  """
  @spec open(binary(), pos_integer(), options(), pid() | nil) :: {:ok, pid()} | {:error, term()}
  def open(host, port, options \\ %{}, supervisor \\ nil) do
    GenServer.start_link(__MODULE__, {host, port, options, supervisor})
  end

  @doc """
  Closes a WebSocket connection.

  ## Parameters

  * `pid` - The connection wrapper PID

  ## Returns

  * `:ok`
  """
  @spec close(pid()) :: :ok
  def close(pid) do
    GenServer.cast(pid, :close)
  end

  @doc """
  Upgrades an HTTP connection to WebSocket.

  ## Parameters

  * `pid` - The connection wrapper PID
  * `path` - The WebSocket endpoint path
  * `headers` - Additional headers for the upgrade request

  ## Returns

  * `{:ok, reference()}` on success
  * `{:error, reason}` on failure
  """
  @spec upgrade_to_websocket(pid(), binary(), Keyword.t()) ::
          {:ok, reference()} | {:error, term()}
  def upgrade_to_websocket(pid, path, headers \\ []) do
    GenServer.call(pid, {:upgrade_to_websocket, path, headers})
  end

  @doc """
  Sends a WebSocket frame.

  ## Parameters

  * `pid` - The connection wrapper PID
  * `stream_ref` - The stream reference from the upgrade
  * `frame` - WebSocket frame to send

  ## Returns

  * `:ok` on success
  * `{:error, reason}` on failure
  """
  @spec send_frame(pid(), reference(), frame() | [frame()]) :: :ok | {:error, term()}
  def send_frame(pid, stream_ref, frame) do
    GenServer.call(pid, {:send_frame, stream_ref, frame})
  end

  @doc """
  Process a Gun message.

  ## Parameters

  * `pid` - The connection wrapper PID
  * `message` - The Gun message to process

  ## Returns

  * `:ok`
  """
  @spec process_gun_message(pid(), tuple()) :: :ok
  def process_gun_message(pid, message) do
    GenServer.cast(pid, {:process_gun_message, message})
  end

  @doc """
  Gets the current state of the connection wrapper.

  ## Parameters

  * `pid` - The connection wrapper PID

  ## Returns

  The current state of the connection wrapper.
  """
  @spec get_state(pid()) :: ConnectionState.t()
  def get_state(pid) do
    GenServer.call(pid, :get_state)
  end

  @doc """
  Sets the connection status (mainly for testing).

  ## Parameters

  * `pid` - The connection wrapper PID
  * `status` - The new status to set

  ## Returns

  * `:ok`
  """
  @spec set_status(pid(), status()) :: :ok
  def set_status(pid, status) do
    GenServer.cast(pid, {:set_status, status})
  end

  # Server callbacks

  @impl true
  def init({host, port, options, _supervisor}) do
    merged_options = Map.merge(@default_options, options)
    state = ConnectionState.new(host, port, merged_options)

    if state.options.test_mode do
      # In test mode, don't actually try to establish a connection
      {:ok, state}
    else
      # Start Gun connection
      case open_connection(state) do
        {:ok, gun_pid} ->
          {:ok, ConnectionState.update_gun_pid(state, gun_pid)}

        {:error, reason} ->
          Logger.error("Failed to open Gun connection: #{inspect(reason)}")

          state =
            state
            |> ConnectionState.update_status(:error)
            |> ConnectionState.record_error(reason)

          {:ok, state}
      end
    end
  end

  @impl true
  def handle_call({:upgrade_to_websocket, path, headers}, _from, state) do
    if state.options.test_mode || (state.gun_pid && state.status == :connected) do
      stream_ref =
        if state.options.test_mode,
          do: make_ref(),
          else:
            :gun.ws_upgrade(
              state.gun_pid,
              path,
              headers_to_gun_format(headers),
              state.options.ws_opts
            )

      # Track the stream
      state = ConnectionState.update_stream(state, stream_ref, :upgrading)

      {:reply, {:ok, stream_ref}, state}
    else
      {:reply, {:error, :not_connected}, state}
    end
  end

  def handle_call({:send_frame, stream_ref, frame}, _from, state) do
    if state.options.test_mode || state.gun_pid do
      if state.options.test_mode do
        # In test mode, just pretend it worked
        {:reply, :ok, state}
      else
        # In normal mode, check the stream status
        case Map.get(state.active_streams, stream_ref) do
          :websocket ->
            # Send frame via Gun
            result = :gun.ws_send(state.gun_pid, stream_ref, frame)
            {:reply, result, state}

          nil ->
            {:reply, {:error, :stream_not_found}, state}

          status ->
            {:reply, {:error, {:invalid_stream_status, status}}, state}
        end
      end
    else
      {:reply, {:error, :not_connected}, state}
    end
  end

  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_cast({:process_gun_message, message}, state) do
    handle_gun_message(message, state)
  end

  def handle_cast(:close, state) do
    # Close Gun connection if it exists
    if state.gun_pid do
      :gun.close(state.gun_pid)
    end

    # Terminate the GenServer
    {:stop, :normal, state}
  end

  def handle_cast({:set_status, status}, state) do
    {:noreply, ConnectionState.update_status(state, status)}
  end

  @impl true
  def handle_info({:gun_up, gun_pid, protocol}, %{gun_pid: gun_pid} = state) do
    MessageHandlers.handle_connection_up(gun_pid, protocol, state)
  end

  def handle_info(
        {:gun_down, gun_pid, protocol, reason, _killed_streams, _unprocessed_streams},
        %{gun_pid: gun_pid} = state
      ) do
    MessageHandlers.handle_connection_down(gun_pid, protocol, reason, state)
  end

  def handle_info(
        {:gun_upgrade, gun_pid, stream_ref, ["websocket"], headers},
        %{gun_pid: gun_pid} = state
      ) do
    MessageHandlers.handle_websocket_upgrade(gun_pid, stream_ref, headers, state)
  end

  def handle_info({:gun_ws, gun_pid, stream_ref, frame}, %{gun_pid: gun_pid} = state) do
    MessageHandlers.handle_websocket_frame(gun_pid, stream_ref, frame, state)
  end

  def handle_info({:gun_error, gun_pid, stream_ref, reason}, %{gun_pid: gun_pid} = state) do
    MessageHandlers.handle_error(gun_pid, stream_ref, reason, state)
  end

  def handle_info(
        {:gun_response, gun_pid, stream_ref, is_fin, status, headers},
        %{gun_pid: gun_pid} = state
      ) do
    MessageHandlers.handle_http_response(gun_pid, stream_ref, is_fin, status, headers, state)
  end

  def handle_info({:gun_data, gun_pid, stream_ref, is_fin, data}, %{gun_pid: gun_pid} = state) do
    MessageHandlers.handle_http_data(gun_pid, stream_ref, is_fin, data, state)
  end

  def handle_info(other, state) do
    Logger.debug("Unhandled message: #{inspect(other)}")
    {:noreply, state}
  end

  # Private functions

  defp handle_gun_message({:gun_up, pid, protocol}, state) do
    MessageHandlers.handle_connection_up(pid, protocol, state)
  end

  defp handle_gun_message(
         {:gun_down, pid, protocol, reason, _killed_streams, _unprocessed_streams},
         state
       ) do
    MessageHandlers.handle_connection_down(pid, protocol, reason, state)
  end

  defp handle_gun_message({:gun_upgrade, pid, stream_ref, ["websocket"], headers}, state) do
    MessageHandlers.handle_websocket_upgrade(pid, stream_ref, headers, state)
  end

  defp handle_gun_message({:gun_ws, pid, stream_ref, frame}, state) do
    MessageHandlers.handle_websocket_frame(pid, stream_ref, frame, state)
  end

  defp handle_gun_message({:gun_error, pid, stream_ref, reason}, state) do
    MessageHandlers.handle_error(pid, stream_ref, reason, state)
  end

  defp handle_gun_message(
         {:gun_response, pid, stream_ref, is_fin, status, headers},
         state
       ) do
    MessageHandlers.handle_http_response(pid, stream_ref, is_fin, status, headers, state)
  end

  defp handle_gun_message({:gun_data, pid, stream_ref, is_fin, data}, state) do
    MessageHandlers.handle_http_data(pid, stream_ref, is_fin, data, state)
  end

  defp handle_gun_message(_message, state) do
    # Unhandled message
    {:noreply, state}
  end

  defp open_connection(state) do
    # Convert options from map to keyword list for gun
    gun_opts =
      %{}
      |> Map.put(:transport, state.options.transport)
      |> Map.put(:protocols, state.options.protocols)
      |> Map.put(:retry, state.options.retry)

    # Add transport_opts only if they're not empty
    gun_opts =
      if Enum.empty?(state.options.transport_opts) do
        gun_opts
      else
        Map.put(gun_opts, :transport_opts, state.options.transport_opts)
      end

    # Try to open Gun connection
    host_charlist = String.to_charlist(state.host)

    case :gun.open(host_charlist, state.port, gun_opts) do
      {:ok, pid} ->
        Logger.debug("Gun connection opened to #{state.host}:#{state.port}")

        # Wait for connection to be established
        case :gun.await_up(pid, 5000) do
          {:ok, _protocol} ->
            {:ok, pid}

          {:error, reason} ->
            :gun.close(pid)
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp headers_to_gun_format(headers) do
    Enum.map(headers, fn
      {key, value} when is_binary(key) -> {key, to_string(value)}
      {key, value} when is_atom(key) -> {to_string(key), to_string(value)}
      other -> other
    end)
  end
end
