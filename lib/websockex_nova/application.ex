defmodule WebsockexNova.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false
  use Application

  alias WebsockexNova.Gun.FrameCodec

  @impl true
  def start(_type, _args) do
    # Initialize frame handlers table at application startup
    FrameCodec.init_handlers_table()

    children = [
      # Starts a worker by calling: WebsockexNova.Worker.start_link(arg)
      # {WebsockexNova.Worker, arg}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: WebsockexNova.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
