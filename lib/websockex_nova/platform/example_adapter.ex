defmodule WebsockexNova.Platform.ExampleAdapter do
  @moduledoc """
  Example platform adapter using WebsockexNova.Adapter macro.
  Demonstrates the minimal implementation required for a custom adapter.
  """

  use WebsockexNova.Adapter

  @impl WebsockexNova.Behaviors.ConnectionHandler
  def handle_connect(_conn_info, state) do
    # Custom connection logic here
    {:ok, state}
  end

  @impl WebsockexNova.Behaviors.SubscriptionHandler
  def subscribe(channel, params, state) do
    # Custom subscription logic here
    {:subscribed, channel, params, state}
  end

  # All other callbacks have safe defaults from the macro
end
