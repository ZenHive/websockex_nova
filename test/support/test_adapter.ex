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

  # Add handle_platform_message for test compatibility
  def handle_platform_message(message, state) do
    # Simply echo the message back for testing
    {:reply, message, state}
  end

  # The following functions are for test compatibility
  def encode_auth_request(_credentials) do
    {:text, ~s({"method":"auth","params":{}})}
  end

  def encode_subscription_request(channel, _params) do
    {:text, "{\"method\":\"subscribe\",\"params\":{\"channel\":\"#{channel}\"}}"}
  end

  def encode_unsubscription_request(channel) do
    {:text, "{\"method\":\"unsubscribe\",\"params\":{\"channel\":\"#{channel}\"}}"}
  end

  # Define gun_config for test compatibility
  def gun_config(state) do
    %{
      host: state.host,
      port: state.port,
      transport: state.transport,
      path: state.path,
      ws_opts: state.ws_opts
    }
  end
end
