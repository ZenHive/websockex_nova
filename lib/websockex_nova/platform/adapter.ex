defmodule WebsockexNova.Platform.Adapter do
  @moduledoc """
  Base module for platform-specific adapters in WebsockexNova.

  This module defines a behavior and provides common functionality for all platform adapters.
  Platform adapters serve as the bridge between WebsockexNova's generic WebSocket behaviors
  and the specific requirements of different platforms (exchanges, chat services, etc.).

  ## Usage

  To create a platform adapter, use this module and implement the required callbacks:

  ```elixir
  defmodule MyApp.PlatformAdapters.Deribit do
    use WebsockexNova.Platform.Adapter,
      default_host: "wss://www.deribit.com/ws/api/v2",
      default_port: 443

    # Implement the required callbacks
  end
  ```

  ## Configuration

  When using this module, you can provide default configuration options:

  * `:default_host` - The default WebSocket host for this platform
  * `:default_port` - The default WebSocket port for this platform
  * `:default_path` - The default WebSocket path for this platform
  * `:default_timeout` - Default timeout for connections and operations

  ## Callbacks

  The adapter behavior requires several callbacks to be implemented:

  * `init/1` - Initialize the adapter with configuration options
  * `handle_platform_message/2` - Process platform-specific messages
  * `encode_auth_request/1` - Generate authentication requests
  * `encode_subscription_request/2` - Generate subscription requests
  * `encode_unsubscription_request/1` - Generate unsubscription requests

  ## Example Implementation

  ```elixir
  defmodule MyApp.PlatformAdapters.Deribit do
    use WebsockexNova.Platform.Adapter,
      default_host: "wss://www.deribit.com/ws/api/v2",
      default_port: 443

    @impl true
    def init(opts) do
      # Custom initialization logic
      {:ok, opts}
    end

    @impl true
    def handle_platform_message(message, state) do
      case message do
        %{"method" => "heartbeat"} ->
          # Handle heartbeat response
          {:noreply, state}

        %{"method" => "auth", "result" => result} ->
          # Handle authentication response
          {:ok, Map.put(state, :auth_token, result["token"])}

        _ ->
          # Handle other messages
          {:noreply, state}
      end
    end

    @impl true
    def encode_auth_request(credentials) do
      # Generate a platform-specific authentication request
      {:text, Jason.encode!(%{
        "jsonrpc" => "2.0",
        "method" => "public/auth",
        "params" => %{
          "grant_type" => "client_credentials",
          "client_id" => credentials.api_key,
          "client_secret" => credentials.api_secret
        }
      })}
    end

    @impl true
    def encode_subscription_request(channel, params) do
      # Generate a subscription request for the platform
      {:text, Jason.encode!(%{
        "jsonrpc" => "2.0",
        "method" => "public/subscribe",
        "params" => %{
          "channels" => [channel],
          "options" => params
        }
      })}
    end

    @impl true
    def encode_unsubscription_request(channel) do
      # Generate an unsubscription request
      {:text, Jason.encode!(%{
        "jsonrpc" => "2.0",
        "method" => "public/unsubscribe",
        "params" => %{
          "channels" => [channel]
        }
      })}
    end
  end
  ```
  """

  @doc """
  When used, defines a platform adapter.

  ## Options

  * `:default_host` - The default WebSocket host for this platform
  * `:default_port` - The default WebSocket port for this platform
  * `:default_path` - The default WebSocket path for this platform
  * `:default_timeout` - Default timeout for connections and operations
  """
  defmacro __using__(opts) do
    quote do
      @behaviour WebsockexNova.Platform.Adapter

      # Import default configuration options
      @default_host unquote(opts[:default_host])
      @default_port unquote(opts[:default_port])
      @default_path unquote(opts[:default_path] || "/")
      @default_timeout unquote(opts[:default_timeout] || 5000)

      # Default implementation of init - can be overridden
      @impl true
      def init(opts) do
        # Apply default configuration values
        opts =
          opts
          # Ensure opts is a map
          |> Map.new()
          |> Map.put_new(:host, @default_host)
          |> Map.put_new(:port, @default_port)
          |> Map.put_new(:path, @default_path)
          |> Map.put_new(:timeout, @default_timeout)

        {:ok, opts}
      end

      defoverridable init: 1
    end
  end

  @typedoc """
  Type representation of adapter state.
  """
  @type state :: map()

  @typedoc """
  Type for credentials used in authentication.
  """
  @type credentials :: map()

  @typedoc """
  Type for a platform-specific message.
  """
  @type platform_message :: map()

  @typedoc """
  Type for WebSocket frames (text or binary).
  """
  @type websocket_frame :: {:text, String.t()} | {:binary, binary()}

  @typedoc """
  Type for subscription parameters.
  """
  @type subscription_params :: map()

  @typedoc """
  Type for subscription channel/topic identifier.
  """
  @type channel :: String.t()

  @typedoc """
  Type for adapter error information.
  """
  @type error_info :: map()

  @doc """
  Initializes the platform adapter with configuration options.

  This callback should validate and prepare the configuration,
  returning the initial adapter state.

  ## Parameters

  * `opts` - The configuration options map

  ## Returns

  * `{:ok, state}` - The initialized state
  * `{:error, reason}` - If initialization fails
  """
  @callback init(opts :: map()) :: {:ok, state()} | {:error, term()}

  @doc """
  Handles platform-specific messages.

  This callback is responsible for processing messages specific to the
  platform and determining the appropriate action to take.

  ## Parameters

  * `message` - The platform-specific message (typically a decoded JSON map)
  * `state` - The current adapter state

  ## Returns

  * `{:ok, state}` - Message processed successfully without a reply
  * `{:reply, websocket_frame(), state}` - Reply with a frame and update state
  * `{:error, error_info, state}` - An error occurred during processing
  * `{:noreply, state}` - No response needed, just update state
  """
  @callback handle_platform_message(message :: platform_message(), state :: state()) ::
              {:ok, state()}
              | {:reply, websocket_frame(), state()}
              | {:error, error_info(), state()}
              | {:noreply, state()}

  @doc """
  Encodes an authentication request for the platform.

  This callback should generate a properly formatted WebSocket frame
  that authenticates with the platform.

  ## Parameters

  * `credentials` - A map containing authentication credentials

  ## Returns

  * `websocket_frame()` - The encoded authentication frame
  """
  @callback encode_auth_request(credentials :: credentials()) :: websocket_frame()

  @doc """
  Encodes a subscription request for the platform.

  This callback should generate a properly formatted WebSocket frame
  that subscribes to a channel or topic on the platform.

  ## Parameters

  * `channel` - The channel or topic to subscribe to
  * `params` - Optional parameters for the subscription

  ## Returns

  * `websocket_frame()` - The encoded subscription frame
  """
  @callback encode_subscription_request(channel :: channel(), params :: subscription_params()) ::
              websocket_frame()

  @doc """
  Encodes an unsubscription request for the platform.

  This callback should generate a properly formatted WebSocket frame
  that unsubscribes from a channel or topic on the platform.

  ## Parameters

  * `channel` - The channel or topic to unsubscribe from

  ## Returns

  * `websocket_frame()` - The encoded unsubscription frame
  """
  @callback encode_unsubscription_request(channel :: channel()) :: websocket_frame()

  @optional_callbacks [
    init: 1
  ]
end
