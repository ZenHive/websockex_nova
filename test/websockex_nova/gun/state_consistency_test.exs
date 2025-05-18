defmodule WebsockexNova.Gun.StateConsistencyTest do
  use ExUnit.Case, async: false

  alias WebsockexNova.Examples.AdapterDeribit

  @tag :integration
  test "configuration propagation and state consistency before and after authentication" do
    # 1. Setup: All possible config options for default behaviors
    config = %{
      host: "test.deribit.com",
      port: 443,
      transport: :tls,
      path: "/ws/api/v2",
      ws_opts: %{},
      protocols: [:http],
      retry: 10,
      headers: [],
      transport_opts: %{},
      callback_pid: self(),
      backoff_type: :exponential,
      base_backoff: 2000,
      rate_limiter: WebsockexNova.Transport.RateLimiting,
      connection_handler: AdapterDeribit,
      message_handler: AdapterDeribit,
      error_handler: AdapterDeribit,
      logging_handler: WebsockexNova.Defaults.DefaultLoggingHandler,
      subscription_handler: AdapterDeribit,
      auth_handler: AdapterDeribit,
      metrics_collector: WebsockexNova.Defaults.DefaultMetricsCollector
    }

    # 2. Start connection using connect/2
    {:ok, conn} = WebsockexNova.Client.connect(AdapterDeribit, config)
    :timer.sleep(500)
    state = :sys.get_state(conn.transport_pid)

    # 3. Assert: No session/auth/subscription state in ConnectionState.options
    options = state.options
    refute Map.has_key?(options, :auth_status), "auth_status should not be in ConnectionState.options"
    refute Map.has_key?(options, :access_token), "access_token should not be in ConnectionState.options"
    refute Map.has_key?(options, :credentials), "credentials should not be in ConnectionState.options"
    refute Map.has_key?(options, :subscriptions), "subscriptions should not be in ConnectionState.options"

    # 4. Assert: All session/auth/subscription state is canonical in ClientConn
    assert is_nil(conn.adapter_state.auth_status) or
             conn.adapter_state.auth_status in [:unauthenticated, :authenticated]

    assert is_map(conn.adapter_state)

    # 5. Authenticate (call authenticate/3 and use updated conn)
    # Use test credentials (these are from CLAUDE.md)
    credentials = %{
      api_key: System.get_env("DERIBIT_CLIENT_ID"),
      secret: System.get_env("DERIBIT_CLIENT_SECRET")
    }

    {:ok, conn2, _auth_result} = WebsockexNova.Client.authenticate(conn, credentials)
    :timer.sleep(500)
    state2 = :sys.get_state(conn2.transport_pid)

    # 6. Assert: After authentication, state is consistent
    assert conn2.adapter_state.auth_status == :authenticated
    assert conn2.adapter_state.credentials == credentials
    assert is_binary(conn2.adapter_state.access_token)

    # Handler state in ConnectionState should not be a stale copy
    handler_state = state2.handlers[:subscription_handler_state]

    if is_map(handler_state) and Map.has_key?(handler_state, :auth_status) do
      assert handler_state.auth_status == conn2.adapter_state.auth_status, "Handler state should match canonical state"
      assert handler_state.credentials == conn2.adapter_state.credentials, "Handler state should match canonical state"
    end

    # 7. Assert: No duplicated or stale state in ConnectionState
    refute Map.has_key?(state2.options, :auth_status), "auth_status should not be in ConnectionState.options after auth"
    refute Map.has_key?(state2.options, :access_token), "access_token should not be in ConnectionState.options after auth"
    refute Map.has_key?(state2.options, :credentials), "credentials should not be in ConnectionState.options after auth"
  end
end
