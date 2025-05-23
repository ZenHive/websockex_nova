defmodule WebsockexNew.Application do
  @moduledoc """
  Application callback module for WebsockexNew.

  Starts the client supervisor for managing WebSocket connections.
  """

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Start the dynamic supervisor for client connections
      WebsockexNew.ClientSupervisor
    ]

    opts = [strategy: :one_for_one, name: WebsockexNew.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
