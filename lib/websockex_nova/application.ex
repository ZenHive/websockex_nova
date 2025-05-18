defmodule WebsockexNova.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false
  use Application

  alias WebsockexNova.ConnectionRegistry
  alias WebsockexNova.Gun.FrameCodec
  alias WebsockexNova.Transport.RateLimiting

  @impl true
  def start(_type, _args) do
    # Initialize frame handlers table at application startup
    FrameCodec.init_handlers_table()

    children = [
      # Starts a worker by calling: WebsockexNova.Worker.start_link(arg)
      # {WebsockexNova.Worker, arg}

      # Connection registry for maintaining stable references to transport processes
      ConnectionRegistry,

      # config :websockex_nova, :rate_limiting,
      #   handler: MyApp.CustomRateLimitHandler,
      #   capacity: 100,
      #   refill_rate: 5,
      #   refill_interval: 1000,
      #   queue_limit: 200,
      #   process_interval: 100,
      #   cost_map: %{subscription: 5, auth: 10, query: 1}

      # Start the global/shared rate limiter
      {RateLimiting, get_rate_limiting_opts()}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: WebsockexNova.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Retrieve rate limiting options from application config
  defp get_rate_limiting_opts do
    Application.get_env(:websockex_nova, :rate_limiting, [])
  end
end
