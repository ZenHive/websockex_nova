defmodule WebsockexNova.HandlerInvokerTest do
  use ExUnit.Case, async: true

  alias WebsockexNova.HandlerInvoker

  defmodule MockConnectionHandler do
    @moduledoc false
    def handle_connect(conn_info, state), do: {:ok, {:connect, conn_info, state}}
    def handle_disconnect(reason, state), do: {:ok, {:disconnect, reason, state}}
    def handle_frame(type, data, state), do: {:ok, {:frame, type, data, state}}
  end

  defmodule MockMessageHandler do
    @moduledoc false
    def handle_message(msg, state), do: {:ok, {:message, msg, state}}
  end

  defmodule MockSubscriptionHandler do
    @moduledoc false
    def subscribe(channel, params, state), do: {:ok, {:subscribe, channel, params, state}}
    def unsubscribe(channel, state), do: {:ok, {:unsubscribe, channel, state}}
  end

  defmodule MockAuthHandler do
    @moduledoc false
    def authenticate(credentials, state), do: {:ok, {:authenticate, credentials, state}}
  end

  defmodule MockErrorHandler do
    @moduledoc false
    def handle_error(error, context, state), do: {:ok, {:error, error, context, state}}
  end

  setup do
    handlers = %{
      connection_handler: MockConnectionHandler,
      message_handler: MockMessageHandler,
      subscription_handler: MockSubscriptionHandler,
      auth_handler: MockAuthHandler,
      error_handler: MockErrorHandler
    }

    %{handlers: handlers}
  end

  test "invoke/3 dispatches to connection_handler handle_connect", %{handlers: handlers} do
    result =
      HandlerInvoker.invoke(:connection_handler, :handle_connect, [%{host: "a"}, :state], handlers)

    assert result == {:ok, {:connect, %{host: "a"}, :state}}
  end

  test "invoke/3 dispatches to message_handler handle_message", %{handlers: handlers} do
    result = HandlerInvoker.invoke(:message_handler, :handle_message, ["msg", :state], handlers)
    assert result == {:ok, {:message, "msg", :state}}
  end

  test "invoke/3 dispatches to subscription_handler subscribe", %{handlers: handlers} do
    result =
      HandlerInvoker.invoke(
        :subscription_handler,
        :subscribe,
        ["chan", %{foo: 1}, :state],
        handlers
      )

    assert result == {:ok, {:subscribe, "chan", %{foo: 1}, :state}}
  end

  test "invoke/3 dispatches to auth_handler authenticate", %{handlers: handlers} do
    result = HandlerInvoker.invoke(:auth_handler, :authenticate, [%{user: "u"}, :state], handlers)
    assert result == {:ok, {:authenticate, %{user: "u"}, :state}}
  end

  test "invoke/3 dispatches to error_handler handle_error", %{handlers: handlers} do
    result =
      HandlerInvoker.invoke(:error_handler, :handle_error, [:err, %{ctx: 1}, :state], handlers)

    assert result == {:ok, {:error, :err, %{ctx: 1}, :state}}
  end

  test "invoke/3 returns :no_handler if handler is missing" do
    handlers = %{}
    result = HandlerInvoker.invoke(:missing_handler, :some_fun, [1, 2], handlers)
    assert result == :no_handler
  end

  test "invoke/3 returns :no_function if function is missing in handler" do
    handlers = %{connection_handler: MockConnectionHandler}
    result = HandlerInvoker.invoke(:connection_handler, :not_a_fun, [1, 2], handlers)
    assert result == :no_function
  end
end
