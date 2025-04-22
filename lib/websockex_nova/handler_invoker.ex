defmodule WebsockexNova.HandlerInvoker do
  @moduledoc """
  Centralized dispatcher for handler module invocation.

  This module provides a single entry point for invoking any handler function
  (connection, message, subscription, auth, error, etc.) in a uniform way.
  It enables modular, testable, and DRY handler invocation logic.
  """

  @doc """
  Invokes the given function on the specified handler module with the provided args.

  ## Parameters
    - handler_type: atom identifying the handler (e.g., :connection_handler)
    - fun: atom function name to call (e.g., :handle_connect)
    - args: list of arguments to pass to the function
    - handlers: map of handler_type => module

  ## Returns
    - The result of the handler function, or :no_handler if handler is missing,
      or :no_function if the function is not exported by the handler module.
  """
  @spec invoke(atom(), atom(), list(), map()) :: term()
  def invoke(handler_type, fun, args, handlers)
      when is_atom(handler_type) and is_atom(fun) and is_list(args) and is_map(handlers) do
    case Map.get(handlers, handler_type) do
      nil ->
        :no_handler

      handler_mod ->
        if function_exported?(handler_mod, fun, length(args)) do
          apply(handler_mod, fun, args)
        else
          :no_function
        end
    end
  end
end
