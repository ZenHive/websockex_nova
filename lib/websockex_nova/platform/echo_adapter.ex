defmodule WebsockexNova.Platform.EchoAdapter do
  @moduledoc """
  Minimal echo adapter using the WebsockexNova.Adapter macro.
  Echoes back any text or JSON message sent to it. Intended as a template for new adapters.
  """

  use WebsockexNova.Adapter

  alias WebsockexNova.Behaviors.ConnectionHandler

  @default_host "echo.websocket.org"
  @default_port 443
  @default_path "/"

  @impl WebsockexNova.Platform.Adapter
  def handle_platform_message(message, state) do
    # Delegate to the handler logic (from macro or override)
    handle_message({:text, message}, state)
  end

  @impl ConnectionHandler
  def init(opts) do
    opts =
      opts
      |> Map.new()
      |> Map.put_new(:host, @default_host)
      |> Map.put_new(:port, @default_port)
      |> Map.put_new(:path, @default_path)

    {:ok, opts}
  end

  @impl ConnectionHandler
  def handle_connect(_conn_info, state), do: {:ok, state}

  @impl WebsockexNova.Behaviors.MessageHandler
  def handle_message({:text, message}, state) when is_binary(message), do: {:reply, {:text, message}, state}
  def handle_message({:text, message}, state) when is_map(message), do: {:reply, {:text, Jason.encode!(message)}, state}
  def handle_message({:text, message}, state), do: {:reply, {:text, to_string(message)}, state}

  # All other callbacks are provided by the macro with safe defaults.
end
