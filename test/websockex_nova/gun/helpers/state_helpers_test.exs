defmodule WebsockexNova.Gun.Helpers.StateHelpersTest do
  use ExUnit.Case, async: true

  alias WebsockexNova.Gun.ConnectionState
  alias WebsockexNova.Gun.Helpers.StateHelpers

  describe "handle_ownership_transfer/2" do
    test "correctly updates state on ownership transfer" do
      # Setup initial state
      state = ConnectionState.new("example.com", 443, %{})

      # Create a test process to act as the gun_pid
      gun_pid = spawn(fn -> Process.sleep(1000) end)

      # Create info map from previous owner
      stream_ref = make_ref()

      info = %{
        gun_pid: gun_pid,
        status: :connected,
        active_streams: %{stream_ref => :websocket}
      }

      # Call the helper
      updated_state = StateHelpers.handle_ownership_transfer(state, info)

      # Verify state was updated correctly
      assert updated_state.gun_pid == gun_pid
      assert updated_state.status == :connected
      assert is_reference(updated_state.gun_monitor_ref)
      assert updated_state.active_streams[stream_ref] == :websocket
    end

    test "doesn't replace active_streams if empty" do
      # Setup initial state with existing streams
      state = ConnectionState.new("example.com", 443, %{})
      existing_stream_ref = make_ref()
      state = ConnectionState.update_stream(state, existing_stream_ref, :websocket)

      # Create a test process
      gun_pid = spawn(fn -> Process.sleep(1000) end)

      # Create info map with empty active_streams
      info = %{
        gun_pid: gun_pid,
        status: :connected,
        active_streams: %{}
      }

      # Call the helper
      updated_state = StateHelpers.handle_ownership_transfer(state, info)

      # Verify streams weren't replaced
      assert updated_state.active_streams[existing_stream_ref] == :websocket
    end

    test "uses existing monitor if already present" do
      # Setup initial state with existing monitor
      state = ConnectionState.new("example.com", 443, %{})
      gun_pid = spawn(fn -> Process.sleep(1000) end)
      monitor_ref = Process.monitor(gun_pid)
      state = ConnectionState.update_gun_monitor_ref(state, monitor_ref)

      # Create info map
      info = %{
        gun_pid: gun_pid,
        status: :connected,
        active_streams: %{}
      }

      # Call the helper
      updated_state = StateHelpers.handle_ownership_transfer(state, info)

      # Verify monitor wasn't changed
      assert updated_state.gun_monitor_ref == monitor_ref
    end
  end
end
