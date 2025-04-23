defmodule WebsockexNova.Examples.DeribitAdapterTest do
  use ExUnit.Case, async: true

  alias WebsockexNova.Examples.DeribitAdapter

  describe "DeribitAdapter minimal implementation" do
    test "connection_info/1 returns correct info" do
      {:ok, info} = DeribitAdapter.connection_info(%{})
      expected_host = System.get_env("DERIBIT_HOST") || "test.deribit.com"
      assert info.host == expected_host
      assert info.port == 443
      assert info.path == "/ws/api/v2"
      assert info.transport_opts.transport == :tls
    end

    test "init/1 initializes state" do
      {:ok, state} = DeribitAdapter.init([])
      assert is_map(state)
      assert state.messages == []
      assert state.connected_at == nil
    end

    test "handle_connect/2 sets connected_at" do
      state = %{messages: [], connected_at: nil}
      conn_info = %{host: "www.deribit.com", port: 443, path: "/ws/api/v2"}
      {:ok, new_state} = DeribitAdapter.handle_connect(conn_info, state)
      assert new_state.connected_at != nil
    end

    test "handle_frame/3 stores text messages" do
      state = %{messages: [], connected_at: 123}
      {:ok, new_state} = DeribitAdapter.handle_frame(:text, "test", state)
      assert new_state.messages == ["test"]
    end

    test "encode_message/2 encodes messages properly" do
      {:ok, :text, encoded} = DeribitAdapter.encode_message("hi", %{})
      assert is_binary(encoded)

      {:ok, :text, json} = DeribitAdapter.encode_message(%{foo: "bar"}, %{})
      assert is_binary(json)
      decoded = Jason.decode!(json)
      assert decoded["foo"] == "bar"
    end
  end
end
