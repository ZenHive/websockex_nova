defmodule WebsockexNova.ConnectionTestHelper do
  @moduledoc """
  Test helper functions for WebsockexNova.Connection tests.
  Provides utilities to start connections in specific states, simulate transport events, and set up Mox expectations.
  """

  import ExUnit.Assertions

  alias WebsockexNova.ClientConn
  alias WebsockexNova.Connection

  @doc """
  Starts a connection process with the given options and returns the pid and initial state.
  Optionally, you can specify the initial connection state (:connected, :disconnected, etc.).
  """
  @spec start_connection_in_state(keyword, atom) :: {:ok, ClientConn.t(), pid}
  def start_connection_in_state(opts, initial_state \\ :connected) do
    {:ok, %ClientConn{pid: pid} = conn} = Connection.start_link(opts)
    # Simulate state if needed
    case initial_state do
      :connected -> send(pid, {:websocket_connected, %{}})
      :disconnected -> send(pid, {:websocket_disconnected, %{}})
      _ -> :ok
    end

    {:ok, conn, pid}
  end

  @doc """
  Simulates a transport event by sending it to the connection process.
  """
  @spec simulate_event(pid, term) :: :ok
  def simulate_event(pid, event) do
    send(pid, event)
    :ok
  end

  @doc """
  Asserts that the connection process transitions to the expected state after an event.
  """
  @spec assert_state_transition(pid, term, (map -> boolean)) :: :ok
  def assert_state_transition(pid, event, assertion_fun) do
    send(pid, event)
    # Give the process a moment to handle the event
    :timer.sleep(10)
    state = :sys.get_state(pid)
    assert assertion_fun.(state)
    :ok
  end
end
