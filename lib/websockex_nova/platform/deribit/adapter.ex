defmodule WebsockexNova.Platform.Deribit.Adapter do
  @moduledoc """
  WebsockexNova adapter for the Deribit exchange (testnet).

  Demonstrates how to use the `WebsockexNova.Adapter` macro and delegate to default behaviors.
  Only Deribit-specific logic is implemented; all other events use robust defaults.

  ## Quick Start

      # Start a connection to Deribit testnet using all defaults
      {:ok, conn} = WebsockexNova.Connection.start_link(adapter: WebsockexNova.Platform.Deribit.Adapter)

      # Send a JSON-RPC message (echoed back by default handler)
      WebsockexNova.Client.send_json(conn, %{jsonrpc: "2.0", method: "public/ping", params: %{}})

      # Subscribe to a channel (uses default subscription handler)
      WebsockexNova.Client.subscribe(conn, "ticker.BTC-PERPETUAL.raw", %{})

  ## Customizing Handlers

  You can override any handler by passing it to `start_link/1`:

      {:ok, conn} = WebsockexNova.Connection.start_link(
        adapter: WebsockexNova.Platform.Deribit.Adapter,
        message_handler: MyApp.CustomMessageHandler,
        error_handler: MyApp.CustomErrorHandler
      )

  ## Advanced: Custom Platform Logic

  To implement Deribit-specific message routing, override `handle_platform_message/2`:

      def handle_platform_message(message, state) do
        # Custom logic here
        ...
      end

  ## Default Configuration

      adapter: WebsockexNova.Platform.Deribit.Adapter
      host: "test.deribit.com"
      port: 443
      path: "/ws/api/v2"

  See integration tests for real-world usage examples.
  """

  use WebsockexNova.Adapter

  alias WebsockexNova.Defaults.DefaultMessageHandler

  require Logger

  @default_host "test.deribit.com"
  @default_port 443
  @default_path "/ws/api/v2"

  @impl WebsockexNova.Behaviors.ConnectionHandler
  def init(opts) do
    state =
      opts
      |> Map.new()
      |> Map.put_new(:host, @default_host)
      |> Map.put_new(:port, @default_port)
      |> Map.put_new(:path, @default_path)
      |> Map.put_new(:message_id, 1)
      |> Map.put_new(:subscriptions, %{})
      |> Map.put_new(:auth_token, nil)
      |> Map.put_new(:transport, :tls)
      |> Map.put_new(:transport_opts,
        verify: :verify_peer,
        cacerts: :certifi.cacerts(),
        server_name_indication: ~c"test.deribit.com"
      )

    {:ok, state}
  end

  @impl WebsockexNova.Platform.Adapter
  def handle_platform_message(message, state) do
    # Pass the raw message directly to the default message handler
    DefaultMessageHandler.handle_message(message, state)
  end

  # All other events (connection, subscription, auth, error, etc.)
  # use the robust defaults provided by the macro.
end
