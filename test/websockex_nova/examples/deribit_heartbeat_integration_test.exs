defmodule WebsockexNova.Examples.DeribitHeartbeatIntegrationTest do
  use ExUnit.Case, async: false
  
  @moduletag timeout: 40000  # Increase timeout for external tests

  alias WebsockexNova.Examples.AdapterDeribit
  alias WebsockexNova.Examples.ClientDeribit

  # Check if credentials are available
  @credentials_available (
    System.get_env("DERIBIT_CLIENT_ID") != nil && 
    System.get_env("DERIBIT_CLIENT_SECRET") != nil
  )

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
    {:ok, conn} = ClientDeribit.connect(%{
      host: "test.deribit.com",
      callback_pid: test_pid,
      log_level: :debug  # Enable debug logging for this test
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
              text =~ "\"method\":\"heartbeat\"" && text =~ "\"type\":\"test_request\"" ->
                IO.puts("✓ TEST REQUEST: #{String.slice(text, 0, 120)}")
                {heartbeats, [text | requests], responses}
                
              text =~ "\"method\":\"heartbeat\"" && text =~ "\"type\":\"heartbeat\"" ->
                IO.puts("♥ HEARTBEAT: #{String.slice(text, 0, 120)}")
                {[text | heartbeats], requests, responses}
                
              text =~ "\"method\":\"public/test\"" ->
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
    
    # Verify we received at least one regular heartbeat
    assert length(heartbeat_messages) > 0, "No regular heartbeat messages received"
    
    # Verify we received at least one test_request
    assert length(test_request_messages) > 0, "No test_request messages received"
    
    # Verify we sent at least one response to a test_request
    # This is the critical test - our handler must be responding to test_requests
    assert length(test_response_messages) > 0, "No test response messages sent - handler not working"
    
    # We should have a similar number of test requests and responses
    # (they might not match exactly due to timing, but should be close)
    assert abs(length(test_request_messages) - length(test_response_messages)) <= 1,
           "Mismatch between test requests (#{length(test_request_messages)}) and responses (#{length(test_response_messages)})"
    
    # We should NOT have received a close frame if our adapter is responding correctly
    assert !Enum.any?(messages, fn msg -> 
      case msg do
        {:websocket_frame, _, {:close, 4000, _}} -> true
        _ -> false 
      end
    end), "Connection was closed due to heartbeat failure (error code 4000)"
    
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