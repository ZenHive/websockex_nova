# Create a plug router for handling HTTP and WebSocket requests
defmodule WebsockexNova.Test.Support.MockWebSockServer.Router do
  use Plug.Router

  require Logger

  # Special case to make the router definable inline in this module
  @server_parent Process.get(:server_parent)
  plug(:match)
  plug(:dispatch)

  get "/ws" do
    Logger.debug("Router received WebSocket upgrade request")

    conn =
      WebSockAdapter.upgrade(
        conn,
        WebsockexNova.Test.Support.MockWebSockHandler,
        [parent: @server_parent],
        []
      )

    # WebSockAdapter will take over the connection from here
    conn
  end

  match _ do
    Logger.debug("Router received non-WebSocket request: #{conn.request_path}")
    send_resp(conn, 404, "Not Found")
  end
end
