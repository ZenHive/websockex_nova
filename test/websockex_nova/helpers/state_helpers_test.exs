defmodule WebsockexNova.Helpers.StateHelpersTest do
  use ExUnit.Case, async: true

  alias WebsockexNova.Helpers.StateHelpers

  describe "state handler updates" do
    setup do
      state = %{
        handlers: %{
          existing_handler: :some_value
        },
        some_field: "test"
      }

      empty_state = %{some_field: "test"}

      {:ok, state: state, empty_state: empty_state}
    end

    test "update_auth_handler_state with existing handlers", %{state: state} do
      auth_state = %{credentials: %{api_key: "key1"}}
      updated_state = StateHelpers.update_auth_handler_state(state, auth_state)

      assert updated_state.handlers[{:auth_handler, :state}] == auth_state
      assert updated_state.handlers.existing_handler == :some_value
      assert updated_state.some_field == "test"
    end

    test "update_auth_handler_state with no handlers", %{empty_state: state} do
      auth_state = %{credentials: %{api_key: "key1"}}
      updated_state = StateHelpers.update_auth_handler_state(state, auth_state)

      assert updated_state.handlers[{:auth_handler, :state}] == auth_state
      assert updated_state.some_field == "test"
    end

    test "update_error_handler_state with existing handlers", %{state: state} do
      error_state = %{max_retries: 5}
      updated_state = StateHelpers.update_error_handler_state(state, error_state)

      assert updated_state.handlers[{:error_handler, :state}] == error_state
      assert updated_state.handlers.existing_handler == :some_value
      assert updated_state.some_field == "test"
    end

    test "update_error_handler_state with no handlers", %{empty_state: state} do
      error_state = %{max_retries: 5}
      updated_state = StateHelpers.update_error_handler_state(state, error_state)

      assert updated_state.handlers[{:error_handler, :state}] == error_state
      assert updated_state.some_field == "test"
    end

    test "update_message_handler_state with existing handlers", %{state: state} do
      message_state = %{message_count: 10}
      updated_state = StateHelpers.update_message_handler_state(state, message_state)

      assert updated_state.handlers[{:message_handler, :state}] == message_state
      assert updated_state.handlers.existing_handler == :some_value
      assert updated_state.some_field == "test"
    end

    test "update_message_handler_state with no handlers", %{empty_state: state} do
      message_state = %{message_count: 10}
      updated_state = StateHelpers.update_message_handler_state(state, message_state)

      assert updated_state.handlers[{:message_handler, :state}] == message_state
      assert updated_state.some_field == "test"
    end

    test "update_connection_handler_state with existing handlers", %{state: state} do
      conn_state = %{connected_at: 123_456_789}
      updated_state = StateHelpers.update_connection_handler_state(state, conn_state)

      assert updated_state.handlers[{:connection_handler, :state}] == conn_state
      assert updated_state.handlers.existing_handler == :some_value
      assert updated_state.some_field == "test"
    end

    test "update_connection_handler_state with no handlers", %{empty_state: state} do
      conn_state = %{connected_at: 123_456_789}
      updated_state = StateHelpers.update_connection_handler_state(state, conn_state)

      assert updated_state.handlers[{:connection_handler, :state}] == conn_state
      assert updated_state.some_field == "test"
    end

    test "update_subscription_handler_state with existing handlers", %{state: state} do
      sub_state = %{subscriptions: ["channel1"]}
      updated_state = StateHelpers.update_subscription_handler_state(state, sub_state)

      assert updated_state.handlers[{:subscription_handler, :state}] == sub_state
      assert updated_state.handlers.existing_handler == :some_value
      assert updated_state.some_field == "test"
    end

    test "update_subscription_handler_state with no handlers", %{empty_state: state} do
      sub_state = %{subscriptions: ["channel1"]}
      updated_state = StateHelpers.update_subscription_handler_state(state, sub_state)

      assert updated_state.handlers[{:subscription_handler, :state}] == sub_state
      assert updated_state.some_field == "test"
    end
  end

  describe "setup_handler" do
    setup do
      state = %{
        handlers: %{
          existing_handler: :some_value
        },
        some_field: "test"
      }

      empty_state = %{some_field: "test"}

      {:ok, state: state, empty_state: empty_state}
    end

    # Define a mock handler module for testing
    defmodule MockHandlerWithInit do
      @moduledoc false
      def init(options) do
        {:ok, Map.put(options, :initialized, true)}
      end
    end

    defmodule MockHandlerNoInit do
      # No init function
      @moduledoc false
    end

    defmodule MockHandlerErrorInit do
      @moduledoc false
      def init(_options) do
        {:error, :some_error}
      end
    end

    test "setup_handler with module having init function", %{state: state} do
      handler_options = %{option1: "value1"}
      updated_state = StateHelpers.setup_handler(state, :test_handler, MockHandlerWithInit, handler_options)

      assert updated_state.handlers[:test_handler] == MockHandlerWithInit
      assert updated_state.handlers[{:test_handler, :state}].option1 == "value1"
      assert updated_state.handlers[{:test_handler, :state}].initialized == true
      assert updated_state.handlers.existing_handler == :some_value
    end

    test "setup_handler with module having no init function", %{state: state} do
      handler_options = %{option1: "value1"}
      updated_state = StateHelpers.setup_handler(state, :test_handler, MockHandlerNoInit, handler_options)

      assert updated_state.handlers[:test_handler] == MockHandlerNoInit
      assert updated_state.handlers[{:test_handler, :state}] == handler_options
      assert updated_state.handlers.existing_handler == :some_value
    end

    test "setup_handler with module having init function that returns error", %{state: state} do
      handler_options = %{option1: "value1"}
      updated_state = StateHelpers.setup_handler(state, :test_handler, MockHandlerErrorInit, handler_options)

      assert updated_state.handlers[:test_handler] == MockHandlerErrorInit
      # When init returns error, it should fall back to using handler_options
      assert updated_state.handlers[{:test_handler, :state}] == handler_options
      assert updated_state.handlers.existing_handler == :some_value
    end

    test "setup_handler with no existing handlers", %{empty_state: state} do
      handler_options = %{option1: "value1"}
      updated_state = StateHelpers.setup_handler(state, :test_handler, MockHandlerWithInit, handler_options)

      assert updated_state.handlers[:test_handler] == MockHandlerWithInit
      assert updated_state.handlers[{:test_handler, :state}].option1 == "value1"
      assert updated_state.handlers[{:test_handler, :state}].initialized == true
    end

    test "setup_handler with default options", %{state: state} do
      updated_state = StateHelpers.setup_handler(state, :test_handler, MockHandlerWithInit)

      assert updated_state.handlers[:test_handler] == MockHandlerWithInit
      assert updated_state.handlers[{:test_handler, :state}].initialized == true
      assert Map.has_key?(updated_state.handlers, {:test_handler, :state})
    end
  end

  describe "robust state accessors" do
    alias WebsockexNova.Helpers.StateHelpers

    test "get_host/1 returns host from top-level, adapter_state, config, or nil" do
      assert StateHelpers.get_host(%{host: "a.com"}) == "a.com"
      assert StateHelpers.get_host(%{adapter_state: %{host: "b.com"}}) == "b.com"
      assert StateHelpers.get_host(%{adapter_state: %{other: 1}, config: %{host: "c.com"}}) == "c.com"
      assert StateHelpers.get_host(%{config: %{host: "d.com"}}) == "d.com"
      assert StateHelpers.get_host(%{adapter_state: %{config: %{host: "e.com"}}}) == "e.com"
      assert StateHelpers.get_host(%{}) == nil
      assert StateHelpers.get_host(%{adapter_state: %{}}) == nil
      assert StateHelpers.get_host(%{config: %{}}) == nil
    end

    test "get_port/1 returns port from top-level, adapter_state, config, or nil" do
      assert StateHelpers.get_port(%{port: 123}) == 123
      assert StateHelpers.get_port(%{adapter_state: %{port: 456}}) == 456
      assert StateHelpers.get_port(%{adapter_state: %{other: 1}, config: %{port: 789}}) == 789
      assert StateHelpers.get_port(%{config: %{port: 321}}) == 321
      assert StateHelpers.get_port(%{adapter_state: %{config: %{port: 654}}}) == 654
      assert StateHelpers.get_port(%{}) == nil
      assert StateHelpers.get_port(%{adapter_state: %{}}) == nil
      assert StateHelpers.get_port(%{config: %{}}) == nil
    end

    test "get_status/1 returns status from top-level, adapter_state, config, or nil" do
      assert StateHelpers.get_status(%{status: :ok}) == :ok
      assert StateHelpers.get_status(%{adapter_state: %{status: :foo}}) == :foo
      assert StateHelpers.get_status(%{adapter_state: %{other: 1}, config: %{status: :bar}}) == :bar
      assert StateHelpers.get_status(%{config: %{status: :baz}}) == :baz
      assert StateHelpers.get_status(%{adapter_state: %{config: %{status: :qux}}}) == :qux
      assert StateHelpers.get_status(%{}) == nil
      assert StateHelpers.get_status(%{adapter_state: %{}}) == nil
      assert StateHelpers.get_status(%{config: %{}}) == nil
    end
  end
end
