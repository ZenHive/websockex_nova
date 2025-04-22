defmodule WebsockexNova.Examples.EchoClientTest do
  use ExUnit.Case, async: false

  alias WebsockexNova.ClientConn
  alias WebsockexNova.Examples.EchoAdapter
  alias WebsockexNova.Examples.EchoClient

  # Mark these tests as integration tests - they can be excluded with --exclude integration
  @moduletag :integration

  # Set a timeout for these tests since they talk to an external service
  @timeout 10_000

  describe "Echo client integration" do
    setup do
      # Start the client connection
      case EchoClient.start() do
        {:ok, conn} ->
          # Return the connection to use in tests and ensure it's closed afterward
          on_exit(fn ->
            # Attempt to close the connection, but ignore any errors
            # (the connection might already be closed by tests)
            try do
              EchoClient.close(conn)
            catch
              _, _ -> :ok
            end
          end)

          {:ok, %{conn: conn}}

        {:error, reason} ->
          # If we can't connect, skip the tests
          IO.puts("SKIPPING INTEGRATION TESTS: Could not connect to echo.websocket.org: #{inspect(reason)}")
          {:skip, "Could not connect to echo.websocket.org: #{inspect(reason)}"}
      end
    end

    test "establishes a connection", %{conn: conn} do
      assert %ClientConn{} = conn
      assert conn.adapter == EchoAdapter
      assert is_pid(conn.transport_pid)
      assert is_reference(conn.stream_ref)

      # Check the connection status
      {:ok, status} = EchoClient.status(conn)
      assert status in [:connected, :ok, "connected"]
    end

    @tag timeout: @timeout
    test "sends and receives a text message", %{conn: conn} do
      test_message = "Hello from integration test! #{System.system_time(:millisecond)}"

      # Send the message
      {:ok, response} = EchoClient.send_message(conn, test_message)

      # The echo server should return exactly what we sent
      assert response == test_message
    end

    @tag timeout: @timeout
    test "sends and receives a JSON message", %{conn: conn} do
      test_data = %{
        greeting: "Hello JSON",
        timestamp: System.system_time(:millisecond),
        values: [1, 2, 3, 4, 5],
        nested: %{key: "value"}
      }

      # Send the JSON data
      {:ok, response} = EchoClient.send_json(conn, test_data)

      # For JSON messages, the response is the JSON string
      assert is_binary(response)

      # Decode the response to verify it contains our data
      {:ok, decoded} = Jason.decode(response, keys: :atoms)
      assert decoded.greeting == test_data.greeting
      assert decoded.timestamp == test_data.timestamp
      assert decoded.values == test_data.values
      assert decoded.nested.key == test_data.nested.key
    end

    @tag timeout: @timeout
    test "sends a ping and receives a pong", %{conn: conn} do
      {:ok, response} = EchoClient.ping(conn)
      assert response == :pong
    end

    @tag timeout: @timeout
    test "closes the connection successfully", %{conn: conn} do
      result = EchoClient.close(conn)
      assert result == :ok

      # Give it a moment to process the close
      :timer.sleep(500)

      # After closing, any further operations should fail
      assert match?({:error, _}, try_operation(fn -> EchoClient.ping(conn) end))
    end
  end

  # Helper function to catch errors when trying operations on a closed connection
  defp try_operation(fun) do
    fun.()
  catch
    kind, reason -> {:error, {kind, reason}}
  end
end
