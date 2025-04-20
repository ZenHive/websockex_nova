defmodule WebsockexNova.Gun.ClientSupervisor do
  @moduledoc """
  Supervisor for Gun WebSocket client connections.

  This module supervises Gun client connections, handling their lifecycle
  and providing appropriate restart strategies when connections fail.

  ## Configuration

  The supervisor can be configured using application environment variables:

  ```elixir
  config :websockex_nova, :gun_client_supervisor,
    max_restarts: 3,           # Maximum restart attempts within timeframe
    max_seconds: 5,            # Timeframe for restart limit in seconds
    strategy: :one_for_one     # Restart strategy
  ```
  """

  use DynamicSupervisor

  alias WebsockexNova.Gun.ConnectionOptions

  require Logger

  @default_config [
    max_restarts: 3,
    max_seconds: 5,
    strategy: :one_for_one
  ]

  @type option :: [
          {:name, atom},
          {:strategy, Supervisor.strategy()},
          {:max_restarts, non_neg_integer},
          {:max_seconds, non_neg_integer}
        ]
  @type client_option :: [
          {:name, atom},
          {:host, String.t()},
          {:port, pos_integer},
          {:transport, :tcp | :tls},
          {:transport_opts, keyword},
          {:protocols, [atom]},
          {:retry, non_neg_integer},
          {:websocket_path, String.t()}
        ]

  @doc """
  Starts the Gun client supervisor.
  """
  @spec start_link(option) :: Supervisor.on_start()
  def start_link(opts \\ []) do
    merged_opts = merge_supervisor_opts(opts)
    DynamicSupervisor.start_link(__MODULE__, merged_opts, name: Keyword.get(merged_opts, :name))
  end

  @impl true
  def init(opts) do
    DynamicSupervisor.init(strategy: Keyword.get(opts, :strategy, :one_for_one))
  end

  @doc """
  Starts a new Gun client under this supervisor.
  """
  @spec start_client(pid, client_option) :: DynamicSupervisor.on_start_child()
  def start_client(supervisor, opts) when is_pid(supervisor) and is_list(opts) do
    validated_opts = validate_and_parse_client_opts(opts)
    client_spec = generate_client_spec(validated_opts, Keyword.get(opts, :name))
    DynamicSupervisor.start_child(supervisor, client_spec)
  end

  @doc """
  Terminates a Gun client that was previously started by this supervisor.
  """
  @spec terminate_client(pid, pid | atom) :: :ok | {:error, :not_found}
  def terminate_client(supervisor, client_pid) when is_pid(client_pid) do
    DynamicSupervisor.terminate_child(supervisor, client_pid)
  end

  def terminate_client(supervisor, client_name) when is_atom(client_name) do
    case Process.whereis(client_name) do
      nil -> {:error, :not_found}
      pid -> terminate_client(supervisor, pid)
    end
  end

  @doc """
  Lists all Gun clients currently supervised by this supervisor.
  """
  @spec list_clients(pid()) :: [
          {id :: term, child :: pid | :restarting | :undefined, type :: :worker | :supervisor,
           modules :: [module] | :dynamic}
        ]
  def list_clients(supervisor) do
    DynamicSupervisor.which_children(supervisor)
  end

  @doc """
  Returns a child specification for starting this supervisor under another supervisor.
  """
  @spec child_spec(option) :: Supervisor.child_spec()
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :supervisor,
      restart: :permanent,
      shutdown: 5000
    }
  end

  # Private helpers

  defp merge_supervisor_opts(opts) do
    app_config = Application.get_env(:websockex_nova, :gun_client_supervisor, [])
    Keyword.merge(@default_config, Keyword.merge(app_config, opts))
  end

  defp validate_and_parse_client_opts(opts) do
    with {:ok, host} <- fetch_required_opt(opts, :host),
         {:ok, port} <- fetch_required_opt(opts, :port) do
      client_opts = %{
        host: host,
        port: port,
        transport: Keyword.get(opts, :transport, :tcp),
        transport_opts: Keyword.get(opts, :transport_opts, []),
        protocols: Keyword.get(opts, :protocols, [:http]),
        retry: Keyword.get(opts, :retry, 5),
        websocket_path: Keyword.get(opts, :websocket_path, "/")
      }

      case ConnectionOptions.parse_and_validate(client_opts) do
        {:ok, validated_opts} -> validated_opts
        {:error, msg} -> raise ArgumentError, "Invalid Gun client options: #{msg}"
      end
    else
      {:error, key} -> raise ArgumentError, ":#{key} is a required option"
    end
  end

  defp fetch_required_opt(opts, key) do
    case Keyword.fetch(opts, key) do
      {:ok, value} -> {:ok, value}
      :error -> {:error, key}
    end
  end

  defp generate_client_spec(client_opts, name) do
    # Extract host, port, and options from client_opts
    host = Map.fetch!(client_opts, :host)
    port = Map.fetch!(client_opts, :port)
    options = Map.drop(client_opts, [:host, :port])
    args = {host, port, options, nil}

    %{
      id: make_ref(),
      start: {WebsockexNova.Gun.ConnectionWrapper, :start_link, [args]},
      restart: :transient,
      shutdown: 5000,
      type: :worker
    }
  end
end
