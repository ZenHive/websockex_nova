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
      assert status in [:connected, :ok, "connected", :websocket_connected]
    end

    @tag timeout: @timeout
    test "sends and receives a text message", %{conn: conn} do
      test_message = "Hello from integration test! #{System.system_time(:millisecond)}"

      matcher = fn
        {:websockex_nova, {:websocket_frame, _stream_ref, {:text, response}}} when response == test_message ->
          {:ok, response}

        {:websockex_nova, :error, reason} ->
          {:error, reason}

        _ ->
          :skip
      end

      opts = %{matcher: matcher}
      {:ok, response} = WebsockexNova.Client.send_text(conn, test_message, opts)
      assert response == test_message
    end

    @tag timeout: @timeout
    test "Echo client integration sends and receives a JSON message", %{conn: conn} do
      payload = %{
        timestamp: System.system_time(:millisecond),
        values: [1, 2, 3, 4, 5],
        greeting: "Hello JSON",
        nested: %{key: "value"}
      }

      IO.inspect("Sending JSON: #{inspect(payload)}")

      matcher = fn
        {:websockex_nova, {:websocket_frame, _stream_ref, {:text, response}}} ->
          case Jason.decode(response, keys: :atoms) do
            {:ok, decoded} -> {:ok, decoded}
            _ -> :skip
          end

        {:websockex_nova, :error, reason} ->
          {:error, reason}

        _ ->
          :skip
      end

      opts = %{matcher: matcher}
      {:ok, decoded} = WebsockexNova.Client.send_json(conn, payload, opts)
      assert decoded.greeting == "Hello JSON"
      assert decoded.nested.key == "value"
      assert is_list(decoded.values)
      assert is_integer(decoded.timestamp)
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
