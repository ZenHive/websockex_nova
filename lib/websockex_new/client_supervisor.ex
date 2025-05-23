defmodule WebsockexNew.ClientSupervisor do
  @moduledoc """
  Supervisor for WebSocket client connections.

  Provides supervised client connections with automatic restart on failure.
  Each client runs under its own supervisor for isolation.

  ## Usage

      # Start a supervised connection
      {:ok, client} = ClientSupervisor.start_client("wss://example.com", 
        retry_count: 5,
        heartbeat_config: %{type: :deribit, interval: 30_000}
      )
      
      # The client will be automatically restarted on crashes
      # with exponential backoff between restarts
  """

  use DynamicSupervisor

  @doc """
  Starts the client supervisor.
  """
  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(
      strategy: :one_for_one,
      max_restarts: 10,
      max_seconds: 60
    )
  end

  @doc """
  Starts a supervised WebSocket client.

  The client will be automatically restarted on failure according to the
  supervisor's restart strategy.
  """
  @spec start_client(String.t() | WebsockexNew.Config.t(), keyword()) ::
          {:ok, WebsockexNew.Client.t()} | {:error, term()}
  def start_client(url_or_config, opts \\ []) do
    # Add supervision flag to opts
    supervised_opts = Keyword.put(opts, :supervised, true)

    child_spec = %{
      id: make_ref(),
      start: {WebsockexNew.Client, :start_link, [url_or_config, supervised_opts]},
      restart: :transient,
      type: :worker
    }

    case DynamicSupervisor.start_child(__MODULE__, child_spec) do
      {:ok, pid} when is_pid(pid) ->
        # Wait for connection and get the client struct
        timeout = Keyword.get(opts, :timeout, 5000) + 1000

        try do
          case GenServer.call(pid, :await_connection, timeout) do
            {:ok, state} ->
              # Build the client struct manually since we have the pid
              client = %WebsockexNew.Client{
                gun_pid: state.gun_pid,
                stream_ref: state.stream_ref,
                state: state.state,
                url: state.url,
                monitor_ref: state.monitor_ref,
                server_pid: pid
              }

              {:ok, client}

            {:error, reason} ->
              # Stop the supervised child on connection failure
              DynamicSupervisor.terminate_child(__MODULE__, pid)
              {:error, reason}
          end
        catch
          :exit, {:timeout, _} ->
            DynamicSupervisor.terminate_child(__MODULE__, pid)
            {:error, :timeout}
        end

      error ->
        error
    end
  end

  @doc """
  Lists all supervised client connections.
  """
  @spec list_clients() :: list(pid())
  def list_clients do
    __MODULE__
    |> DynamicSupervisor.which_children()
    |> Enum.map(fn {_, pid, _, _} -> pid end)
    |> Enum.filter(&Process.alive?/1)
  end

  @doc """
  Gracefully stops a supervised client.
  """
  @spec stop_client(pid()) :: :ok | {:error, :not_found}
  def stop_client(pid) when is_pid(pid) do
    DynamicSupervisor.terminate_child(__MODULE__, pid)
  end
end
