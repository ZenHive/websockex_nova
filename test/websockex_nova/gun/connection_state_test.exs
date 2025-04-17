defmodule WebSockexNova.Gun.ConnectionStateTest do
  use ExUnit.Case, async: true

  alias WebSockexNova.Gun.ConnectionState

  describe "initialization" do
    test "new/3 creates a new state struct with default values" do
      host = "example.com"
      port = 443
      options = %{transport: :tls}

      state = ConnectionState.new(host, port, options)

      assert state.host == host
      assert state.port == port
      assert state.options == options
      assert state.status == :initialized
      assert state.callback_pid == nil
      assert state.active_streams == %{}
      assert state.reconnect_attempts == 0
    end

    test "new/3 sets callback_pid from options" do
      callback_pid = self()
      options = %{callback_pid: callback_pid}

      state = ConnectionState.new("example.com", 443, options)

      assert state.callback_pid == callback_pid
    end
  end

  describe "state updates" do
    setup do
      state = ConnectionState.new("example.com", 443, %{})
      %{state: state}
    end

    test "update_status/2 changes the status field", %{state: state} do
      updated_state = ConnectionState.update_status(state, :connected)
      assert updated_state.status == :connected
    end

    test "update_gun_pid/2 sets the gun_pid field", %{state: state} do
      fake_pid =
        spawn(fn ->
          receive do
            _ -> :ok
          end
        end)

      updated_state = ConnectionState.update_gun_pid(state, fake_pid)
      assert updated_state.gun_pid == fake_pid
    end

    test "record_error/2 sets the last_error field", %{state: state} do
      error = {:error, :connection_refused}
      updated_state = ConnectionState.record_error(state, error)
      assert updated_state.last_error == error
    end

    test "update_stream/3 adds a stream to active_streams", %{state: state} do
      stream_ref = make_ref()
      updated_state = ConnectionState.update_stream(state, stream_ref, :upgrading)
      assert updated_state.active_streams[stream_ref] == :upgrading
    end

    test "update_stream/3 updates an existing stream", %{state: state} do
      stream_ref = make_ref()
      state_with_stream = ConnectionState.update_stream(state, stream_ref, :upgrading)
      updated_state = ConnectionState.update_stream(state_with_stream, stream_ref, :websocket)
      assert updated_state.active_streams[stream_ref] == :websocket
    end

    test "increment_reconnect_attempts/1 increases the reconnect counter", %{state: state} do
      assert state.reconnect_attempts == 0

      updated_state = ConnectionState.increment_reconnect_attempts(state)
      assert updated_state.reconnect_attempts == 1

      updated_state = ConnectionState.increment_reconnect_attempts(updated_state)
      assert updated_state.reconnect_attempts == 2
    end

    test "reset_reconnect_attempts/1 resets the counter to zero", %{state: state} do
      # First increment a few times
      state =
        state
        |> ConnectionState.increment_reconnect_attempts()
        |> ConnectionState.increment_reconnect_attempts()

      assert state.reconnect_attempts == 2

      # Then reset
      updated_state = ConnectionState.reset_reconnect_attempts(state)
      assert updated_state.reconnect_attempts == 0
    end
  end
end
