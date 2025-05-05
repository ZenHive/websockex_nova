defmodule Mix.Tasks.WebsockexNova.CheckHandlers do
  @shortdoc "Check all WebsockexNova default handler modules for required callbacks"

  @moduledoc """
  Checks all WebsockexNova.Defaults.* handler modules to ensure they implement all required callbacks for their respective behaviours.
  Prints missing callbacks or confirms all are correct.
  """

  use Mix.Task

  @handlers [
    {WebsockexNova.Defaults.DefaultConnectionHandler, WebsockexNova.Behaviours.ConnectionHandler,
     "ConnectionHandler"},
    {WebsockexNova.Defaults.DefaultMessageHandler, WebsockexNova.Behaviours.MessageHandler,
     "MessageHandler"},
    {WebsockexNova.Defaults.DefaultSubscriptionHandler,
     WebsockexNova.Behaviours.SubscriptionHandler, "SubscriptionHandler"},
    {WebsockexNova.Defaults.DefaultAuthHandler, WebsockexNova.Behaviours.AuthHandler,
     "AuthHandler"},
    {WebsockexNova.Defaults.DefaultErrorHandler, WebsockexNova.Behaviours.ErrorHandler,
     "ErrorHandler"},
    {WebsockexNova.Defaults.DefaultRateLimitHandler, WebsockexNova.Behaviours.RateLimitHandler,
     "RateLimitHandler"},
    {WebsockexNova.Defaults.DefaultLoggingHandler, WebsockexNova.Behaviours.LoggingHandler,
     "LoggingHandler"},
    {WebsockexNova.Defaults.DefaultMetricsCollector, WebsockexNova.Behaviours.MetricsCollector,
     "MetricsCollector"}
  ]

  @impl true
  def run(_args) do
    Mix.Task.run("app.start")

    for {mod, behaviour, label} <- @handlers do
      IO.puts("\n--- Checking #{label} ---")
      IO.puts("Module: #{inspect(mod)}")
      IO.puts("Behavior: #{inspect(behaviour)}")
      IO.puts("Loaded from: #{:code.which(mod)}")

      required_callbacks = behaviour.behaviour_info(:callbacks)
      optional_callbacks = behaviour.behaviour_info(:optional_callbacks)
      required_only = required_callbacks -- optional_callbacks

      exported = mod.module_info(:exports)

      missing =
        Enum.filter(required_only, fn {fun, arity} ->
          not Enum.any?(exported, fn {f, a} -> f == fun and a == arity end)
        end)

      if missing == [] do
        IO.puts("✅ All required callbacks are implemented.\n")
      else
        IO.puts("❌ Missing callbacks: #{inspect(missing)}\n")
      end
    end
  end
end
