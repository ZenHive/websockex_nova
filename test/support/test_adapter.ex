defmodule WebsockexNova.TestAdapter do
  @moduledoc false
  def init(opts) do
    {:ok,
     %{
       host: Map.fetch!(opts, :host),
       port: Map.get(opts, :port, 80),
       transport: Map.get(opts, :transport, :tcp),
       path: Map.get(opts, :path, "/"),
       ws_opts: Map.get(opts, :ws_opts, %{})
     }}
  end
end
