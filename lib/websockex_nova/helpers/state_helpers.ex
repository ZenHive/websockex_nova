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

  ## Returns

  The updated state map with the new handler and its state.

  ## Note
  `handler_type` must be an atom. The handler state will be stored under the key `{handler_type, :state}` in the handlers map (e.g., `{:auth_handler, :state}`).
  This avoids dynamic atom creation and is safe for all inputs.
  """
  @spec setup_handler(map(), atom(), module(), term()) :: map()
  def setup_handler(state, handler_type, handler_module, handler_options \\ %{}) when is_atom(handler_type) do
    handlers = Map.get(state, :handlers, %{})

    # Try to initialize handler with options if it has an init function
    handler_state =
      if function_exported?(handler_module, :init, 1) do
        case handler_module.init(handler_options) do
          {:ok, init_state} -> init_state
          _ -> handler_options
        end
      else
        handler_options
      end

    # Update both handler module and state (state is now stored under a tuple key)
    updated_handlers =
      handlers
      |> Map.put(handler_type, handler_module)
      |> Map.put({handler_type, :state}, handler_state)

    # Handle case when state doesn't have a handlers map
    Map.put(state, :handlers, updated_handlers)
  end
end
