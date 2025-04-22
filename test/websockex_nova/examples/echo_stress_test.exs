defmodule WebsockexNova.Examples.EchoStressTest do
  use ExUnit.Case, async: false

  alias WebsockexNova.Examples.EchoClient

  # Mark these tests as integration and stress tests
  @moduletag [:integration, :stress]

  # Longer timeout for stress tests
  @timeout 60_000

  # Number of messages to send in rapid succession
  @message_count 50

  describe "Echo client stress tests" do
    setup do
      # Start the client connection
      case EchoClient.start() do
        {:ok, conn} ->
          # Return the connection to use in tests and ensure it's closed afterward
          on_exit(fn ->
            # Attempt to close the connection, but ignore any errors
            try do
              EchoClient.close(conn)
            catch
              _, _ -> :ok
            end
          end)

          {:ok, %{conn: conn}}

        {:error, reason} ->
          # If we can't connect, skip the tests
          IO.puts("SKIPPING STRESS TESTS: Could not connect to echo.websocket.org: #{inspect(reason)}")
          {:skip, "Could not connect to echo.websocket.org: #{inspect(reason)}"}
      end
    end

    @tag timeout: @timeout
    test "handles multiple messages in rapid succession", %{conn: conn} do
      # Create a list of messages to send
      messages =
        for i <- 1..@message_count do
          "Test message #{i} - #{System.system_time(:millisecond)}"
        end

      # Send all messages and collect responses
      tasks =
        Enum.map(messages, fn message ->
          Task.async(fn ->
            EchoClient.send_message(conn, message)
          end)
        end)

      # Await all responses
      results = Task.await_many(tasks, @timeout)

      # Verify all messages were echoed correctly
      for {{:ok, response}, message} <- Enum.zip(results, messages) do
        assert response == message
      end
    end

    @tag timeout: @timeout
    test "handles multiple pings in rapid succession", %{conn: conn} do
      # Send multiple pings and collect responses
      tasks =
        for _ <- 1..20 do
          Task.async(fn ->
            EchoClient.ping(conn)
          end)
        end

      # Await all responses
      results = Task.await_many(tasks, @timeout)

      # Verify all pings were successful
      for result <- results do
        assert result == {:ok, :pong}
      end
    end

    @tag timeout: @timeout
    test "handles alternating message types", %{conn: conn} do
      test_operations = [
        {:text, "Text message 1"},
        {:json, %{type: "json", value: 1}},
        {:text, "Text message 2"},
        {:json, %{type: "json", value: 2}},
        {:ping, nil},
        {:text, "Text message 3"},
        {:json, %{type: "json", value: 3}},
        {:ping, nil},
        {:json, %{type: "json", value: 4}},
        {:text, "Text message 4"}
      ]

      # Execute all operations
      results =
        Enum.map(test_operations, fn
          {:text, message} ->
            {:text, EchoClient.send_message(conn, message), message}

          {:json, data} ->
            {:json, EchoClient.send_json(conn, data), data}

          {:ping, _} ->
            {:ping, EchoClient.ping(conn), nil}
        end)

      # Verify all operations were successful
      for result <- results do
        case result do
          {:text, {:ok, response}, message} ->
            assert response == message

          {:json, {:ok, response}, data} ->
            assert is_binary(response)
            {:ok, decoded} = Jason.decode(response, keys: :atoms)
            assert decoded.type == data.type
            assert decoded.value == data.value

          {:ping, {:ok, response}, _} ->
            assert response == :pong
        end
      end
    end

    @tag timeout: @timeout
    test "handles concurrent connections", %{conn: _conn} do
      # Create multiple concurrent connections to the echo server
      connection_count = 5

      # Start multiple connections
      tasks =
        for i <- 1..connection_count do
          Task.async(fn ->
            # Connect and send a unique message
            {:ok, conn} = EchoClient.start()
            message = "Connection #{i} at #{System.system_time(:millisecond)}"

            # Send the message and verify the response
            {:ok, response} = EchoClient.send_message(conn, message)
            assert response == message

            # Clean up the connection
            :ok = EchoClient.close(conn)

            {:ok, i}
          end)
        end

      # Await all tasks
      results = Task.await_many(tasks, @timeout)

      # Verify all connections were successful
      for {status, i} <- results do
        assert status == :ok
        assert i in 1..connection_count
      end
    end
  end
end
