defmodule WebsockexNova.Examples.EchoClient do
  @moduledoc """
  A simple client example demonstrating the use of the Echo adapter.

  This module provides a convenient way to test connectivity with the
  echo.websocket.org WebSocket Echo Server.
  """

  alias WebsockexNova.Client
  alias WebsockexNova.Examples.EchoAdapter

  require Logger

  @doc """
  Starts an interactive echo client session that connects to echo.websocket.org.

  Returns a tuple containing the connection for further interaction.

  ## Examples

      iex> {:ok, conn} = WebsockexNova.Examples.EchoClient.start()
      iex> WebsockexNova.Examples.EchoClient.send_message(conn, "Hello, WebSocket!")
      {:ok, "Hello, WebSocket!"}
  """
  def start do
    Logger.info("Connecting to echo.websocket.org...")

    case EchoAdapter.connection_info(%{}) do
      {:ok, connection_info} ->
        Client.connect(EchoAdapter, connection_info)

      other ->
        {:error, {:unexpected_connection_info, other}}
    end
  end

  @doc """
  Starts an echo client session with custom options (host, port, etc.).

  Returns a tuple containing the connection for further interaction.

  ## Examples

      iex> {:ok, conn} = WebsockexNova.Examples.EchoClient.start(%{host: "localhost", port: 12345})
      iex> WebsockexNova.Examples.EchoClient.send_message(conn, "Hello, WebSocket!")
      {:ok, "Hello, WebSocket!"}
  """
  def start(opts) when is_map(opts) do
    Logger.info("Connecting to custom echo server with opts: #{inspect(opts)}")

    case EchoAdapter.connection_info(opts) do
      {:ok, connection_info} ->
        # Merge/override connection_info with opts for host/port/path/transport_opts
        merged = Map.merge(connection_info, opts)
        Client.connect(EchoAdapter, merged)

      other ->
        {:error, {:unexpected_connection_info, other}}
    end
  end

  @doc """
  Sends a text message to the echo server and receives the echoed response.

  ## Parameters

  - `conn` - The connection struct from `start/0`
  - `message` - The text message to send

  ## Returns

  - `{:ok, response}` - The echoed response from the server
  - `{:error, reason}` - If an error occurs
  """
  def send_message(conn, message) when is_binary(message) do
    Logger.info("Sending message: #{inspect(message)}")
    Client.send_text(conn, message)
  end

  @doc """
  Sends a JSON message to the echo server and receives the echoed response.

  ## Parameters

  - `conn` - The connection struct from `start/0`
  - `data` - The map to send as JSON

  ## Returns

  - `{:ok, response}` - The echoed response from the server
  - `{:error, reason}` - If an error occurs
  """
  def send_json(conn, data) when is_map(data) do
    Logger.info("Sending JSON: #{inspect(data)}")
    Client.send_json(conn, data)
  end

  @doc """
  Sends a ping to the echo server to verify the connection is alive.

  ## Parameters

  - `conn` - The connection struct from `start/0`

  ## Returns

  - `{:ok, :pong}` - If the server responds with a pong
  - `{:error, reason}` - If an error occurs
  """
  def ping(conn) do
    Logger.info("Sending ping...")
    Client.ping(conn)
  end

  @doc """
  Closes the connection to the echo server.

  ## Parameters

  - `conn` - The connection struct from `start/0`

  ## Returns

  - `:ok` - If the connection is successfully closed
  """
  def close(conn) do
    Logger.info("Closing connection...")
    Client.close(conn)
  end

  @doc """
  Returns the current status of the connection.

  ## Parameters

  - `conn` - The connection struct from `start/0`

  ## Returns

  - `{:ok, status}` - The connection status
  - `{:error, reason}` - If an error occurs
  """
  def status(conn) do
    Client.status(conn)
  end

  @doc """
  Runs a demo sequence connecting to the echo server and exchanging several messages.

  This function connects to the echo server, sends a series of test messages,
  and then closes the connection.

  ## Examples

      iex> WebsockexNova.Examples.EchoClient.run_demo()
      :ok
  """
  def run_demo do
    Logger.configure(level: :info)

    case start() do
      {:ok, conn} ->
        Logger.info("Connected to echo.websocket.org")

        # Wait a brief moment for the connection to settle
        :timer.sleep(500)

        # Send a simple text message
        {:ok, response1} = send_message(conn, "Hello, WebSocket!")
        Logger.info("Received echo: #{inspect(response1)}")

        # Wait a moment between messages
        :timer.sleep(500)

        # Send a JSON message
        {:ok, response2} = send_json(conn, %{greeting: "Hello", data: [1, 2, 3]})
        Logger.info("Received echo: #{inspect(response2)}")

        # Wait a moment
        :timer.sleep(500)

        # Check connection status
        {:ok, status} = status(conn)
        Logger.info("Connection status: #{inspect(status)}")

        # Send a ping
        {:ok, ping_response} = ping(conn)
        Logger.info("Ping response: #{inspect(ping_response)}")

        # Wait a moment
        :timer.sleep(500)

        # Close the connection
        :ok = close(conn)
        Logger.info("Connection closed")

        :ok

      {:error, reason} ->
        Logger.error("Failed to connect: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
