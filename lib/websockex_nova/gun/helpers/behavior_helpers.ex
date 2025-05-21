defmodule WebsockexNova.Gun.Helpers.BehaviorHelpers do
  @moduledoc """
  Helper functions for calling behavior callbacks consistently.

  This module provides a standardized way to call behavior callbacks,
  handle their responses, and update state accordingly. It ensures
  proper error handling and consistent behavior throughout the application.
  """

  alias WebsockexNova.Gun.ConnectionState
  alias WebsockexNova.Helpers.StateHelpers

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
        log_event(:message, :skipping_call_handle_connect, %{}, state)
        {:ok, state}

      {:error, reason} ->
        log_event(:error, :call_handle_connect_error, %{reason: reason}, state)
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
        log_event(:message, :skipping_call_handle_disconnect, %{}, state)
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
         {:ok, result} <-
           call_handler_frame(
             handler_module,
             frame_type,
             frame_data,
             handler_state,
             state,
             stream_ref
           ) do
      result
    else
      :no_handler ->
        log_event(:message, :skipping_call_handle_frame, %{}, state)
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
          log_event(:error, :invalid_return_handle_timeout, %{other: other}, state)
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

  # For frame handling, try both connection_handler and message_handler
  defp fetch_handler(%{handlers: handlers}) do
    cond do
      # Try connection_handler first (for connection lifecycle events)
      is_map_key(handlers, :connection_handler) and is_map_key(handlers, :connection_handler_state) and
      is_atom(handlers.connection_handler) and not is_nil(handlers.connection_handler_state) ->
        {:ok, handlers.connection_handler, handlers.connection_handler_state}
        
      # Fall back to message_handler if available
      is_map_key(handlers, :message_handler) and is_map_key(handlers, :message_handler_state) and
      is_atom(handlers.message_handler) and not is_nil(handlers.message_handler_state) ->
        {:ok, handlers.message_handler, handlers.message_handler_state}
        
      # No suitable handler found
      true -> 
        :no_handler
    end
  end

  defp fetch_handler(_), do: :no_handler

  defp build_conn_info(state, extra_info) do
    %{
      host: StateHelpers.get_host(state),
      port: StateHelpers.get_port(state),
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
        log_event(:error, :invalid_return_handle_connect, %{other: other}, state)
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
        log_event(:error, :invalid_return_handle_disconnect, %{other: other}, state)
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
        
      # Special case for adapters using the optional 5-element reply tuple with custom stream_ref
      {:ok, {:reply, reply_type, reply_data, new_handler_state, custom_stream_ref}} ->
        updated_state = ConnectionState.update_connection_handler_state(state, new_handler_state)
        # Pass through the custom stream_ref (could be :text_frame or an actual stream_ref)
        {:ok, {:reply, reply_type, reply_data, updated_state, custom_stream_ref}}

      {:ok, {:close, code, reason, new_handler_state}} ->
        updated_state = ConnectionState.update_connection_handler_state(state, new_handler_state)
        {:ok, {:close, code, reason, updated_state, stream_ref}}

      {:ok, other} ->
        log_event(:error, :invalid_return_handle_frame, %{other: other}, state)
        {:error, :invalid_handler_return}

      {:error, e} ->
        {:error, e}
    end
  end

  defp safe_call(fun) do
    {:ok, fun.()}
  rescue
    e ->
      log_event(:error, :error_in_handler_callback, %{exception: e}, %{})
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

  # Logging helpers
  # defp log_event(:connection, event, context, state) do
  #   if Map.has_key?(state, :logging_handler) and
  #              function_exported?(state.logging_handler, :log_connection_event, 3) do
  #     state.logging_handler.log_connection_event(event, context, state)
  #   else
  #     Logger.info("[CONNECTION] #{inspect(event)} | #{inspect(context)}")
  #   end
  # end

  defp log_event(:message, event, context, state) do
    if Map.has_key?(state, :logging_handler) and function_exported?(state.logging_handler, :log_message_event, 3) do
      state.logging_handler.log_message_event(event, context, state)
    else
      Logger.debug("[MESSAGE] #{inspect(event)} | #{inspect(context)}")
    end
  end

  defp log_event(:error, event, context, state) do
    if Map.has_key?(state, :logging_handler) and function_exported?(state.logging_handler, :log_error_event, 3) do
      state.logging_handler.log_error_event(event, context, state)
    else
      Logger.error("[ERROR] #{inspect(event)} | #{inspect(context)}")
    end
  end
end
