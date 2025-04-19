defmodule WebsockexNova.Platform.Echo.AdapterTest do
  @moduledoc """
  The Echo adapter is intentionally minimal and only supports echoing text and JSON messages.
  All advanced features (subscriptions, authentication, ping, etc.) return inert values.
  """

  use ExUnit.Case, async: true

  alias WebsockexNova.Platform.Echo.Adapter, as: EchoAdapter

  describe "handle_platform_message/2" do
    setup do
      {:ok, state} = EchoAdapter.init(%{})
      {:ok, state: state}
    end

    test "echoes plain text", %{state: state} do
      message = "Hello World"
      {:reply, {:text, response}, ^state} = EchoAdapter.handle_platform_message(message, state)
      assert response == "Hello World"
    end

    test "echoes JSON message", %{state: state} do
      message = %{foo: "bar", n: 42}
      {:reply, {:text, json}, ^state} = EchoAdapter.handle_platform_message(message, state)
      assert Jason.decode!(json) == %{"foo" => "bar", "n" => 42}
    end

    test "echoes unknown message types as string", %{state: state} do
      message = 12_345
      {:reply, {:text, response}, ^state} = EchoAdapter.handle_platform_message(message, state)
      assert response == "12345"
    end
  end
end
