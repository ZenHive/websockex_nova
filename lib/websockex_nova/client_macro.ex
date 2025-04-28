defmodule WebsockexNova.ClientMacro do
  @moduledoc """
  Macro for building WebsockexNova client modules with minimal boilerplate.

  Usage:

      defmodule MyApp.MyClient do
        use WebsockexNova.ClientMacro, adapter: MyApp.MyAdapter

        # Add domain-specific methods:
        def subscribe_to_custom_channel(conn, instrument_id, opts \\ nil) do
          channel = "custom.\#{instrument_id}.events"
          Client.subscribe(conn, channel, opts)
        end
      end

  This macro:
  - Injects common client functionality (connect, authenticate, send_json, etc.)
  - Configures the client to use the specified adapter
  - Allows adding domain-specific helper methods
  """

  defmacro __using__(opts) do
    adapter = Keyword.fetch!(opts, :adapter)

    quote do
      # Get client module from config or use WebsockexNova.Client as default
      # This allows for dependency injection in tests
      defp client_module do
        Application.get_env(:websockex_nova, :client_module, WebsockexNova.Client)
      end

      # Default options - clients can override this as needed
      @default_opts %{}

      @doc """
      Connect to WebSocket API with sensible defaults from the adapter.
      User-supplied opts override defaults.
      """
      def connect(opts \\ %{}) when is_map(opts) do
        # 1. Adapter protocol defaults
        {:ok, adapter_defaults} = unquote(adapter).connection_info(%{})
        # 2. Merge in client/app-level defaults (lowest priority after adapter)
        merged = Map.merge(adapter_defaults, default_opts())
        # 3. Merge in user opts (highest priority)
        merged_opts = Map.merge(merged, opts)
        client_module().connect(unquote(adapter), merged_opts)
      end

      @doc """
      Authenticate using credentials.
      """
      def authenticate(conn, credentials \\ %{}, opts \\ nil) do
        client_module().authenticate(conn, credentials, opts)
      end

      @doc """
      Subscribe to a channel.
      """
      def subscribe(conn, channel, opts \\ nil) do
        client_module().subscribe(conn, channel, opts)
      end

      @doc """
      Unsubscribe from a channel.
      """
      def unsubscribe(conn, channel, opts \\ nil) do
        client_module().unsubscribe(conn, channel, opts)
      end

      @doc """
      Send a JSON message.
      """
      def send_json(conn, payload, opts \\ nil) do
        client_module().send_json(conn, payload, opts)
      end

      @doc """
      Send a text message.
      """
      def send_text(conn, text, opts \\ nil) do
        client_module().send_text(conn, text, opts)
      end

      @doc """
      Send a ping and wait for pong response.
      """
      def ping(conn, opts \\ nil) do
        client_module().ping(conn, opts)
      end

      @doc """
      Get connection status.
      """
      def status(conn, opts \\ nil) do
        client_module().status(conn, opts)
      end

      @doc """
      Close the connection.
      """
      def close(conn) do
        client_module().close(conn)
      end

      # Allow clients to define their own default options
      defp default_opts, do: @default_opts
      defoverridable default_opts: 0
    end
  end
end
