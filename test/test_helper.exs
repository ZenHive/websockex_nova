require Logger
## Configure Logger to only show warnings and errors
# Logger.configure(level: :none)
# Logger.configure(level: :info)
# Logger.configure(level: :warning)
# Logger.configure(level: :debug)

ExUnit.start()
# Display testing policy message
Logger.warning("""
\n[!] TESTING POLICY [!]
--------------------------------------------------
DO NOT USE MOCKS! They are proven to be unreliable.
ALWAYS test against real test APIs (e.g., test.deribit.com).
If no test API is available, use real API.

NEVER SKIP TESTS because you can not find CREDENTIALS. Credentials
must be always present. LET THEM FAIL.

Failure to adhere to this policy will result in immediate
TERMINATION ("you are fired!") and your employment will be terminated.
--------------------------------------------------
\n
""")

Mox.defmock(WebsockexNova.TransportMock, for: WebsockexNova.Transport)
Mox.defmock(WebsockexNova.ConnectionHandlerMock, for: WebsockexNova.Behaviors.ConnectionHandler)
Mox.defmock(WebsockexNova.MessageHandlerMock, for: WebsockexNova.Behaviors.MessageHandler)
Mox.defmock(WebsockexNova.SubscriptionHandlerMock, for: WebsockexNova.Behaviors.SubscriptionHandler)
Mox.defmock(WebsockexNova.AuthHandlerMock, for: WebsockexNova.Behaviors.AuthHandler)
Mox.defmock(WebsockexNova.ErrorHandlerMock, for: WebsockexNova.Behaviors.ErrorHandler)
Mox.defmock(WebsockexNova.RateLimitHandlerMock, for: WebsockexNova.Behaviors.RateLimitHandler)
Mox.defmock(WebsockexNova.LoggingHandlerMock, for: WebsockexNova.Behaviors.LoggingHandler)
Mox.defmock(WebsockexNova.MetricsCollectorMock, for: WebsockexNova.Behaviors.MetricsCollector)
# Mox.defmock(WebsockexNova.ConnectionManagerMock, for: WebsockexNova.ConnectionManagerBehaviour)

# Mox.set_mox_global()

### see in mix.exs where it is loaded already
# ["#{__DIR__}", "support/**/*.ex"]
# |> Path.join()
# |> Path.wildcard()
# |> Enum.each(&Code.require_file/1)
### end of see in mix.exs where it is loaded already
