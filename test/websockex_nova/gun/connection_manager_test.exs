defmodule WebsockexNova.Gun.ConnectionManagerTest do
  use ExUnit.Case, async: true

  alias WebsockexNova.Gun.ConnectionManager
  alias WebsockexNova.Gun.ConnectionState

  describe "state transitions" do
    test "allows transition from :initialized to :connecting" do
      state = ConnectionState.new("example.com", 80, %{})
      {:ok, new_state} = ConnectionManager.transition_to(state, :connecting)
      assert new_state.status == :connecting
    end

    test "allows transition from :connecting to :connected" do
      state = ConnectionState.new("example.com", 80, %{})
      {:ok, state} = ConnectionManager.transition_to(state, :connecting)
      {:ok, new_state} = ConnectionManager.transition_to(state, :connected)
      assert new_state.status == :connected
    end

    test "allows transition from :connected to :websocket_connected" do
      state = ConnectionState.new("example.com", 80, %{})
      {:ok, state} = ConnectionManager.transition_to(state, :connecting)
      {:ok, state} = ConnectionManager.transition_to(state, :connected)
      {:ok, new_state} = ConnectionManager.transition_to(state, :websocket_connected)
      assert new_state.status == :websocket_connected
    end

    test "disallows invalid transitions" do
      state = ConnectionState.new("example.com", 80, %{})

      # Can't go from :initialized to :websocket_connected directly
      assert {:error, :invalid_transition} =
               ConnectionManager.transition_to(state, :websocket_connected)

      # Can't go from :initialized to :disconnected directly
      assert {:error, :invalid_transition} = ConnectionManager.transition_to(state, :disconnected)
    end

    test "allows transition to :disconnected from connected states" do
      state = ConnectionState.new("example.com", 80, %{})
      {:ok, state} = ConnectionManager.transition_to(state, :connecting)
      {:ok, state} = ConnectionManager.transition_to(state, :connected)
      {:ok, new_state} = ConnectionManager.transition_to(state, :disconnected)
      assert new_state.status == :disconnected

      # Also from websocket_connected
      state = ConnectionState.new("example.com", 80, %{})
      {:ok, state} = ConnectionManager.transition_to(state, :connecting)
      {:ok, state} = ConnectionManager.transition_to(state, :connected)
      {:ok, state} = ConnectionManager.transition_to(state, :websocket_connected)
      {:ok, new_state} = ConnectionManager.transition_to(state, :disconnected)
      assert new_state.status == :disconnected
    end

    test "allows transition to :error from any state" do
      states = [
        :initialized,
        :connecting,
        :connected,
        :websocket_connected,
        :disconnected,
        :reconnecting
      ]

      for initial_state <- states do
        # Create a fresh state for each test case
        state = ConnectionState.new("example.com", 80, %{})

        # Set up the state for testing based on which state we want to test
        state =
          case initial_state do
            :initialized ->
              # Already initialized, no transition needed
              state

            :connecting ->
              {:ok, connecting_state} = ConnectionManager.transition_to(state, :connecting)
              connecting_state

            :connected ->
              {:ok, connecting_state} = ConnectionManager.transition_to(state, :connecting)

              {:ok, connected_state} =
                ConnectionManager.transition_to(connecting_state, :connected)

              connected_state

            :websocket_connected ->
              {:ok, connecting_state} = ConnectionManager.transition_to(state, :connecting)

              {:ok, connected_state} =
                ConnectionManager.transition_to(connecting_state, :connected)

              {:ok, ws_state} =
                ConnectionManager.transition_to(connected_state, :websocket_connected)

              ws_state

            :disconnected ->
              # Go through connected first, then disconnect
              {:ok, connecting_state} = ConnectionManager.transition_to(state, :connecting)

              {:ok, connected_state} =
                ConnectionManager.transition_to(connecting_state, :connected)

              {:ok, disconnected_state} =
                ConnectionManager.transition_to(connected_state, :disconnected)

              disconnected_state

            :reconnecting ->
              # Go to disconnected first, then reconnecting
              {:ok, connecting_state} = ConnectionManager.transition_to(state, :connecting)

              {:ok, connected_state} =
                ConnectionManager.transition_to(connecting_state, :connected)

              {:ok, disconnected_state} =
                ConnectionManager.transition_to(connected_state, :disconnected)

              {:ok, reconnecting_state} =
                ConnectionManager.transition_to(disconnected_state, :reconnecting)

              reconnecting_state
          end

        # Now transition to error - this should work from any state
        {:ok, new_state} = ConnectionManager.transition_to(state, :error)
        assert new_state.status == :error
      end
    end
  end

  describe "reconnection logic" do
    test "reconnects on temporary failures" do
      state = ConnectionState.new("example.com", 80, %{retry: 3})
      {:ok, state} = ConnectionManager.transition_to(state, :connecting)
      {:ok, state} = ConnectionManager.transition_to(state, :connected)
      {:ok, state} = ConnectionManager.transition_to(state, :disconnected, %{reason: :normal})

      # With a normal disconnect reason, should allow reconnection
      assert {:ok, _reconnect_after, new_state} = ConnectionManager.handle_reconnection(state)
      assert new_state.status == :reconnecting
      assert new_state.reconnect_attempts == 1
    end

    test "doesn't reconnect on terminal failures" do
      state = ConnectionState.new("example.com", 80, %{retry: 3})
      {:ok, state} = ConnectionManager.transition_to(state, :connecting)

      # Terminal error scenario
      {:ok, state} = ConnectionManager.transition_to(state, :error, %{reason: :fatal_error})

      assert {:error, :terminal_error, new_state} = ConnectionManager.handle_reconnection(state)
      assert new_state.status == :error
    end

    test "respects max reconnection attempts" do
      state = ConnectionState.new("example.com", 80, %{retry: 2})
      {:ok, state} = ConnectionManager.transition_to(state, :connecting)
      {:ok, state} = ConnectionManager.transition_to(state, :connected)
      {:ok, state} = ConnectionManager.transition_to(state, :disconnected)

      # First attempt
      {:ok, _reconnect_after, state} = ConnectionManager.handle_reconnection(state)
      assert state.reconnect_attempts == 1

      # Set back to disconnected for another attempt
      {:ok, state} = ConnectionManager.transition_to(state, :disconnected)

      # Second attempt
      {:ok, _reconnect_after, state} = ConnectionManager.handle_reconnection(state)
      assert state.reconnect_attempts == 2

      # Set back to disconnected for third attempt, which should fail
      {:ok, state} = ConnectionManager.transition_to(state, :disconnected)

      # Third attempt - exceeds the limit of 2
      assert {:error, :max_attempts_reached, new_state} =
               ConnectionManager.handle_reconnection(state)

      assert new_state.status == :error
      # Shouldn't be incremented after failure
      assert new_state.reconnect_attempts == 2
    end

    test "implements exponential backoff" do
      state =
        ConnectionState.new("example.com", 80, %{
          retry: 3,
          backoff_type: :exponential,
          base_backoff: 100
        })

      {:ok, state} = ConnectionManager.transition_to(state, :connecting)
      {:ok, state} = ConnectionManager.transition_to(state, :connected)
      {:ok, state} = ConnectionManager.transition_to(state, :disconnected)

      # First attempt
      {:ok, first_delay, state} = ConnectionManager.handle_reconnection(state)

      # Should be around 100ms (base_backoff) with jitter
      assert first_delay >= 100
      assert first_delay <= 120

      # Set back to disconnected for second attempt
      {:ok, state} = ConnectionManager.transition_to(state, :disconnected)

      # Second attempt should have increased delay
      {:ok, second_delay, _state} = ConnectionManager.handle_reconnection(state)

      # Should be around 200ms (2^1 * base_backoff) with jitter
      assert second_delay >= 200
      assert second_delay <= 240
    end

    test "handles reconnection scheduling" do
      # Create a test process to receive messages
      test_pid = self()

      # Create a callback function that will be called when reconnect is scheduled
      callback = fn delay, attempt -> send(test_pid, {:reconnect_scheduled, delay, attempt}) end

      # Create initial state
      state =
        ConnectionState.new("example.com", 80, %{
          retry: 2,
          backoff_type: :linear,
          base_backoff: 100
        })

      {:ok, state} = ConnectionManager.transition_to(state, :connecting)
      {:ok, state} = ConnectionManager.transition_to(state, :connected)
      {:ok, state} = ConnectionManager.transition_to(state, :disconnected)

      # Test scheduling a reconnection
      new_state = ConnectionManager.schedule_reconnection(state, callback)

      # Verify the state is updated properly
      assert new_state.status == :reconnecting
      assert new_state.reconnect_attempts == 1

      # Verify the callback was called with the right parameters
      assert_receive {:reconnect_scheduled, delay, 1}
      assert delay >= 100

      # Test what happens when max attempts is reached
      {:ok, state} = ConnectionManager.transition_to(new_state, :disconnected)

      # This should be the last attempt (max_retries = 2)
      new_state = ConnectionManager.schedule_reconnection(state, callback)
      assert new_state.reconnect_attempts == 2
      assert_receive {:reconnect_scheduled, _delay, 2}

      # One more attempt should fail and go to error state
      {:ok, state} = ConnectionManager.transition_to(new_state, :disconnected)

      final_state = ConnectionManager.schedule_reconnection(state, callback)
      assert final_state.status == :error
      # No callback message should be sent
      refute_receive {:reconnect_scheduled, _delay, _attempt}
    end

    test "does not schedule reconnection for terminal errors" do
      # Create a test process to receive messages
      test_pid = self()

      # Create a callback function
      callback = fn delay, attempt -> send(test_pid, {:reconnect_scheduled, delay, attempt}) end

      # Create initial state with a terminal error
      state =
        "example.com"
        |> ConnectionState.new(80, %{retry: 3})
        |> ConnectionState.record_error(:econnrefused)

      {:ok, state} = ConnectionManager.transition_to(state, :connecting)
      {:ok, state} = ConnectionManager.transition_to(state, :disconnected)

      # Try to schedule reconnection with a terminal error
      new_state = ConnectionManager.schedule_reconnection(state, callback)

      # Should transition to error state
      assert new_state.status == :error

      # No callback should have been called
      refute_receive {:reconnect_scheduled, _delay, _attempt}
    end
  end

  describe "state machine integration" do
    test "handles full connection lifecycle" do
      # Initialize
      state = ConnectionState.new("example.com", 80, %{retry: 3})
      assert state.status == :initialized

      # Connect
      {:ok, state} = ConnectionManager.transition_to(state, :connecting)
      assert state.status == :connecting

      # Connection established
      {:ok, state} = ConnectionManager.transition_to(state, :connected)
      assert state.status == :connected

      # WebSocket upgrade
      {:ok, state} = ConnectionManager.transition_to(state, :websocket_connected)
      assert state.status == :websocket_connected

      # Disconnect
      {:ok, state} = ConnectionManager.transition_to(state, :disconnected)
      assert state.status == :disconnected

      # Reconnecting
      {:ok, _reconnect_after, state} = ConnectionManager.handle_reconnection(state)
      assert state.status == :reconnecting

      # Reconnected
      {:ok, state} = ConnectionManager.transition_to(state, :connecting)
      {:ok, state} = ConnectionManager.transition_to(state, :connected)
      assert state.status == :connected

      # Success - connection reestablished
      {:ok, state} = ConnectionManager.transition_to(state, :websocket_connected)
      assert state.status == :websocket_connected
    end
  end
end
