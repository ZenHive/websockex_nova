defmodule WebSockexNova.Gun.ClientSupervisor do
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

  use Supervisor
  require Logger

  # Default values for supervisor configuration
  @default_config [
    max_restarts: 3,
    max_seconds: 5,
    strategy: :one_for_one
  ]

  @doc """
  Starts the Gun client supervisor.

  ## Options

  * `:name` - Name to register the supervisor process as
  * `:strategy` - Supervisor restart strategy
  * `:max_restarts` - Maximum number of restarts allowed in a timeframe
  * `:max_seconds` - Timeframe for restart limit in seconds

  ## Examples

      {:ok, pid} = WebSockexNova.Gun.ClientSupervisor.start_link()

      {:ok, pid} = WebSockexNova.Gun.ClientSupervisor.start_link(
        name: :my_gun_supervisor,
        strategy: :one_for_one,
        max_restarts: 5,
        max_seconds: 10
      )
  """
  def start_link(opts \\ []) do
    # Merge provided options with application config and defaults
    app_config = Application.get_env(:websockex_nova, :gun_client_supervisor, [])

    # Start the supervisor with merged options
    Supervisor.start_link(
      __MODULE__,
      Keyword.merge(@default_config, Keyword.merge(app_config, opts)),
      name: opts[:name]
    )
  end

  @impl true
  def init(opts) do
    # Extract supervisor options from the merged config
    supervisor_flags = [
      strategy: opts[:strategy] || :one_for_one,
      max_restarts: opts[:max_restarts] || 3,
      max_seconds: opts[:max_seconds] || 5
    ]

    # Start with an empty list of children
    children = []

    # Initialize the supervisor with the extracted flags and children
    Supervisor.init(children, supervisor_flags)
  end

  @doc """
  Starts a new Gun client under this supervisor.

  ## Options

  * `:name` - Optional name to register the client process
  * `:host` - The hostname to connect to (required)
  * `:port` - The port to connect to (required)
  * `:transport` - Transport protocol (`:tcp` or `:tls`, default: `:tcp`)
  * `:transport_opts` - Options for the transport protocol
  * `:protocols` - Protocols to negotiate (`[http | http2 | socks | ws]`)
  * `:retry` - Retry configuration for failed connections
  * `:websocket_path` - Path for WebSocket upgrade (default: `"/"`)

  ## Examples

      {:ok, client} = WebSockexNova.Gun.ClientSupervisor.start_client(
        supervisor_pid,
        host: "echo.websocket.org",
        port: 443,
        transport: :tls,
        websocket_path: "/echo"
      )
  """
  def start_client(supervisor, opts) do
    # Validate required options
    unless Keyword.has_key?(opts, :host) and Keyword.has_key?(opts, :port) do
      raise ArgumentError, "Both :host and :port are required options"
    end

    # Extract client options
    client_opts = %{
      host: opts[:host],
      port: opts[:port],
      transport: opts[:transport] || :tcp,
      transport_opts: opts[:transport_opts] || [],
      protocols: opts[:protocols] || [:http],
      retry: opts[:retry] || 5,
      websocket_path: opts[:websocket_path] || "/"
    }

    # Define a child spec for the Gun client
    client_spec = generate_client_spec(client_opts, opts[:name])

    # Start the child and return the result
    Supervisor.start_child(supervisor, client_spec)
  end

  @doc """
  Terminates a Gun client that was previously started by this supervisor.

  ## Examples

      :ok = WebSockexNova.Gun.ClientSupervisor.terminate_client(supervisor_pid, client_pid)
  """
  def terminate_client(supervisor, client_pid) when is_pid(client_pid) do
    Supervisor.terminate_child(supervisor, client_pid)
  end

  def terminate_client(supervisor, client_name) when is_atom(client_name) do
    if pid = Process.whereis(client_name) do
      terminate_client(supervisor, pid)
    else
      {:error, :not_found}
    end
  end

  @doc """
  Lists all Gun clients currently supervised by this supervisor.

  ## Examples

      clients = WebSockexNova.Gun.ClientSupervisor.list_clients(supervisor_pid)
  """
  def list_clients(supervisor) do
    Supervisor.which_children(supervisor)
  end

  @doc """
  Returns a child specification for starting this supervisor under another supervisor.

  ## Examples

      children = [
        WebSockexNova.Gun.ClientSupervisor.child_spec([])
      ]
  """
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :supervisor,
      restart: :permanent,
      shutdown: 5000
    }
  end

  # Private function to generate a child spec for a Gun client
  defp generate_client_spec(client_opts, name) do
    # This function would generate a child spec for a Gun connection process
    # In the actual implementation, we'll manage the Gun connection process lifecycle
    # For now, we'll create a dummy GenServer to simulate the Gun client
    # In the T2.3 and T2.4 tasks, we'll implement the actual Gun connection wrapper

    %{
      id: make_ref(),
      start: {WebSockexNova.Gun.DummyClient, :start_link, [client_opts, name]},
      restart: :transient,
      shutdown: 5000,
      type: :worker
    }
  end
end
