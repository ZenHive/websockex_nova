defmodule WebsockexNova.MockTransportImpl do
  @moduledoc """
  A simple mock implementation of the WebsockexNova.Transport behaviour for testing and development.

  This module can be used in place of a real transport (e.g., Gun) to simulate transport operations
  in tests or development environments where a real network connection is not desired.
  """
  @behaviour WebsockexNova.Transport

  @impl true
  def send_frame(_state, _stream_ref, _frame), do: :ok

  @impl true
  def upgrade_to_websocket(_state, _path, _headers), do: {:ok, :mock_stream}

  @impl true
  def close(_state), do: :ok

  @impl true
  def process_transport_message(_state, msg), do: {:handled, msg}

  @impl true
  def get_state(state), do: state
end
