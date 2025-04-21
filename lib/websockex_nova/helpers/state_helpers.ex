defmodule WebsockexNova.Helpers.StateHelpers do
  @moduledoc """
  Helper functions for working with application state.

  This module provides standardized methods for updating and managing
  different types of handler states within the application.
  """

  require Logger

  @doc """
  Updates the auth handler state within the main state map.

  The handler state is stored under the key `{:auth_handler, :state}` in the handlers map.
  """
  @spec update_auth_handler_state(map(), term()) :: map()
  def update_auth_handler_state(state, auth_handler_state) do
    case state do
      %{handlers: handlers} when is_map(handlers) ->
        %{state | handlers: Map.put(handlers, {:auth_handler, :state}, auth_handler_state)}

      _ ->
        # If there's no handlers map yet, create one
        Map.put(state, :handlers, %{{:auth_handler, :state} => auth_handler_state})
    end
  end

  @doc """
  Updates the error handler state within the main state map.

  The handler state is stored under the key `{:error_handler, :state}` in the handlers map.
  """
  @spec update_error_handler_state(map(), term()) :: map()
  def update_error_handler_state(state, error_handler_state) do
    case state do
      %{handlers: handlers} when is_map(handlers) ->
        %{state | handlers: Map.put(handlers, {:error_handler, :state}, error_handler_state)}

      _ ->
        # If there's no handlers map yet, create one
        Map.put(state, :handlers, %{{:error_handler, :state} => error_handler_state})
    end
  end

  @doc """
  Updates the message handler state within the main state map.

  The handler state is stored under the key `{:message_handler, :state}` in the handlers map.
  """
  @spec update_message_handler_state(map(), term()) :: map()
  def update_message_handler_state(state, message_handler_state) do
    case state do
      %{handlers: handlers} when is_map(handlers) ->
        %{state | handlers: Map.put(handlers, {:message_handler, :state}, message_handler_state)}

      _ ->
        # If there's no handlers map yet, create one
        Map.put(state, :handlers, %{{:message_handler, :state} => message_handler_state})
    end
  end

  @doc """
  Updates the connection handler state within the main state map.

  The handler state is stored under the key `{:connection_handler, :state}` in the handlers map.
  """
  @spec update_connection_handler_state(map(), term()) :: map()
  def update_connection_handler_state(state, connection_handler_state) do
    case state do
      %{handlers: handlers} when is_map(handlers) ->
        %{state | handlers: Map.put(handlers, {:connection_handler, :state}, connection_handler_state)}

      _ ->
        # If there's no handlers map yet, create one
        Map.put(state, :handlers, %{{:connection_handler, :state} => connection_handler_state})
    end
  end

  @doc """
  Updates the subscription handler state within the main state map.

  The handler state is stored under the key `{:subscription_handler, :state}` in the handlers map.
  """
  @spec update_subscription_handler_state(map(), term()) :: map()
  def update_subscription_handler_state(state, subscription_handler_state) do
    case state do
      %{handlers: handlers} when is_map(handlers) ->
        %{state | handlers: Map.put(handlers, {:subscription_handler, :state}, subscription_handler_state)}

      _ ->
        # If there's no handlers map yet, create one
        Map.put(state, :handlers, %{{:subscription_handler, :state} => subscription_handler_state})
    end
  end

  @doc """
  Sets up a handler in the state with its initial state.

  ## Parameters

  * `state` - The current state map
  * `handler_type` - The type of handler (must be an atom, e.g., :auth_handler, :error_handler)
  * `handler_module` - The module that implements the handler behavior
  * `handler_options` - Options to pass to the handler's init function (if it has one)
  * `callback_name` - The name of the callback function to call for initializing the handler

  ## Returns

  The updated state map with the new handler and its state.

  ## Note
  `handler_type` must be an atom. The handler state will be stored under the key `{handler_type, :state}` in the handlers map (e.g., `{:auth_handler, :state}`).
  This avoids dynamic atom creation and is safe for all inputs.
  """
  @spec setup_handler(map(), atom(), module(), term(), atom()) :: map()
  def setup_handler(state, handler_type, handler_module, handler_options \\ %{}, callback_name)
      when is_atom(handler_type) and is_atom(callback_name) do
    handlers = Map.get(state, :handlers, %{})

    handler_state =
      if function_exported?(handler_module, callback_name, 1) do
        case apply(handler_module, callback_name, [handler_options]) do
          {:ok, init_state} -> init_state
          _ -> handler_options
        end
      else
        handler_options
      end

    updated_handlers =
      handlers
      |> Map.put(handler_type, handler_module)
      |> Map.put({handler_type, :state}, handler_state)

    Map.put(state, :handlers, updated_handlers)
  end

  @doc """
  Retrieves the host from the state, adapter_state, or config, in that order.
  Returns nil if not found.
  """
  @spec get_host(map()) :: String.t() | nil
  def get_host(%{host: host}) when is_binary(host), do: host
  def get_host(%{adapter_state: %{host: host}}) when is_binary(host), do: host

  def get_host(%{adapter_state: adapter_state, config: config}) when is_map(adapter_state) and is_map(config) do
    get_host(config)
  end

  def get_host(%{adapter_state: adapter_state}) when is_map(adapter_state), do: get_host(adapter_state)
  def get_host(%{config: %{host: host}}) when is_binary(host), do: host
  def get_host(%{config: config}) when is_map(config), do: get_host(config)
  def get_host(_), do: nil

  @doc """
  Retrieves the port from the state, adapter_state, or config, in that order.
  Returns nil if not found.
  """
  @spec get_port(map()) :: non_neg_integer() | nil
  def get_port(%{port: port}) when is_integer(port), do: port
  def get_port(%{adapter_state: %{port: port}}) when is_integer(port), do: port

  def get_port(%{adapter_state: adapter_state, config: config}) when is_map(adapter_state) and is_map(config) do
    get_port(config)
  end

  def get_port(%{adapter_state: adapter_state}) when is_map(adapter_state), do: get_port(adapter_state)
  def get_port(%{config: %{port: port}}) when is_integer(port), do: port
  def get_port(%{config: config}) when is_map(config), do: get_port(config)
  def get_port(_), do: nil

  @doc """
  Retrieves the status from the state, adapter_state, or config, in that order.
  Returns nil if not found.
  """
  @spec get_status(map()) :: atom() | nil
  def get_status(%{status: status}) when is_atom(status), do: status
  def get_status(%{adapter_state: %{status: status}}) when is_atom(status), do: status

  def get_status(%{adapter_state: adapter_state, config: config}) when is_map(adapter_state) and is_map(config) do
    get_status(config)
  end

  def get_status(%{adapter_state: adapter_state}) when is_map(adapter_state), do: get_status(adapter_state)
  def get_status(%{config: %{status: status}}) when is_atom(status), do: status
  def get_status(%{config: config}) when is_map(config), do: get_status(config)
  def get_status(_), do: nil

  @doc """
  Stub for handle_ownership_transfer/2. Not yet implemented.
  """
  def handle_ownership_transfer(_state, _info) do
    raise "handle_ownership_transfer/2 is not implemented. Please implement this function in the appropriate module."
  end
end
