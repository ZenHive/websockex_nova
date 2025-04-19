defmodule WebsockexNova.Gun.ClientSupervisorTest do
  @moduledoc """
  Tests for WebsockexNova.Gun.ClientSupervisor.
  Note: This module uses async: false to ensure that tests verifying process registration under the hardcoded name :test_gun_supervisor do not interfere with each other or with other tests. This is required to safely test name registration.
  """
  use ExUnit.Case, async: false

  alias WebsockexNova.Gun.ClientSupervisor

  describe "initialization" do
    test "starts the supervisor with default options" do
      assert {:ok, pid} = start_supervised(ClientSupervisor)
      assert Process.alive?(pid)
      assert Supervisor.count_children(pid) == %{active: 0, specs: 0, supervisors: 0, workers: 0}
    end

    test "accepts configuration options and registers under the given name" do
      # This test intentionally uses a hardcoded name to verify registration.
      # Do not run this test async with others using :test_gun_supervisor.
      opts = [name: :test_gun_supervisor, strategy: :one_for_one]
      assert {:ok, pid} = start_supervised({ClientSupervisor, opts})
      assert Process.alive?(pid)
      assert Process.whereis(:test_gun_supervisor) == pid
    end
  end

  describe "child specifications" do
    test "generates valid child specifications" do
      connection_opts = [
        host: "example.com",
        port: 443,
        transport: :tls,
        transport_opts: [verify: :verify_none]
      ]

      child_spec = ClientSupervisor.child_spec(connection_opts)

      assert is_map(child_spec)
      assert child_spec.id == WebsockexNova.Gun.ClientSupervisor

      assert child_spec.start ==
               {WebsockexNova.Gun.ClientSupervisor, :start_link, [connection_opts]}

      assert child_spec.type == :supervisor
      assert child_spec.restart == :permanent
      assert child_spec.shutdown > 0
    end

    test "creates a Gun client with specified options" do
      {:ok, supervisor} = start_supervised(ClientSupervisor)
      unique_name = :"test_gun_client_#{:erlang.unique_integer([:positive])}"
      connection_opts = [
        name: unique_name,
        host: "echo.websocket.org",
        port: 443,
        transport: :tls
      ]
      assert {:ok, client_pid} = ClientSupervisor.start_client(supervisor, connection_opts)
      assert Process.alive?(client_pid)
      children = Supervisor.which_children(supervisor)
      assert Enum.any?(children, fn {_, pid, _, _} -> pid == client_pid end)
    end
  end

  describe "restart strategy" do
    @tag :capture_log
    test "restarts a crashed client automatically (structure only)" do
      {:ok, _supervisor} = start_supervised(ClientSupervisor)
      unique_name = :"test_restart_client_#{:erlang.unique_integer([:positive])}"
      _connection_opts = [
        name: unique_name,
        host: "example.com",
        port: 443
      ]
      # Future implementation would:
      # 1. Start a client
      # 2. Simulate a crash
      # 3. Verify the supervisor automatically restarts it
    end
  end

  describe "application configuration" do
    setup do
      original_env = Application.get_env(:websockex_nova, :gun_client_supervisor, [])
      on_exit(fn -> Application.put_env(:websockex_nova, :gun_client_supervisor, original_env) end)
      :ok
    end

    test "respects application configuration for default options (smoke test)" do
      test_config = [
        max_restarts: 10,
        max_seconds: 60,
        strategy: :rest_for_one
      ]

      Application.put_env(:websockex_nova, :gun_client_supervisor, test_config)

      # Start the supervisor with application config
      {:ok, supervisor} = start_supervised(ClientSupervisor)

      # We can't introspect the strategy directly, but we can check the supervisor is alive
      assert Process.alive?(supervisor)
    end
  end
end
