defmodule WebsockexNova.Examples.EchoDemo do
  @moduledoc """
  Interactive demo module for the WebsockexNova Echo client.

  This module provides a simple way to interactively test and demonstrate
  the WebSocket Echo server connection from IEx.

  ## Usage

  ```elixir
  # Start IEx
  iex -S mix

  # Run the demo
  WebsockexNova.Examples.EchoDemo.run()

  # Connect and interact manually
  alias WebsockexNova.Examples.EchoDemo
  {:ok, session} = EchoDemo.start()
  EchoDemo.send_text(session, "Hello, WebSocket!")
  EchoDemo.send_json(session, %{greeting: "Hello", data: [1, 2, 3]})
  EchoDemo.ping(session)
  EchoDemo.close(session)
  ```
  """

  alias WebsockexNova.Examples.EchoClient

  require Logger

  @doc """
  Starts an Echo client session.

  Returns a session map that includes the connection and metadata for tracking
  messages sent during the session.

  ## Examples

      iex> {:ok, session} = WebsockexNova.Examples.EchoDemo.start()
      iex> is_map(session)
      true
  """
  def start do
    Logger.configure(level: :info)
    Logger.info("Starting Echo client demo session...")

    case EchoClient.start() do
      {:ok, conn} ->
        session = %{
          conn: conn,
          messages: [],
          started_at: DateTime.utc_now(),
          message_count: 0
        }

        Logger.info("Connected to echo.websocket.org")
        {:ok, session}

      {:error, reason} ->
        Logger.error("Failed to connect: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Sends a text message to the echo server.

  Returns the updated session and echoed response.

  ## Parameters

  - `session` - The session map from `start/0`
  - `message` - The text message to send

  ## Examples

      iex> {:ok, session} = WebsockexNova.Examples.EchoDemo.start()
      iex> {:ok, session, response} = WebsockexNova.Examples.EchoDemo.send_text(session, "Hello")
      iex> response
      "Hello"
  """
  def send_text(session, message) when is_binary(message) do
    Logger.info("Sending text: #{inspect(message)}")

    case EchoClient.send_message(session.conn, message) do
      {:ok, response} ->
        new_session = %{
          session
          | messages: [%{type: :text, sent: message, received: response} | session.messages],
            message_count: session.message_count + 1
        }

        Logger.info("Received echo: #{inspect(response)}")
        {:ok, new_session, response}

      {:error, reason} ->
        Logger.error("Failed to send message: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Sends a JSON message to the echo server.

  Returns the updated session and echoed response.

  ## Parameters

  - `session` - The session map from `start/0`
  - `data` - Map to be encoded as JSON

  ## Examples

      iex> {:ok, session} = WebsockexNova.Examples.EchoDemo.start()
      iex> {:ok, session, response} = WebsockexNova.Examples.EchoDemo.send_json(session, %{greeting: "Hello"})
      iex> is_binary(response)
      true
  """
  def send_json(session, data) when is_map(data) do
    Logger.info("Sending JSON: #{inspect(data)}")

    case EchoClient.send_json(session.conn, data) do
      {:ok, response} ->
        new_session = %{
          session
          | messages: [%{type: :json, sent: data, received: response} | session.messages],
            message_count: session.message_count + 1
        }

        Logger.info("Received echo: #{inspect(response)}")
        {:ok, new_session, response}

      {:error, reason} ->
        Logger.error("Failed to send JSON: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Sends a ping to the echo server.

  Returns the updated session and pong response.

  ## Parameters

  - `session` - The session map from `start/0`

  ## Examples

      iex> {:ok, session} = WebsockexNova.Examples.EchoDemo.start()
      iex> {:ok, session, response} = WebsockexNova.Examples.EchoDemo.ping(session)
      iex> response
      :pong
  """
  def ping(session) do
    Logger.info("Sending ping...")

    case EchoClient.ping(session.conn) do
      {:ok, response} ->
        new_session = %{
          session
          | messages: [%{type: :ping, sent: :ping, received: response} | session.messages],
            message_count: session.message_count + 1
        }

        Logger.info("Received pong: #{inspect(response)}")
        {:ok, new_session, response}

      {:error, reason} ->
        Logger.error("Failed to send ping: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Checks the connection status.

  Returns the updated session and connection status.

  ## Parameters

  - `session` - The session map from `start/0`

  ## Examples

      iex> {:ok, session} = WebsockexNova.Examples.EchoDemo.start()
      iex> {:ok, _session, status} = WebsockexNova.Examples.EchoDemo.status(session)
      iex> is_atom(status)
      true
  """
  def status(session) do
    Logger.info("Checking status...")

    case EchoClient.status(session.conn) do
      {:ok, status} ->
        Logger.info("Connection status: #{inspect(status)}")
        {:ok, session, status}

      {:error, reason} ->
        Logger.error("Failed to get status: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Closes the echo server connection.

  Returns the updated session.

  ## Parameters

  - `session` - The session map from `start/0`

  ## Examples

      iex> {:ok, session} = WebsockexNova.Examples.EchoDemo.start()
      iex> {:ok, _session} = WebsockexNova.Examples.EchoDemo.close(session)
  """
  def close(session) do
    Logger.info("Closing connection...")

    # EchoClient.close/1 only returns :ok as documented
    :ok = EchoClient.close(session.conn)

    # Calculate session duration
    ended_at = DateTime.utc_now()
    duration = DateTime.diff(ended_at, session.started_at, :second)

    new_session = %{session | ended_at: ended_at, duration: duration}

    # Log a summary
    Logger.info("Connection closed")
    Logger.info("Session summary:")
    Logger.info("- Total messages: #{new_session.message_count}")
    Logger.info("- Session duration: #{duration} seconds")

    {:ok, new_session}
  end

  @doc """
  Runs a complete demo sequence with the echo server.

  This function connects to the echo server, sends various types of messages,
  and then closes the connection. It provides a simple way to demonstrate
  the WebsockexNova Echo client functionality.

  ## Examples

      iex> WebsockexNova.Examples.EchoDemo.run()
      :ok
  """
  def run do
    Logger.configure(level: :info)
    Logger.info("Starting WebsockexNova Echo Demo")

    case start() do
      {:ok, session} ->
        # Wait a brief moment for the connection to settle
        :timer.sleep(500)

        # Check status
        {:ok, session, _status} = status(session)

        # Send a simple text message
        {:ok, session, _response} = send_text(session, "Hello, WebSocket!")
        :timer.sleep(500)

        # Send a JSON message
        {:ok, session, _response} =
          send_json(session, %{
            greeting: "Hello JSON",
            timestamp: DateTime.to_string(DateTime.utc_now()),
            values: [1, 2, 3, 4, 5],
            nested: %{key: "value"}
          })

        :timer.sleep(500)

        # Send a ping
        {:ok, session, _pong} = ping(session)
        :timer.sleep(500)

        # Send another text message
        {:ok, session, _response} = send_text(session, "Goodbye, WebSocket!")
        :timer.sleep(500)

        # Close the connection - we know close/1 only returns {:ok, session}
        {:ok, _final_session} = close(session)

        :ok

      {:error, reason} ->
        Logger.error("Demo failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Prints session statistics.

  ## Parameters

  - `session` - The session map from `start/0`

  ## Examples

      iex> {:ok, session} = WebsockexNova.Examples.EchoDemo.start()
      iex> WebsockexNova.Examples.EchoDemo.print_stats(session)
      :ok
  """
  def print_stats(session) do
    current_time = DateTime.utc_now()
    start_time = session.started_at
    duration = DateTime.diff(current_time, start_time, :second)

    IO.puts("\nEcho Session Statistics:")
    IO.puts("----------------------")
    IO.puts("Started at: #{DateTime.to_string(start_time)}")
    IO.puts("Current time: #{DateTime.to_string(current_time)}")
    IO.puts("Duration: #{duration} seconds")
    IO.puts("Total messages: #{session.message_count}")

    if session.message_count > 0 do
      IO.puts("\nMessage History (most recent first):")
      IO.puts("----------------------------------")

      session.messages
      # Only show the most recent 10 messages
      |> Enum.take(10)
      |> Enum.with_index(1)
      |> Enum.each(fn {msg, i} ->
        IO.puts("#{i}. Type: #{msg.type}, Sent: #{inspect(msg.sent)}, Received: #{inspect(msg.received)}")
      end)

      if length(session.messages) > 10 do
        IO.puts("... and #{length(session.messages) - 10} more")
      end
    end

    :ok
  end
end
