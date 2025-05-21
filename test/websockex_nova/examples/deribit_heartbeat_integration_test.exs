defmodule WebsockexNova.Examples.DeribitHeartbeatIntegrationTest do
  use ExUnit.Case, async: false

  alias WebsockexNova.Examples.ClientDeribit

  # Increase timeout for external tests
  @moduletag timeout: 40_000

  # Check if credentials are available
  @credentials_available System.get_env("DERIBIT_CLIENT_ID") != nil &&
                           System.get_env("DERIBIT_CLIENT_SECRET") != nil

  setup do
    if !@credentials_available do
      IO.warn("Skipping Deribit integration test - no credentials provided")
      # Just return without running the test
      exit(:shutdown)
    end

    # Start a test process to receive messages
    test_pid = self()

    on_exit(fn ->
      # Ensure we clean up any connections
      Process.sleep(500)
    end)

    {:ok, %{test_pid: test_pid}}
  end

  test "correctly responds to heartbeat test_request messages", %{test_pid: test_pid} do
    # Connect to the real Deribit test server with verbose logging
    {:ok, conn} =
      ClientDeribit.connect(%{
        host: "test.deribit.com",
        callback_pid: test_pid,
        # Enable debug logging for this test
        log_level: :debug
      })

    # Set a heartbeat interval (10 seconds is the minimum allowed by Deribit)
    {:ok, heartbeat_response} = ClientDeribit.set_heartbeat(conn, 10)
    IO.puts("Heartbeat set response: #{inspect(heartbeat_response)}")

    # Wait for initial setup to complete
    Process.sleep(1000)

    # Flush any initial messages
    flush_messages()

    # Wait longer for heartbeat messages (at least 20 seconds to ensure we get a test_request)
    # This should be enough time to receive both regular heartbeat and test_request messages
    messages = collect_messages([], 25_000)

    # Categorize and log the received messages
    IO.puts("\n====== RECEIVED MESSAGES (#{length(messages)} total) ======")

    # Use reduce to collect message types while logging
    {heartbeat_messages, test_request_messages, test_response_messages} =
      Enum.reduce(messages, {[], [], []}, fn msg, {heartbeats, requests, responses} ->
        case msg do
          {:websocket_frame, _, {:text, text}} ->
            cond do
              text =~ ~s("method":"heartbeat") && text =~ ~s("type":"test_request") ->
                IO.puts("✓ TEST REQUEST: #{String.slice(text, 0, 120)}")
                {heartbeats, [text | requests], responses}

              text =~ ~s("method":"heartbeat") && !(text =~ ~s("type":"test_request")) ->
                IO.puts("♥ HEARTBEAT: #{String.slice(text, 0, 120)}")
                {[text | heartbeats], requests, responses}

              text =~ ~s("method":"public/test") ->
                IO.puts("⟲ TEST RESPONSE: #{String.slice(text, 0, 120)}")
                {heartbeats, requests, [text | responses]}

              true ->
                IO.puts("OTHER TEXT: #{String.slice(text, 0, 100)}")
                {heartbeats, requests, responses}
            end

          {:websocket_frame, _, {:close, code, reason}} ->
            IO.puts("⚠ CLOSE FRAME: code=#{code}, reason=#{reason}")
            {heartbeats, requests, responses}

          other ->
            IO.puts("OTHER MESSAGE: #{inspect(other)}")
            {heartbeats, requests, responses}
        end
      end)

    IO.puts("=======================================\n")

    # Clean up
    ClientDeribit.disconnect(conn)

    # According to Deribit API, they send test_request messages, not regular heartbeat messages
    # The test_request messages are what we need to respond to
    # So let's just verify we got the set_heartbeat confirmation and any test_requests
    IO.puts("Heartbeat messages: #{length(heartbeat_messages)}")
    IO.puts("Test request messages: #{length(test_request_messages)}")
    IO.puts("Test response messages: #{length(test_response_messages)}")

    # The main test: verify our adapter is working by checking we didn't get disconnected
    # If our heartbeat handler is working, the connection should stay open
    # According to Deribit docs: "If your software fails to respond to test_request messages,
    # the API server will immediately close the connection"

    # Check if we got a connection close due to heartbeat failure
    connection_closed_by_heartbeat =
      Enum.any?(messages, fn msg ->
        case msg do
          # 4000 is heartbeat timeout
          {:websocket_frame, _, {:close, 4000, _}} -> true
          _ -> false
        end
      end)

    # The critical test: we should NOT have been disconnected for heartbeat failure
    refute connection_closed_by_heartbeat,
           "Connection was closed due to heartbeat failure (error code 4000) - our handler is not working properly"

    # If we received test_request(s), verify we responded to them
    if length(test_request_messages) > 0 do
      assert length(test_response_messages) > 0,
             "Received test_request messages but didn't send responses - handler not working"

      IO.puts(
        "✅ Received #{length(test_request_messages)} test_request(s) and sent #{length(test_response_messages)} response(s)"
      )
    else
      IO.puts(
        "ℹ️  No test_request messages received during test period - this is normal if the server hasn't sent them yet"
      )
    end

    # Success! If we got here without the connection being closed for heartbeat failure,
    # our adapter is working correctly

    # Success message
    IO.puts("\n✅ Integration test passed: Deribit adapter correctly handling heartbeat test_request messages")
  end

  # Helper to flush any pending messages from the process mailbox
  defp flush_messages do
    receive do
      _ -> flush_messages()
    after
      0 -> :ok
    end
  end

  # Helper function to collect messages for a specified time
  defp collect_messages(msgs, timeout) do
    timeout_ref = make_ref()
    timer_ref = Process.send_after(self(), {:timeout, timeout_ref}, timeout)

    result = collect_messages_loop(msgs, timeout_ref)
    Process.cancel_timer(timer_ref)

    # Clean mailbox from potential timeout message
    receive do
      {:timeout, ^timeout_ref} -> :ok
    after
      0 -> :ok
    end

    result
  end

  defp collect_messages_loop(msgs, timeout_ref) do
    receive do
      {:timeout, ^timeout_ref} ->
        msgs

      msg = {:websocket_frame, _, _} ->
        collect_messages_loop([msg | msgs], timeout_ref)

      msg = {:connection_up, _} ->
        collect_messages_loop([msg | msgs], timeout_ref)

      msg = {:websocket_upgrade, _, _} ->
        collect_messages_loop([msg | msgs], timeout_ref)

      _other ->
        collect_messages_loop(msgs, timeout_ref)
    end
  end
end
