defmodule WebsockexNova.Test.Support.MockWebSockHandler do
  @moduledoc """
  WebSock-based handler for the mock WebSocket server.

  This module implements the WebSock behavior to handle WebSocket connections
  in a standardized way, making testing more reliable.
  """

  @behaviour WebSock

  require Logger

  @impl WebSock
  def init(options) do
    parent = Keyword.get(options, :parent)
    Logger.debug("MockWebSockHandler init with options: #{inspect(options)}")

    state = %{
      parent: parent,
      ref: make_ref()
    }

    # Register with parent server
    if parent do
      Logger.debug("MockWebSockHandler registering with parent: #{inspect(parent)}")
      send(parent, {:register_client, self(), state.ref})
    end

    {:ok, state}
  end

  @impl WebSock
  def handle_in({:text, message, opts}, state) do
    Logger.debug(
      "MockWebSockHandler received TEXT frame: #{inspect(message)}, opts: #{inspect(opts)}"
    )

    # Forward message to parent
    if state.parent do
      Logger.debug("Forwarding text message to parent: #{inspect(state.parent)}")
      send(state.parent, {:websocket_message, self(), :text, message})
    end

    # Return without reply - real response will be sent later by parent
    {:ok, state}
  end

  @impl WebSock
  def handle_in({:binary, message, opts}, state) do
    Logger.debug(
      "MockWebSockHandler received BINARY frame: #{byte_size(message)} bytes, opts: #{inspect(opts)}"
    )

    # Forward message to parent
    if state.parent do
      Logger.debug("Forwarding binary message to parent: #{inspect(state.parent)}")
      send(state.parent, {:websocket_message, self(), :binary, message})
    end

    # Return without reply - real response will be sent later by parent
    {:ok, state}
  end

  @impl WebSock
  def handle_in({:ping, message, _opts}, state) do
    Logger.debug("MockWebSockHandler received PING frame: #{inspect(message)}")
    # Auto-respond with pong
    {:push, {:pong, message}, state}
  end

  @impl WebSock
  def handle_in({:pong, message, _opts}, state) do
    Logger.debug("MockWebSockHandler received PONG frame: #{inspect(message)}")
    # Ignore pongs
    {:ok, state}
  end

  @impl WebSock
  def handle_in({:close, code, reason, _opts}, state) do
    Logger.debug(
      "MockWebSockHandler received CLOSE frame: code=#{inspect(code)}, reason=#{inspect(reason)}"
    )

    # Client requested close
    {:stop, :normal, state}
  end

  @impl WebSock
  def handle_info({:send_text, message}, state) do
    Logger.debug("MockWebSockHandler sending TEXT frame: #{inspect(message)}")
    # Send text frame to client
    {:push, {:text, message}, state}
  end

  @impl WebSock
  def handle_info({:send_binary, message}, state) do
    Logger.debug("MockWebSockHandler sending BINARY frame: #{byte_size(message)} bytes")
    # Send binary frame to client
    {:push, {:binary, message}, state}
  end

  @impl WebSock
  def handle_info({:send_error, reason}, state) do
    # Log error and echo it back as text
    Logger.error("Mock WebSocket error: #{reason}")
    {:push, {:text, Jason.encode!(%{error: reason})}, state}
  end

  @impl WebSock
  def handle_info({:disconnect, code, reason}, state) do
    Logger.debug(
      "MockWebSockHandler disconnecting: code=#{inspect(code)}, reason=#{inspect(reason)}"
    )

    # Close the WebSocket connection
    {:push, {:close, code, reason}, state}
  end

  @impl WebSock
  def handle_info(message, state) do
    # Log unhandled messages
    Logger.debug("MockWebSockHandler received unhandled message: #{inspect(message)}")
    {:ok, state}
  end

  @impl WebSock
  def terminate(reason, state) do
    # Log termination and notify parent if needed
    Logger.debug("MockWebSockHandler terminating. Reason: #{inspect(reason)}")

    if state.parent && Process.alive?(state.parent) do
      Logger.debug("Notifying parent #{inspect(state.parent)} about termination")
      send(state.parent, {:client_terminated, self(), reason})
    end

    :ok
  end
end
