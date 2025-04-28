defmodule WebsockexNova.Gun.ConnectionStateTest do
  use ExUnit.Case, async: true

  alias WebsockexNova.Gun.ConnectionState

  describe "initialization" do
    test "new/3 creates a new state struct with default values" do
      host = "example.com"
      port = 443
      options = %{transport: :tls}
      state = ConnectionState.new(host, port, options)
      assert state.host == host
      assert state.port == port
      assert state.status == :initialized
      assert state.options == options
      assert state.transport == :tls
      assert state.path == "/ws"
      assert state.ws_opts == %{}
      assert state.gun_pid == nil
      assert state.gun_monitor_ref == nil
      assert state.last_error == nil
      assert state.active_streams == %{}
      assert state.handlers == %{}
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

    test "update_gun_monitor_ref/2 updates the monitor ref", %{state: state} do
      ref = make_ref()
      updated_state = ConnectionState.update_gun_monitor_ref(state, ref)
      assert updated_state.gun_monitor_ref == ref
    end

    test "record_error/2 sets the last_error field", %{state: state} do
      error = {:error, :connection_refused}
      updated_state = ConnectionState.record_error(state, error)
      assert updated_state.last_error == error
    end

    test "update_stream/3 adds or updates a stream", %{state: state} do
      stream_ref = make_ref()
      updated_state = ConnectionState.update_stream(state, stream_ref, :websocket)
      assert updated_state.active_streams[stream_ref] == :websocket
    end

    test "remove_stream/2 removes a stream", %{state: state} do
      stream_ref = make_ref()
      state = ConnectionState.update_stream(state, stream_ref, :websocket)
      updated_state = ConnectionState.remove_stream(state, stream_ref)
      refute Map.has_key?(updated_state.active_streams, stream_ref)
    end

    test "remove_streams/2 removes multiple streams", %{state: state} do
      ref1 = make_ref()
      ref2 = make_ref()
      state = ConnectionState.update_stream(state, ref1, :websocket)
      state = ConnectionState.update_stream(state, ref2, :websocket)
      updated_state = ConnectionState.remove_streams(state, [ref1, ref2])
      refute Map.has_key?(updated_state.active_streams, ref1)
      refute Map.has_key?(updated_state.active_streams, ref2)
    end

    test "clear_all_streams/1 clears all streams", %{state: state} do
      ref1 = make_ref()
      ref2 = make_ref()
      state = ConnectionState.update_stream(state, ref1, :websocket)
      state = ConnectionState.update_stream(state, ref2, :websocket)
      updated_state = ConnectionState.clear_all_streams(state)
      assert updated_state.active_streams == %{}
    end
  end

  describe "state duplication and divergence (post-refactor)" do
    test "options map does NOT contain session/auth/subscription state" do
      options = %{
        transport: :tls,
        auth_status: :authenticated,
        access_token: "token",
        subscriptions: %{topic: "foo"},
        adapter_state: %{foo: :bar}
      }

      state = ConnectionState.new("example.com", 443, options)
      # These should NOT be present in options after refactor
      refute Map.has_key?(state.options, :auth_status)
      refute Map.has_key?(state.options, :access_token)
      refute Map.has_key?(state.options, :subscriptions)
      refute Map.has_key?(state.options, :adapter_state)
      # Only transport config keys should be present
      assert Map.has_key?(state.options, :transport)
    end

    test "session/auth state cannot diverge between ClientConn and ConnectionState.options" do
      options = %{
        transport: :tls,
        auth_status: :unauthenticated,
        access_token: nil
      }

      state = ConnectionState.new("example.com", 443, options)

      _client_conn = %WebsockexNova.ClientConn{
        auth_status: :authenticated,
        access_token: "token"
      }

      # There is no session/auth state in options, so no divergence is possible
      refute Map.has_key?(state.options, :auth_status)
      refute Map.has_key?(state.options, :access_token)
    end
  end
end
