defmodule WebsockexNova.Gun.ClientSupervisorRegistrationTest do
  @moduledoc """
  This test is isolated and marked async: false because it verifies process registration under the hardcoded name :test_gun_supervisor.
  Using a hardcoded name can cause interference if run in parallel, so it is kept in a separate file.
  """
  use ExUnit.Case, async: false

  alias WebsockexNova.Gun.ClientSupervisor

  test "accepts configuration options and registers under the given name" do
    opts = [name: :test_gun_supervisor, strategy: :one_for_one]
    assert {:ok, pid} = start_supervised({ClientSupervisor, opts})
    assert Process.alive?(pid)
    assert Process.whereis(:test_gun_supervisor) == pid
  end
end
