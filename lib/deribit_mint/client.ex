defmodule DeribitMint.Client do
  @moduledoc """
  Persistent Deribit WebSocket client with automatic heartbeat and test_request handling.
  """

  use GenServer

  require Logger

  @default_heartbeat 30
  @default_scheme :https
  @default_host "test.deribit.com"
  @default_port 443
  @default_path "/ws/api/v2"
  @jsonrpc_version "2.0"

  defmodule State do
    @moduledoc false
    defstruct [
      :scheme,
      :host,
      :port,
      :path,
      :client_id,
      :client_secret,
      :heartbeat,
      :conn,
      :ws,
      :ref,
      :access_token,
      :authenticated,
      :last_heartbeat,
      :awaiting_test_response
    ]
  end

  # Public API

  @doc """
  Start the persistent Deribit client.
  Options: :heartbeat, :client_id, :client_secret, :scheme, :host, :port, :path
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Send a JSON-RPC request over the persistent connection.
  Returns {:ok, result} or {:error, reason}.
  """
  def call(method, params \\ %{}, timeout \\ 5_000) do
    GenServer.call(__MODULE__, {:call, method, params}, timeout)
  end

  @doc """
  Get the current connection and heartbeat status.
  """
  def status do
    GenServer.call(__MODULE__, :status)
  end

  @doc """
  Get the full current state struct of the DeribitMint persistent client.
  """
  def get_state do
    GenServer.call(__MODULE__, :get_state)
  end

  # GenServer callbacks

  @impl true
  def init(opts) do
    state = %State{
      scheme: Keyword.get(opts, :scheme, @default_scheme),
      host: Keyword.get(opts, :host, @default_host),
      port: Keyword.get(opts, :port, @default_port),
      path: Keyword.get(opts, :path, @default_path),
      client_id: Keyword.get(opts, :client_id, client_id()),
      client_secret: Keyword.get(opts, :client_secret, client_secret()),
      heartbeat: Keyword.get(opts, :heartbeat, @default_heartbeat),
      conn: nil,
      ws: nil,
      ref: nil,
      access_token: nil,
      authenticated: false,
      last_heartbeat: nil,
      awaiting_test_response: false
    }

    send(self(), :connect)
    {:ok, state}
  end

  @impl true
  def handle_info(:connect, state) do
    Logger.info("Connecting to Deribit WebSocket...")

    with {:ok, conn} <- Mint.HTTP.connect(state.scheme, state.host, state.port, []),
         {:ok, conn, ref} <- Mint.WebSocket.upgrade(:wss, conn, state.path, []),
         {:ok, conn, responses} <- await_upgrade(conn, ref, 5_000),
         {:ok, conn, ws} <- websocket_from_upgrade(conn, ref, responses) do
      Logger.info("WebSocket upgrade successful. Authenticating...")
      # Authenticate if credentials are present
      if state.client_id && state.client_secret do
        auth_msg =
          jsonrpc_request(
            "public/auth",
            %{
              "grant_type" => "client_credentials",
              "client_id" => state.client_id,
              "client_secret" => state.client_secret
            },
            1
          )

        {:ok, ws, data} = Mint.WebSocket.encode(ws, {:text, auth_msg})
        {:ok, conn} = Mint.WebSocket.stream_request_body(conn, ref, data)
        {:noreply, %{state | conn: conn, ws: ws, ref: ref}}
      else
        # No auth, proceed to set heartbeat
        send(self(), :set_heartbeat)
        {:noreply, %{state | conn: conn, ws: ws, ref: ref}}
      end
    else
      error ->
        Logger.error("WebSocket connection failed: #{inspect(error)}. Retrying in 5s...")
        Process.send_after(self(), :connect, 5_000)
        {:noreply, state}
    end
  end

  @impl true
  def handle_info(:set_heartbeat, state) do
    Logger.info("Setting heartbeat interval to #{state.heartbeat}s...")
    msg = jsonrpc_request("public/set_heartbeat", %{"interval" => state.heartbeat}, 2)
    {:ok, ws, data} = Mint.WebSocket.encode(state.ws, {:text, msg})
    {:ok, conn} = Mint.WebSocket.stream_request_body(state.conn, state.ref, data)
    {:noreply, %{state | conn: conn, ws: ws, last_heartbeat: :os.system_time(:second)}}
  end

  @impl true
  def handle_info({:tcp, _port, _data} = msg, state), do: handle_ws_message(msg, state)
  @impl true
  def handle_info({:ssl, _port, _data} = msg, state), do: handle_ws_message(msg, state)
  @impl true
  def handle_info({:tcp_closed, _port}, state), do: reconnect(state)
  @impl true
  def handle_info({:ssl_closed, _port}, state), do: reconnect(state)

  defp handle_ws_message(msg, state) do
    case Mint.WebSocket.stream(state.conn, msg) do
      {:ok, conn, responses} ->
        responses
        |> Enum.reduce(%{state | conn: conn}, fn
          {:data, _ref, data}, acc_state ->
            {:ok, ws, frames} = Mint.WebSocket.decode(acc_state.ws, data)
            Enum.reduce(frames, %{acc_state | ws: ws}, &handle_frame(&1, &2))

          _, acc_state ->
            acc_state
        end)
        |> noreply_continue_recv()

      {:error, conn, reason, _responses} ->
        Logger.error("WebSocket error: #{inspect(reason)}. Reconnecting...")
        reconnect(%{state | conn: conn})
    end
  end

  defp handle_frame({:text, json}, state) do
    case Jason.decode(json) do
      {:ok, %{"method" => "heartbeat"}} ->
        Logger.debug("Received heartbeat from server.")
        %{state | last_heartbeat: :os.system_time(:second)}

      {:ok, %{"method" => "test_request", "id" => id}} ->
        Logger.info("Received test_request. Responding with public/test...")
        msg = jsonrpc_request("public/test", %{}, id)
        {:ok, ws, data} = Mint.WebSocket.encode(state.ws, {:text, msg})
        {:ok, conn} = Mint.WebSocket.stream_request_body(state.conn, state.ref, data)
        %{state | conn: conn, ws: ws}

      {:ok, %{"result" => _result, "id" => _id}} ->
        # Handle responses to our requests (could be improved to match requests)
        state

      {:ok, %{"error" => error}} ->
        Logger.error("Received error from server: #{inspect(error)}")
        state

      _ ->
        Logger.debug("Received unhandled frame: #{json}")
        state
    end
  end

  defp handle_frame(_other, state), do: state

  defp noreply_continue_recv(state) do
    # Continue receiving
    {:noreply, state}
  end

  defp reconnect(state) do
    Logger.warning("WebSocket disconnected. Reconnecting in 5s...")
    Process.send_after(self(), :connect, 5_000)
    {:noreply, %{state | conn: nil, ws: nil, ref: nil, authenticated: false}}
  end

  @impl true
  def handle_call({:call, method, params}, _from, state) do
    id = :erlang.unique_integer([:positive])
    msg = jsonrpc_request(method, params, id)
    {:ok, ws, data} = Mint.WebSocket.encode(state.ws, {:text, msg})
    {:ok, conn} = Mint.WebSocket.stream_request_body(state.conn, state.ref, data)
    # For simplicity, we don't match responses to requests in this scaffold
    {:reply, :ok, %{state | conn: conn, ws: ws}}
  end

  @impl true
  def handle_call(:status, _from, state) do
    status = %{
      connected: not is_nil(state.conn),
      last_heartbeat: state.last_heartbeat
    }

    {:reply, status, state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  # --- Internal helpers ---

  defp jsonrpc_request(method, params, id) do
    Jason.encode!(%{
      "jsonrpc" => @jsonrpc_version,
      "id" => id,
      "method" => method,
      "params" => params
    })
  end

  defp await_upgrade(conn, ref, timeout) do
    receive do
      message ->
        case Mint.WebSocket.stream(conn, message) do
          {:ok, conn, responses} ->
            if Enum.any?(responses, &match?({:done, ^ref}, &1)),
              do: {:ok, conn, responses},
              else: await_upgrade(conn, ref, timeout)

          {:error, _conn, _reason, _responses} ->
            {:error, :upgrade_failed}
        end
    after
      timeout -> {:error, :upgrade_timeout}
    end
  end

  defp websocket_from_upgrade(conn, ref, responses) do
    with {:status, ^ref, status} <- Enum.find(responses, &match?({:status, ^ref, _}, &1)),
         {:headers, ^ref, headers} <- Enum.find(responses, &match?({:headers, ^ref, _}, &1)) do
      Mint.WebSocket.new(conn, ref, status, headers)
    else
      _ -> {:error, :websocket_upgrade_failed}
    end
  end

  defp client_id do
    Application.get_env(:websockex_nova, Deribit)[:client_id]
  end

  defp client_secret do
    Application.get_env(:websockex_nova, Deribit)[:client_secret]
  end
end
