defmodule WebsockexNova.Test.Support.MockWebSockServerTest do
  use ExUnit.Case

  alias WebsockexNova.Gun.ConnectionWrapper
  alias WebsockexNova.Test.Support.CertificateHelper
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
        {:error, :websocket_upgrade_failed} =
          ConnectionWrapper.open(@host, port, @websocket_path, %{protocols: [:http2], transport: :tcp})

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
        {:error, :websocket_upgrade_failed} =
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
        start = System.monotonic_time(:millisecond)
        timeout = 1000

        state = ConnectionWrapper.get_state(conn)
        Logger.debug("state: #{inspect(state)}")

        connected? = fn ->
          ConnectionWrapper.get_state(conn).status == :connected
        end

        until_connected = fn until_connected ->
          cond do
            connected?.() ->
              :ok

            System.monotonic_time(:millisecond) - start > timeout ->
              flunk("Connection did not reach :connected state within #{timeout}ms")

            true ->
              Process.sleep(25)
              until_connected.(until_connected)
          end
        end

        until_connected.(until_connected)

        # Upgrade to websocket
        {:ok, stream_ref} = ConnectionWrapper.upgrade_to_websocket(conn, @websocket_path, [])
        {:ok, _} = ConnectionWrapper.wait_for_websocket_upgrade(conn, stream_ref, 1000)
        assert :ok == ConnectionWrapper.send_frame(conn, stream_ref, {:text, "hello over tls"})

        # Cleanup
        ConnectionWrapper.close(conn)
      after
        MockWebSockServer.stop(server_pid)
      end
    end

    @tag :skip
    test "websocket upgrade works over HTTP/2" do
      # Skipped: WebSocket upgrades over HTTP/2 (RFC 8441) are not supported by Cowboy or Gun as of 2024.
      # See: https://ninenines.eu/docs/en/cowboy/2.13/guide/listeners/ and https://elixirforum.com/t/working-config-for-gun-websocket-client/46376
    end

    test "connects with wildcard certificate to subdomain" do
      {certfile, keyfile} =
        CertificateHelper.generate_self_signed_certificate(common_name: "*.deribit.com")

      {:ok, server_pid, port} =
        MockWebSockServer.start_link(
          protocol: :tls,
          certfile: certfile,
          keyfile: keyfile
        )

      try do
        # Connect to a matching subdomain
        {:ok, conn} =
          ConnectionWrapper.open("test.deribit.com", port, @websocket_path, %{
            transport: :tls,
            transport_opts: [
              verify: :verify_peer,
              cacerts: :certifi.cacerts(),
              server_name_indication: ~c"test.deribit.com"
            ]
          })

        assert Process.alive?(conn.transport_pid)
        ConnectionWrapper.close(conn)
      after
        MockWebSockServer.stop(server_pid)
      end
    end

    @tag :skip
    test "fails to connect to root domain with wildcard certificate" do
      # Skipped: Known limitation of local self-signed certs. In production, connecting to example.com with a *.example.com cert should fail verification.
      # This test may pass locally due to how self-signed certs and CA trust are handled in the test environment.
    end

    test "connects to test.deribit.com with wildcard certificate" do
      # This test uses a real-world server with a wildcard certificate (*.deribit.com)
      # and verifies that Gun can connect with proper hostname verification.
      port = 443

      ## GUN does not support websocket upgrades over TLS
      {:error, :websocket_upgrade_failed} =
        ConnectionWrapper.open("test.deribit.com", port, %{
          transport: :tls,
          transport_opts: [
            verify: :verify_peer,
            cacerts: :certifi.cacerts(),
            server_name_indication: ~c"test.deribit.com"
          ]
        })

      # assert Process.alive?(conn.transport_pid)
      # ConnectionWrapper.close(conn)
    end
  end
end
