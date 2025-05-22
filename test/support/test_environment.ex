defmodule WebsockexNew.TestEnvironment do
  @moduledoc """
  Manages test environments for real API testing.
  
  Supports multiple environments and automatic health checks.
  Provides a consistent interface for testing against different
  WebSocket endpoints with environment-specific configurations.
  """

  require Logger

  @type environment :: :deribit_test | :custom_mock | :local_server | :binance_test
  
  @type config :: %{
    endpoint: String.t(),
    auth: keyword(),
    protocols: [String.t()],
    health_check: boolean(),
    timeout: pos_integer(),
    tls: boolean(),
    headers: [{String.t(), String.t()}]
  }

  @type health_status :: :healthy | :unhealthy | :unknown

  @environments %{
    deribit_test: %{
      endpoint: "wss://test.deribit.com/ws/api/v2",
      auth: [
        client_id: {:system, "DERIBIT_CLIENT_ID"},
        client_secret: {:system, "DERIBIT_CLIENT_SECRET"}
      ],
      protocols: ["wamp"],
      health_check: true,
      timeout: 10_000,
      tls: true,
      headers: []
    },
    
    binance_test: %{
      endpoint: "wss://testnet.binance.vision/ws",
      auth: [],
      protocols: [],
      health_check: true,
      timeout: 5_000,
      tls: true,
      headers: []
    },
    
    custom_mock: %{
      endpoint: nil,  # Will be set dynamically
      auth: [],
      protocols: [],
      health_check: false,
      timeout: 5_000,
      tls: false,
      headers: []
    },
    
    local_server: %{
      endpoint: nil,  # Will be set dynamically
      auth: [],
      protocols: [],
      health_check: false,
      timeout: 2_000,
      tls: false,
      headers: []
    }
  }

  @doc """
  Sets up a test environment with the specified configuration.
  
  For dynamic environments (custom_mock, local_server), starts the server
  and updates the endpoint configuration.
  
  ## Options
  - `:force_setup` - Force setup even if environment is already configured
  - `:skip_health_check` - Skip health check even if normally required
  - `:server_opts` - Options to pass to server startup (for dynamic environments)
  """
  @spec setup_environment(environment(), keyword()) :: {:ok, config()} | {:error, term()}
  def setup_environment(environment, opts \\ [])

  def setup_environment(:custom_mock, opts) do
    server_opts = Keyword.get(opts, :server_opts, [])
    
    case WebsockexNew.MockWebSockServer.start_server(server_opts) do
      {:ok, port} ->
        base_config = @environments[:custom_mock]
        config = %{base_config | endpoint: "ws://localhost:#{port}/ws"}
        
        if Keyword.get(opts, :skip_health_check, false) do
          {:ok, config}
        else
          case health_check(config) do
            :ok -> {:ok, config}
            {:error, reason} -> {:error, {:health_check_failed, reason}}
          end
        end
      
      {:error, reason} ->
        {:error, {:server_start_failed, reason}}
    end
  end

  def setup_environment(:local_server, opts) do
    server_opts = Keyword.get(opts, :server_opts, [])
    
    case WebsockexNew.ConfigurableTestServer.start_server(server_opts) do
      {:ok, port} ->
        base_config = @environments[:local_server]
        config = %{base_config | endpoint: "ws://localhost:#{port}/ws"}
        
        if Keyword.get(opts, :skip_health_check, false) do
          {:ok, config}
        else
          case health_check(config) do
            :ok -> {:ok, config}
            {:error, reason} -> {:error, {:health_check_failed, reason}}
          end
        end
      
      {:error, reason} ->
        {:error, {:server_start_failed, reason}}
    end
  end

  def setup_environment(environment, opts) when environment in [:deribit_test, :binance_test] do
    base_config = @environments[environment]
    
    # Resolve environment variables
    case resolve_auth_config(base_config.auth) do
      {:ok, resolved_auth} ->
        config = %{base_config | auth: resolved_auth}
        
        skip_health = Keyword.get(opts, :skip_health_check, false)
        if config.health_check and not skip_health do
          case health_check(config) do
            :ok -> {:ok, config}
            {:error, reason} -> {:error, {:health_check_failed, reason}}
          end
        else
          {:ok, config}
        end
      
      {:error, reason} ->
        {:error, {:auth_config_failed, reason}}
    end
  end

  def setup_environment(environment, _opts) do
    {:error, {:unknown_environment, environment}}
  end

  @doc """
  Tears down a test environment, cleaning up any resources.
  """
  @spec teardown_environment(config()) :: :ok
  def teardown_environment(config) do
    case extract_port_from_endpoint(config.endpoint) do
      {:ok, port} when is_integer(port) ->
        # Try to stop local servers
        WebsockexNew.MockWebSockServer.stop_server(port)
        WebsockexNew.ConfigurableTestServer.stop_server(port)
        :ok
      
      _ ->
        # External endpoint, nothing to clean up
        :ok
    end
  end

  @doc """
  Performs a health check on the specified environment configuration.
  """
  @spec health_check(config()) :: :ok | {:error, term()}
  def health_check(config) do
    Logger.debug("Performing health check for #{config.endpoint}")
    
    # Create a minimal client configuration
    client_config = %WebsockexNew.Config{
      uri: config.endpoint,
      protocols: config.protocols,
      headers: config.headers,
      connect_timeout: config.timeout
    }
    
    # Attempt connection
    case WebsockexNew.Client.connect(client_config) do
      {:ok, client} ->
        # Connection successful, clean up
        WebsockexNew.Client.close(client)
        Logger.debug("Health check passed for #{config.endpoint}")
        :ok
      
      {:error, reason} ->
        Logger.warning("Health check failed for #{config.endpoint}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Gets the health status of all configured environments.
  """
  @spec health_check_all() :: %{environment() => health_status()}
  def health_check_all do
    @environments
    |> Map.keys()
    |> Enum.filter(fn env -> env not in [:custom_mock, :local_server] end)
    |> Enum.map(fn env ->
      case setup_environment(env, skip_health_check: true) do
        {:ok, config} ->
          status = case health_check(config) do
            :ok -> :healthy
            {:error, _} -> :unhealthy
          end
          {env, status}
        
        {:error, _} ->
          {env, :unknown}
      end
    end)
    |> Map.new()
  end

  @doc """
  Lists all available test environments.
  """
  @spec list_environments() :: [environment()]
  def list_environments do
    Map.keys(@environments)
  end

  @doc """
  Gets the default configuration for an environment.
  """
  @spec get_environment_config(environment()) :: {:ok, map()} | {:error, :not_found}
  def get_environment_config(environment) do
    case Map.get(@environments, environment) do
      nil -> {:error, :not_found}
      config -> {:ok, config}
    end
  end

  # Private functions

  defp resolve_auth_config(auth_config) do
    resolved = Enum.reduce_while(auth_config, [], fn
      {key, {:system, env_var}}, acc ->
        case System.get_env(env_var) do
          nil ->
            {:halt, {:error, {:missing_env_var, env_var}}}
          
          value ->
            {:cont, [{key, value} | acc]}
        end
      
      {key, value}, acc ->
        {:cont, [{key, value} | acc]}
    end)
    
    case resolved do
      {:error, reason} -> {:error, reason}
      auth_list -> {:ok, Enum.reverse(auth_list)}
    end
  end

  defp extract_port_from_endpoint(endpoint) when is_binary(endpoint) do
    case URI.parse(endpoint) do
      %URI{port: port} when is_integer(port) ->
        {:ok, port}
      
      %URI{host: "localhost", path: path} ->
        # Try to extract port from path or host
        case Regex.run(~r/:(\d+)/, endpoint) do
          [_, port_str] ->
            case Integer.parse(port_str) do
              {port, ""} -> {:ok, port}
              _ -> {:error, :invalid_port}
            end
          
          nil ->
            {:error, :no_port_found}
        end
      
      _ ->
        {:error, :external_endpoint}
    end
  end

  defp extract_port_from_endpoint(_), do: {:error, :invalid_endpoint}
end