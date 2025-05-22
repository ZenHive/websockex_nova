defmodule Mix.Tasks.WebsockexNew.CheckHandlers do
  @shortdoc "Check all WebsockexNew default handler modules for required callbacks"

  @moduledoc """
  Checks all WebsockexNew.Defaults.* handler modules to ensure they implement all required callbacks for their respective behaviors.
  Prints missing callbacks or confirms all are correct.
  """

  use Mix.Task

  @handlers [
    {WebsockexNew.Defaults.DefaultConnectionHandler, WebsockexNew.Behaviors.ConnectionHandler, "ConnectionHandler"},
    {WebsockexNew.Defaults.DefaultMessageHandler, WebsockexNew.Behaviors.MessageHandler, "MessageHandler"},
    {WebsockexNew.Defaults.DefaultSubscriptionHandler, WebsockexNew.Behaviors.SubscriptionHandler,
     "SubscriptionHandler"},
    {WebsockexNew.Defaults.DefaultAuthHandler, WebsockexNew.Behaviors.AuthHandler, "AuthHandler"},
    {WebsockexNew.Defaults.DefaultErrorHandler, WebsockexNew.Behaviors.ErrorHandler, "ErrorHandler"},
    {WebsockexNew.Defaults.DefaultRateLimitHandler, WebsockexNew.Behaviors.RateLimitHandler, "RateLimitHandler"},
    {WebsockexNew.Defaults.DefaultLoggingHandler, WebsockexNew.Behaviors.LoggingHandler, "LoggingHandler"},
    {WebsockexNew.Defaults.DefaultMetricsCollector, WebsockexNew.Behaviors.MetricsCollector, "MetricsCollector"}
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
