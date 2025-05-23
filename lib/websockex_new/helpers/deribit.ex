defmodule WebsockexNew.Helpers.Deribit do
  @moduledoc """
  Helper functions for Deribit-specific WebSocket operations.
  """

  require Logger

  @doc """
  Handles Deribit test_request heartbeat messages.
  """
  def handle_heartbeat(%{"params" => %{"type" => "test_request"}}, state) do
    Logger.info("🚨 [DERIBIT TEST_REQUEST] Auto-responding...")

    # Send immediate test response
    response =
      Jason.encode!(%{
        jsonrpc: "2.0",
        method: "public/test",
        params: %{}
      })

    Logger.info("📤 [HEARTBEAT RESPONSE] #{DateTime.to_string(DateTime.utc_now())}")
    Logger.info("   ✅ Sending automatic public/test response")

    :gun.ws_send(state.gun_pid, state.stream_ref, {:text, response})

    # Update heartbeat tracking
    %{
      state
      | active_heartbeats: MapSet.put(state.active_heartbeats, :deribit_test_request),
        last_heartbeat_at: System.system_time(:millisecond),
        heartbeat_failures: 0
    }
  end

  def handle_heartbeat(_msg, state), do: state

  @doc """
  Sends Deribit heartbeat ping message.
  """
  def send_heartbeat(state) do
    message =
      Jason.encode!(%{
        jsonrpc: "2.0",
        method: "public/test",
        params: %{}
      })

    :gun.ws_send(state.gun_pid, state.stream_ref, {:text, message})

    %{state | last_heartbeat_at: System.system_time(:millisecond)}
  end
end
