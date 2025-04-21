defmodule WebsockexNova.Platform.Echo.Adapter do
  @moduledoc """
  Minimal reference implementation of the WebsockexNova platform adapter contract.

  This adapter connects to the public echo WebSocket server at https://echo.websocket.org
  and simply echoes back any text or JSON message sent to it. It is intended as a template
  for building real, featureful adapters.

  ## Features

  - Echoes text and JSON messages as text frames.
  - All advanced features (subscriptions, authentication, ping, status, etc.) are not supported
    and return inert values.
  - No state is tracked or mutated beyond the initial connection.

  ## Usage

      iex> {:ok, pid} = WebsockexNova.Connection.start_link(adapter: WebsockexNova.Platform.Echo.Adapter)
      iex> WebsockexNova.Client.send_text(pid, "Hello")
      {:text, "Hello"}
      iex> WebsockexNova.Client.send_json(pid, %{foo: "bar"})
      {:text, "{\"foo\":\"bar\"}"}

  The adapter always connects to the public echo server (wss://echo.websocket.org).

  ## Purpose
  This module is a minimal, idiomatic example of a platform adapter.
  """

  use WebsockexNova.Platform.Adapter

  @default_host "echo.websocket.org"
  @default_port 443
  @default_path "/"

  @impl true
  @doc """
  Initializes the Echo adapter state.
  Accepts options and merges with defaults.
  """
  def init(opts) do
    opts =
      opts
      |> Map.new()
      |> Map.put_new(:host, @default_host)
      |> Map.put_new(:port, @default_port)
      |> Map.put_new(:path, @default_path)

    {:ok, opts}
  end

  @doc """
  Handles platform messages by echoing them back as text frames.
  - If the message is a binary, echoes as text.
  - If the message is a map, encodes as JSON and echoes as text.
  """
  @impl WebsockexNova.Platform.Adapter
  def handle_platform_message(message, state) when is_binary(message), do: {:reply, {:text, message}, state}
  def handle_platform_message(message, state) when is_map(message), do: {:reply, {:text, Jason.encode!(message)}, state}
  def handle_platform_message(message, state), do: {:reply, {:text, to_string(message)}, state}
end
