defmodule WebsockexNova.Test.Support.MockWebSockServerTest do
  use ExUnit.Case

  alias WebsockexNova.Gun.ConnectionWrapper
  # alias WebsockexNova.Test.Support.CertificateHelper
  alias WebsockexNova.Test.Support.MockWebSockServer

  @websocket_path "/ws"
  @host "localhost"
  describe "protocol options" do
    require Logger

    test "starts server with HTTP/1.1 (default)" do
      {:ok, server_pid, port} = MockWebSockServer.start_link()

      try do
        # Verify we can connect with default options
        {:ok, conn} = ConnectionWrapper.open(@host, port, @websocket_path, %{transport: :tcp})

        # Verify the connection works
        assert Process.alive?(conn.transport_pid)

        # Cleanup
        ConnectionWrapper.close(conn)
      after
        MockWebSockServer.stop(server_pid)
      end
    end

    test "starts server with HTTP/2" do
      {:ok, server_pid, port} = MockWebSockServer.start_link(protocol: :http2)

      ## GUN does not support websocket upgrades over HTTP/2
      try do
        # Connect with HTTP/2 protocol
        {:error, :connection_failed} =
          ConnectionWrapper.open(@host, port, @websocket_path, %{
            protocols: [:http2],
            transport: :tcp
          })

        # Verify connection
        # assert Process.alive?(conn.transport_pid)

        # Cleanup
        # ConnectionWrapper.close(conn)
      after
        MockWebSockServer.stop(server_pid)
      end
    end

    test "starts server with TLS" do
      {:ok, server_pid, port} = MockWebSockServer.start_link(protocol: :tls)

      try do
        # Connect with TLS
        {:ok, conn} =
          ConnectionWrapper.open(@host, port, @websocket_path, %{
            transport: :tls,
            transport_opts: [verify: :verify_none]
          })

        # Verify connection
        assert Process.alive?(conn.transport_pid)

        # Cleanup
        ConnectionWrapper.close(conn)
      after
        MockWebSockServer.stop(server_pid)
      end
    end

    test "starts server with HTTP/2 over TLS" do
      {:ok, server_pid, port} = MockWebSockServer.start_link(protocol: :https2)

      ## GUN does not support websocket upgrades over HTTP/2
      try do
        # Connect with HTTP/2 over TLS
        {:error, :connection_failed} =
          ConnectionWrapper.open(@host, port, @websocket_path, %{
            transport: :tls,
            transport_opts: [verify: :verify_none],
            protocols: [:http2]
          })

        # Verify connection
        # assert Process.alive?(conn.transport_pid)

        # Cleanup
        # ConnectionWrapper.close(conn)
      after
        MockWebSockServer.stop(server_pid)
      end
    end

    test "websocket upgrade works over TLS" do
      {:ok, server_pid, port} = MockWebSockServer.start_link(protocol: :tls)

      try do
        # Connect with TLS
        {:ok, conn} =
          ConnectionWrapper.open(@host, port, @websocket_path, %{
            transport: :tls,
            transport_opts: [verify: :verify_none]
          })

        # Wait for connection to be established (up to 1000ms)
        # The connection is already upgraded to websocket by open/4
        assert Process.alive?(conn.transport_pid)
        assert :ok == ConnectionWrapper.send_frame(conn, conn.stream_ref, {:text, "hello over tls"})

        # Cleanup
        ConnectionWrapper.close(conn)
      after
        MockWebSockServer.stop(server_pid)
      end
    end

    @tag :skip
    test "websocket upgrade works over HTTP/2" do
      # Skipped: WebSocket upgrades over HTTP/2 (RFC 8441) are not supported by Cowboy or Gun as of
      # 2024.
      # See: https://ninenines.eu/docs/en/cowboy/2.13/guide/listeners/ and
      # https://elixirforum.com/t/working-config-for-gun-websocket-client/46376
    end

    test "connects with wildcard certificate to subdomain" do
      # No need to generate a cert or start a mock server for real server test

      {:ok, conn} =
        ConnectionWrapper.open("test.deribit.com", 443, "/ws/api/v2", %{
          transport: :tls,
          transport_opts: [
            verify: :verify_peer,
            cacerts: :certifi.cacerts(),
            server_name_indication: ~c"test.deribit.com"
          ],
          callback_pid: self()
        })

      assert Process.alive?(conn.transport_pid)
      ConnectionWrapper.close(conn)
    end

    test "connects to www.deribit.com with wildcard certificate" do
      # This test uses a real-world server with a wildcard certificate (*.deribit.com)
      # and verifies that Gun can connect with proper hostname verification.

      ## GUN does not support websocket upgrades over TLS
      {:ok, conn} =
        ConnectionWrapper.open("www.deribit.com", 443, "/ws/api/v2", %{
          transport: :tls,
          transport_opts: [
            verify: :verify_peer,
            cacerts: :certifi.cacerts(),
            server_name_indication: ~c"www.deribit.com"
          ]
        })

      assert Process.alive?(conn.transport_pid)
      ConnectionWrapper.close(conn)
    end
  end
end
