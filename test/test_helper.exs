## Configure Logger to only show warnings and errors
Logger.configure(level: :none)
# Logger.configure(level: :info)
# Logger.configure(level: :warning)
# Logger.configure(level: :debug)

ExUnit.start()

Mox.defmock(WebsockexNova.TransportMock, for: WebsockexNova.Transport)
Mox.defmock(WebsockexNova.ConnectionHandlerMock, for: WebsockexNova.Behaviours.ConnectionHandler)
Mox.defmock(WebsockexNova.MessageHandlerMock, for: WebsockexNova.Behaviours.MessageHandler)

Mox.defmock(WebsockexNova.SubscriptionHandlerMock,
  for: WebsockexNova.Behaviours.SubscriptionHandler
)

Mox.defmock(WebsockexNova.AuthHandlerMock, for: WebsockexNova.Behaviours.AuthHandler)
Mox.defmock(WebsockexNova.ErrorHandlerMock, for: WebsockexNova.Behaviours.ErrorHandler)
Mox.defmock(WebsockexNova.RateLimitHandlerMock, for: WebsockexNova.Behaviours.RateLimitHandler)
Mox.defmock(WebsockexNova.LoggingHandlerMock, for: WebsockexNova.Behaviours.LoggingHandler)
Mox.defmock(WebsockexNova.MetricsCollectorMock, for: WebsockexNova.Behaviours.MetricsCollector)
# Mox.defmock(WebsockexNova.ConnectionManagerMock, for: WebsockexNova.ConnectionManagerBehaviour)

# Mox.set_mox_global()

### see in mix.exs where it is loaded already
# ["#{__DIR__}", "support/**/*.ex"]
# |> Path.join()
# |> Path.wildcard()
# |> Enum.each(&Code.require_file/1)
### end of see in mix.exs where it is loaded already
