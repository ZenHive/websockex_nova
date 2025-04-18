defmodule WebsockexNova.Gun.Helpers.BehaviorHelpers do
  @moduledoc """
  Helper functions for calling behavior callbacks consistently.

  This module provides a standardized way to call behavior callbacks,
  handle their responses, and update state accordingly. It ensures
  proper error handling and consistent behavior throughout the application.
  """

  alias WebsockexNova.Gun.ConnectionState

  require Logger

  @doc """
  Calls the connection handler's handle_connect callback.

  Assembles a connection info map from the state, calls the handler,
  and processes the response.

  ## Parameters

  * `state` - The current connection state
  * `extra_info` - Optional extra information to include in the conn_info map

  ## Returns

  `{:ok, updated_state}` or error tuple
  """
  @spec call_handle_connect(ConnectionState.t(), map()) ::
          {:ok, ConnectionState.t()}
          | {:reply, atom(), binary(), ConnectionState.t()}
          | {:close, integer(), binary(), ConnectionState.t()}
          | {:stop, term(), ConnectionState.t()}
          | {:error, term()}
  def call_handle_connect(%ConnectionState{} = state, extra_info \\ %{}) do
    with {:ok, handler_module, handler_state} <- fetch_handler(state),
         conn_info = build_conn_info(state, extra_info),
         {:ok, result} <- call_handler_connect(handler_module, conn_info, handler_state, state) do
      result
    else
      :no_handler ->
        Logger.debug("BehaviorHelpers - Skipping call_handle_connect, no handler_module or handler_state")
        {:ok, state}

      {:error, reason} ->
        Logger.error("BehaviorHelpers - call_handle_connect error: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Calls the connection handler's handle_disconnect callback.

  ## Parameters

  * `state` - The current connection state
  * `reason` - The disconnect reason

  ## Returns

  `{:ok, updated_state}`, `{:reconnect, updated_state}`, or `{:stop, reason, updated_state}`
  """
  @spec call_handle_disconnect(ConnectionState.t(), term()) ::
          {:ok, ConnectionState.t()}
          | {:reconnect, ConnectionState.t()}
          | {:stop, term(), ConnectionState.t()}
  def call_handle_disconnect(%ConnectionState{} = state, reason) do
    with {:ok, handler_module, handler_state} <- fetch_handler(state),
         formatted_reason = format_disconnect_reason(reason),
         {:ok, result} <- call_handler_disconnect(handler_module, formatted_reason, handler_state, state) do
      result
    else
      :no_handler ->
        Logger.debug("BehaviorHelpers - Skipping call_handle_disconnect, no handler_module or handler_state")
        {:ok, state}

      {:error, _} ->
        {:ok, state}
    end
  end

  @doc """
  Calls the connection handler's handle_frame callback.

  ## Parameters

  * `state` - The current connection state
  * `frame_type` - Type of the frame (:text, :binary, etc.)
  * `frame_data` - Data contained in the frame
  * `stream_ref` - Reference to the stream that received the frame

  ## Returns

  `{:ok, updated_state}` or other handler return value with updated state
  """
  @spec call_handle_frame(ConnectionState.t(), atom(), binary(), reference()) ::
          {:ok, ConnectionState.t()}
          | {:reply, atom(), binary(), ConnectionState.t(), reference()}
          | {:close, integer(), binary(), ConnectionState.t(), reference()}
  def call_handle_frame(%ConnectionState{} = state, frame_type, frame_data, stream_ref) do
    with {:ok, handler_module, handler_state} <- fetch_handler(state),
         {:ok, result} <- call_handler_frame(handler_module, frame_type, frame_data, handler_state, state, stream_ref) do
      result
    else
      :no_handler ->
        Logger.debug("BehaviorHelpers - Skipping call_handle_frame, no handler_module or handler_state")
        {:ok, state}

      {:error, _} ->
        {:ok, state}
    end
  end

  @doc """
  Calls the connection handler's handle_timeout callback.

  ## Parameters

  * `state` - The current connection state

  ## Returns

  `{:ok, updated_state}`, `{:reconnect, updated_state}`, or `{:stop, reason, updated_state}`
  """
  @spec call_handle_timeout(ConnectionState.t()) ::
          {:ok, ConnectionState.t()}
          | {:reconnect, ConnectionState.t()}
          | {:stop, term(), ConnectionState.t()}
  def call_handle_timeout(%ConnectionState{} = state) do
    with {:ok, handler_module, handler_state} <- fetch_handler(state),
         true <- function_exported?(handler_module, :handle_timeout, 1) do
      case safe_call(fn -> handler_module.handle_timeout(handler_state) end) do
        {:ok, {:ok, new_handler_state}} ->
          {:ok, ConnectionState.update_connection_handler_state(state, new_handler_state)}

        {:ok, {:reconnect, new_handler_state}} ->
          {:reconnect, ConnectionState.update_connection_handler_state(state, new_handler_state)}

        {:ok, {:stop, stop_reason, new_handler_state}} ->
          {:stop, stop_reason, ConnectionState.update_connection_handler_state(state, new_handler_state)}

        {:ok, other} ->
          Logger.error("Invalid return from handle_timeout: #{inspect(other)}")
          {:ok, state}

        {:error, _} ->
          {:ok, state}
      end
    else
      :no_handler -> {:reconnect, state}
      false -> {:reconnect, state}
    end
  end

  # Private helper functions

  defp fetch_handler(%{handlers: %{connection_handler: mod, connection_handler_state: st}})
       when is_atom(mod) and not is_nil(st),
       do: {:ok, mod, st}

  defp fetch_handler(_), do: :no_handler

  defp build_conn_info(state, extra_info) do
    %{
      host: state.host,
      port: state.port,
      path: Map.get(extra_info, :path, "/"),
      protocol: Map.get(extra_info, :protocol),
      transport: Map.get(state.options, :transport, :tcp)
    }
  end

  defp call_handler_connect(handler_module, conn_info, handler_state, state) do
    fn -> handler_module.handle_connect(conn_info, handler_state) end
    |> safe_call()
    |> case do
      {:ok, {:ok, new_handler_state}} ->
        {:ok, {:ok, ConnectionState.update_connection_handler_state(state, new_handler_state)}}

      {:ok, {:reply, frame_type, data, new_handler_state}} ->
        updated_state = ConnectionState.update_connection_handler_state(state, new_handler_state)
        {:ok, {:reply, frame_type, data, updated_state}}

      {:ok, {:close, code, reason, new_handler_state}} ->
        updated_state = ConnectionState.update_connection_handler_state(state, new_handler_state)
        {:ok, {:close, code, reason, updated_state}}

      {:ok, {:stop, reason, new_handler_state}} ->
        updated_state = ConnectionState.update_connection_handler_state(state, new_handler_state)
        {:ok, {:stop, reason, updated_state}}

      {:ok, other} ->
        Logger.error("Invalid return from handle_connect: #{inspect(other)}")
        {:error, :invalid_handler_return}

      {:error, e} ->
        {:error, e}
    end
  end

  defp call_handler_disconnect(handler_module, formatted_reason, handler_state, state) do
    fn -> handler_module.handle_disconnect(formatted_reason, handler_state) end
    |> safe_call()
    |> case do
      {:ok, {:ok, new_handler_state}} ->
        {:ok, {:ok, ConnectionState.update_connection_handler_state(state, new_handler_state)}}

      {:ok, {:reconnect, new_handler_state}} ->
        {:ok, {:reconnect, ConnectionState.update_connection_handler_state(state, new_handler_state)}}

      {:ok, {:stop, stop_reason, new_handler_state}} ->
        {:ok, {:stop, stop_reason, ConnectionState.update_connection_handler_state(state, new_handler_state)}}

      {:ok, other} ->
        Logger.error("Invalid return from handle_disconnect: #{inspect(other)}")
        {:error, :invalid_handler_return}

      {:error, e} ->
        {:error, e}
    end
  end

  defp call_handler_frame(handler_module, frame_type, frame_data, handler_state, state, stream_ref) do
    fn -> handler_module.handle_frame(frame_type, frame_data, handler_state) end
    |> safe_call()
    |> case do
      {:ok, {:ok, new_handler_state}} ->
        {:ok, {:ok, ConnectionState.update_connection_handler_state(state, new_handler_state)}}

      {:ok, {:reply, reply_type, reply_data, new_handler_state}} ->
        updated_state = ConnectionState.update_connection_handler_state(state, new_handler_state)
        {:ok, {:reply, reply_type, reply_data, updated_state, stream_ref}}

      {:ok, {:close, code, reason, new_handler_state}} ->
        updated_state = ConnectionState.update_connection_handler_state(state, new_handler_state)
        {:ok, {:close, code, reason, updated_state, stream_ref}}

      {:ok, other} ->
        Logger.error("Invalid return from handle_frame: #{inspect(other)}")
        {:error, :invalid_handler_return}

      {:error, e} ->
        {:error, e}
    end
  end

  defp safe_call(fun) do
    {:ok, fun.()}
  rescue
    e ->
      Logger.error("Error in handler callback: #{inspect(e)}")
      {:error, e}
  end

  # Format disconnect reason for the handler
  defp format_disconnect_reason({:remote, code, message}) when is_integer(code) and is_binary(message),
    do: {:remote, code, message}

  defp format_disconnect_reason({:remote, _, _}), do: {:remote, 1006, "Connection closed abnormally"}

  defp format_disconnect_reason({:local, code, message}) when is_integer(code) and is_binary(message),
    do: {:local, code, message}

  defp format_disconnect_reason({:local, _, _}), do: {:local, 1000, "Normal closure"}
  defp format_disconnect_reason(reason), do: {:error, reason}
end
