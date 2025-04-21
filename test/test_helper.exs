## Configure Logger to only show warnings and errors
# Logger.configure(level: :none)
# Logger.configure(level: :warning)
# Logger.configure(level: :debug)

ExUnit.start()

["#{__DIR__}", "support/**/*.ex"]
|> Path.join()
|> Path.wildcard()
|> Enum.each(&Code.require_file/1)
