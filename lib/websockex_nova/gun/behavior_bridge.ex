defmodule WebsockexNova.Gun.BehaviorBridge do
  @moduledoc """
  Connects Gun events to WebsockexNova behavior callbacks.

  This module serves as the bridge between the Gun transport layer and the WebsockexNova
  behavior-based architecture. It translates Gun-specific events into standardized callbacks
  to the appropriate behavior implementations.

  ## Responsibilities

  The BehaviorBridge has the following key responsibilities:

  1. **Event Translation**: Converts Gun-specific messages to behavior-friendly formats
  2. **Routing**: Routes events to the appropriate behavior (ConnectionHandler, MessageHandler, ErrorHandler)
  3. **State Management**: Maintains and updates connection state based on behavior responses
  4. **Response Processing**: Handles behavior return values with appropriate actions
  5. **Error Handling**: Ensures robust error handling throughout the bridge

  ## Integration Points

  The BehaviorBridge integrates with:

  * **Gun Connection Events**: Handles gun_up, gun_down, and other Gun protocol events
  * **WebSocket Frames**: Processes WebSocket frames and routes them to handlers
  * **Connection State**: Updates and manages connection state through transitions
  * **Behavior Callbacks**: Invokes the appropriate callbacks on behavior implementations

  This module is designed to be used internally by the ConnectionWrapper, which acts as
  the main GenServer responsible for receiving and processing Gun messages.
  """

  alias WebsockexNova.Gun.ConnectionManager
  alias WebsockexNova.Gun.ConnectionState
  alias WebsockexNova.Gun.Helpers.BehaviorHelpers

  require Logger

  # Jason is used for JSON decoding in message handling
  @json_library Jason

  @doc """
  Handles the `:gun_up` message when a connection is established.

  Translates this event to a call to the connection handler's handle_connect callback.

  ## Parameters

  * `gun_pid` - The Gun connection PID
  * `protocol` - The protocol that was negotiated
  * `state` - Current connection state

  ## Returns

  `{:noreply, updated_state}` or other appropriate return value
  """
  @spec handle_gun_up(pid() | any(), atom(), ConnectionState.t()) ::
          {:noreply, ConnectionState.t()}
  def handle_gun_up(gun_pid, protocol, state) do
    log_event(:connection, :gun_up, %{protocol: protocol}, state)

    # First update the connection state through the ConnectionManager
    # This ensures the proper state transitions are tracked
    case ConnectionManager.transition_to(state, :connected) do
      {:ok, new_state} ->
        log_event(:connection, :state_transition_connected, %{protocol: protocol}, state)

        # Update the Gun PID in state if needed
        state_with_pid = ConnectionState.update_gun_pid(new_state, gun_pid)

        # Prepare connection info for the behavior callback
        extra_info = %{protocol: protocol}

        # Call the connection handler's handle_connect callback
        case BehaviorHelpers.call_handle_connect(state_with_pid, extra_info) do
          {:ok, updated_state} ->
            # No special action needed, just return the updated state
            log_event(:connection, :no_reconnect_requested, %{reason: :normal}, updated_state)
            {:noreply, updated_state}

          {:reply, _frame_type, _data, updated_state} ->
            log_event(:message, :frame_send_on_connect, %{protocol: protocol}, state)
            {:noreply, updated_state}

          {:close, code, reason, updated_state} ->
            log_event(:connection, :close_on_connect, %{code: code, reason: reason}, updated_state)
            {:stop, {:close_requested, code, reason}, updated_state}

          {:stop, reason, updated_state} ->
            # Handler wants to stop the process
            log_event(:error, :stop_requested, %{stop_reason: reason}, updated_state)
            {:stop, reason, updated_state}

          other ->
            log_event(:error, :unexpected_return_handle_connect, %{other: other}, state_with_pid)
            {:noreply, state_with_pid}
        end

      {:error, reason} ->
        log_event(:error, :failed_transition_connected, %{reason: reason}, state)
        {:noreply, state}
    end
  end

  @doc """
  Handles the `:gun_down` message when a connection is lost.

  Translates this event to a call to the connection handler's handle_disconnect callback.

  ## Parameters

  * `gun_pid` - The Gun connection PID
  * `protocol` - The protocol that was in use
  * `reason` - Reason for the connection loss
  * `state` - Current connection state
  * `killed_streams` - List of stream references that were killed
  * `unprocessed_streams` - List of stream references with unprocessed data

  ## Returns

  * `{:noreply, updated_state}` - Standard response
  * `{:noreply, {:reconnect, updated_state}}` - Request reconnection
  * `{:stop, reason, updated_state}` - Request process termination
  """
  @spec handle_gun_down(
          pid() | any(),
          atom(),
          term(),
          ConnectionState.t(),
          [reference()] | nil,
          [reference()] | nil
        ) ::
          {:noreply, ConnectionState.t()}
          | {:noreply, {:reconnect, ConnectionState.t()}}
          | {:stop, term(), ConnectionState.t()}
  def handle_gun_down(
        _gun_pid,
        _protocol,
        reason,
        state,
        killed_streams \\ [],
        _unprocessed_streams \\ []
      ) do
    log_event(:connection, :gun_down, %{reason: reason}, state)

    # First transition to the disconnected state
    case ConnectionManager.transition_to(state, :disconnected, %{reason: reason}) do
      {:ok, disconnected_state} ->
        # Clean up killed streams
        state_with_streams_removed =
          if Enum.empty?(killed_streams) do
            disconnected_state
          else
            ConnectionState.remove_streams(disconnected_state, killed_streams)
          end

        # Format reason in a way the connection handler expects
        formatted_reason = format_disconnect_reason(reason)

        # Call the connection handler's handle_disconnect callback
        case BehaviorHelpers.call_handle_disconnect(state_with_streams_removed, formatted_reason) do
          {:ok, updated_state} ->
            log_event(:connection, :no_reconnect_requested, %{reason: reason}, updated_state)
            {:noreply, updated_state}

          {:reconnect, updated_state} ->
            log_event(:connection, :reconnect_requested, %{reason: reason}, updated_state)
            {:noreply, {:reconnect, updated_state}}

          {:stop, stop_reason, updated_state} ->
            log_event(:connection, :stop_requested, %{stop_reason: stop_reason}, updated_state)
            {:stop, stop_reason, updated_state}
        end

      {:error, transition_reason} ->
        log_event(:error, :failed_transition_disconnected, %{reason: transition_reason}, state)
        {:noreply, state}
    end
  end

  @doc """
  Handles WebSocket frames received from Gun.

  Processes the frame and routes it to the appropriate handler.

  ## Parameters

  * `gun_pid` - The Gun connection PID
  * `stream_ref` - The stream reference for the frame
  * `frame` - The WebSocket frame (as a tuple like `{:text, data}`)
  * `state` - Current connection state

  ## Returns

  * `{:noreply, updated_state}` - Standard response
  * `{:reply, frame_type, data, updated_state, stream_ref}` - Response to send
  * `{:stop, reason, updated_state}` - Stop the process
  """
  @spec handle_websocket_frame(pid() | any(), reference() | any(), tuple(), ConnectionState.t()) ::
          {:noreply, ConnectionState.t()}
          | {:reply, atom(), binary(), ConnectionState.t(), reference() | any()}
          | {:stop, term(), ConnectionState.t()}
  def handle_websocket_frame(gun_pid, stream_ref, frame, state) do
    {frame_type, frame_data} = normalize_frame(frame)
    log_event(:message, :websocket_frame, %{frame_type: frame_type, frame_data: frame_data}, state)

    handle_frame_result(
      BehaviorHelpers.call_handle_frame(state, frame_type, frame_data, stream_ref),
      gun_pid,
      stream_ref,
      frame_type,
      frame_data,
      state
    )
  end

  # Handles the result of call_handle_frame/4 for handle_websocket_frame/4
  defp handle_frame_result({:ok, handler_state}, gun_pid, stream_ref, :text, frame_data, _state) do
    process_text_message(gun_pid, stream_ref, frame_data, handler_state)
  end

  defp handle_frame_result(
         {:ok, handler_state},
         _gun_pid,
         _stream_ref,
         _frame_type,
         _frame_data,
         _state
       ) do
    {:noreply, handler_state}
  end

  defp handle_frame_result(
         {:reply, reply_frame_type, reply_data, updated_state, stream_ref},
         _gun_pid,
         _stream_ref,
         _frame_type,
         _frame_data,
         _state
       ) do
    {:reply, reply_frame_type, reply_data, updated_state, stream_ref}
  end

  defp handle_frame_result(
         {:close, code, reason, updated_state, stream_ref},
         _gun_pid,
         _stream_ref,
         _frame_type,
         _frame_data,
         _state
       ) do
    {:reply, :close, {code, reason}, updated_state, stream_ref}
  end

  @doc """
  Handles WebSocket upgrades received from Gun.

  Transitions the state to websocket_connected and notifies the connection handler.

  ## Parameters

  * `gun_pid` - The Gun connection PID
  * `stream_ref` - The stream reference for the upgrade
  * `headers` - The response headers received
  * `state` - Current connection state

  ## Returns

  * `{:noreply, updated_state}` - Standard response
  * `{:stop, reason, updated_state}` - Stop the process
  """
  @spec handle_websocket_upgrade(pid() | any(), reference() | any(), list(), ConnectionState.t()) ::
          {:noreply, ConnectionState.t()} | {:stop, term(), ConnectionState.t()}
  def handle_websocket_upgrade(_gun_pid, stream_ref, headers, state) do
    log_event(:connection, :websocket_upgrade, %{stream_ref: stream_ref, headers: headers}, state)

    # First transition to websocket_connected state
    case ConnectionManager.transition_to(state, :websocket_connected) do
      {:ok, ws_connected_state} ->
        # Add the stream reference to the active streams list
        state_with_stream =
          ConnectionState.add_active_stream(ws_connected_state, stream_ref, %{
            type: :websocket,
            created_at: System.monotonic_time(:millisecond)
          })

        # Extract protocol from headers if present
        ws_protocol =
          Enum.find_value(headers, nil, fn
            {"sec-websocket-protocol", protocol} -> protocol
            _ -> nil
          end)

        # Call connection handler with extra info about the WebSocket upgrade
        extra_info = %{
          protocol: ws_protocol,
          headers: headers,
          stream_ref: stream_ref
        }

        # Call the connection handler
        case BehaviorHelpers.call_handle_connect(state_with_stream, extra_info) do
          {:ok, updated_state} ->
            # No special action needed
            {:noreply, updated_state}

          {:reply, frame_type, data, updated_state} ->
            # Send a frame right after upgrade
            {:reply, frame_type, data, updated_state, stream_ref}

          {:close, code, reason, updated_state} ->
            # Close the WebSocket right after upgrade
            {:reply, :close, {code, reason}, updated_state, stream_ref}

          {:stop, reason, updated_state} ->
            # Stop the process
            {:stop, reason, updated_state}
        end

      {:error, transition_reason} ->
        log_event(
          :error,
          :failed_transition_websocket_connected,
          %{reason: transition_reason},
          state
        )

        {:noreply, state}
    end
  end

  @doc """
  Handles errors encountered during Gun operations.

  Routes the error to the error handler for processing.

  ## Parameters

  * `error` - The error that occurred
  * `context` - Additional context about the error
  * `state` - Current connection state

  ## Returns

  * `{:noreply, updated_state}` - Continue with the updated state
  * `{:noreply, {:reconnect, updated_state}}` - Attempt reconnection
  * `{:stop, reason, updated_state}` - Stop the process
  """
  @spec handle_error(term(), map(), ConnectionState.t()) ::
          {:noreply, ConnectionState.t()}
          | {:noreply, {:reconnect, ConnectionState.t()}}
          | {:stop, term(), ConnectionState.t()}
  def handle_error(error, context, state) do
    log_event(:error, :handle_error, %{error: error, context: context}, state)

    # Record the error in the state
    state_with_error = ConnectionState.record_error(state, error)

    # First, call the error handler's log_error callback
    error_handler = Map.get(state.handlers, :error_handler)
    error_handler_state = Map.get(state.handlers, :error_handler_state)

    if error_handler && error_handler_state do
      # Log the error
      error_handler.log_error(error, context, error_handler_state)

      # Now call the handle_error callback
      case error_handler.handle_error(error, context, error_handler_state) do
        {:ok, new_handler_state} ->
          # No special action needed
          updated_state = put_in(state_with_error.handlers.error_handler_state, new_handler_state)
          {:noreply, updated_state}

        {:reconnect, new_handler_state} ->
          # Attempt immediate reconnection
          updated_state = put_in(state_with_error.handlers.error_handler_state, new_handler_state)
          {:noreply, {:reconnect, updated_state}}

        {:retry, _delay, new_handler_state} ->
          # Retry after a delay
          # In a real implementation, we'd need to set up a timer here
          # For this bridge implementation, we'll treat it like reconnect
          updated_state = put_in(state_with_error.handlers.error_handler_state, new_handler_state)
          {:noreply, {:reconnect, updated_state}}

        {:stop, reason, new_handler_state} ->
          # Stop the process
          updated_state = put_in(state_with_error.handlers.error_handler_state, new_handler_state)
          {:stop, reason, updated_state}
      end
    else
      # No error handler available
      {:noreply, state_with_error}
    end
  end

  @doc """
  Determines if reconnection should be attempted after an error.

  Consults the error handler to make this decision.

  ## Parameters

  * `error` - The error that caused the disconnection
  * `attempt` - The current reconnection attempt number
  * `state` - Current connection state

  ## Returns

  * `{true, delay}` - Should reconnect after the specified delay
  * `{false, _}` - Should not reconnect
  """
  @spec should_reconnect?(term(), non_neg_integer(), ConnectionState.t()) ::
          {boolean(), non_neg_integer() | nil}
  def should_reconnect?(error, attempt, state) do
    log_event(:connection, :should_reconnect, %{error: error, attempt: attempt}, state)

    error_handler = Map.get(state.handlers, :error_handler)
    error_handler_state = Map.get(state.handlers, :error_handler_state)

    if error_handler && error_handler_state &&
         function_exported?(error_handler, :should_reconnect?, 3) do
      # Call the error handler's should_reconnect? callback
      error_handler.should_reconnect?(error, attempt, error_handler_state)
    else
      # Default behavior: reconnect up to 5 times with increasing delay
      {attempt <= 5, attempt * 1000}
    end
  end

  # Private helpers

  # Normalizes a WebSocket frame into a consistent {type, data} format
  defp normalize_frame({:text, data}), do: {:text, data}
  defp normalize_frame({:binary, data}), do: {:binary, data}
  defp normalize_frame(:ping), do: {:ping, ""}
  defp normalize_frame({:ping, data}), do: {:ping, data}
  defp normalize_frame(:pong), do: {:pong, ""}
  defp normalize_frame({:pong, data}), do: {:pong, data}
  defp normalize_frame(:close), do: {:close, ""}
  defp normalize_frame({:close, code, reason}), do: {:close, "#{code}:#{reason}"}
  defp normalize_frame(other), do: {:unknown, inspect(other)}

  # Refactored process_text_message/4 for clarity and reduced nesting
  defp process_text_message(_gun_pid, stream_ref, frame_data, state) do
    message_handler = Map.get(state.handlers, :message_handler)
    message_handler_state = Map.get(state.handlers, :message_handler_state)

    if is_nil(message_handler) or is_nil(message_handler_state) do
      {:noreply, state}
    else
      do_process_text_message(message_handler, message_handler_state, frame_data, state, stream_ref)
    end
  end

  # Handles JSON decoding, validation, and message processing for text frames
  defp do_process_text_message(
         message_handler,
         message_handler_state,
         frame_data,
         state,
         stream_ref
       ) do
    with {:ok, decoded} <- decode_json(frame_data),
         {:ok, validated_message} <- validate_message(message_handler, decoded) do
      result = handle_message(message_handler, validated_message, message_handler_state)
      handle_message_result(result, message_handler, state, stream_ref)
    else
      {:error, reason, _message} ->
        log_event(:error, :invalid_message, %{reason: reason}, state)
        {:noreply, state}

      {:error, reason} ->
        log_event(:error, :failed_decode_json, %{reason: reason}, state)
        {:noreply, state}

      exception ->
        log_event(:error, :exception_message_processing, %{exception: exception}, state)
        {:noreply, state}
    end
  rescue
    e ->
      log_event(:error, :exception_message_processing, %{exception: e}, state)
      {:noreply, state}
  end

  # Decodes JSON using the configured library
  defp decode_json(frame_data) do
    @json_library.decode(frame_data)
  end

  # Validates the decoded message
  defp validate_message(message_handler, decoded) do
    message_handler.validate_message(decoded)
  end

  # Handles the validated message
  defp handle_message(message_handler, validated_message, message_handler_state) do
    message_handler.handle_message(validated_message, message_handler_state)
  end

  # Handles the result of handle_message/3
  defp handle_message_result({:ok, new_handler_state}, _message_handler, state, _stream_ref) do
    updated_state = put_in(state.handlers.message_handler_state, new_handler_state)
    {:noreply, updated_state}
  end

  defp handle_message_result(
         {:reply, reply_message, new_handler_state},
         message_handler,
         state,
         stream_ref
       ) do
    case message_handler.encode_message(reply_message, new_handler_state) do
      {:ok, frame_type, encoded_data} ->
        updated_state = put_in(state.handlers.message_handler_state, new_handler_state)
        {:reply, frame_type, encoded_data, updated_state, stream_ref}

      {:error, reason} ->
        log_event(:error, :error_encoding_message, %{reason: reason}, state)
        updated_state = put_in(state.handlers.message_handler_state, new_handler_state)
        {:noreply, updated_state}
    end
  end

  defp handle_message_result(
         {:reply_many, messages, new_handler_state},
         message_handler,
         state,
         stream_ref
       ) do
    log_event(:message, :reply_many_not_implemented, %{messages: messages}, state)
    [first_message | _rest] = messages

    case message_handler.encode_message(first_message, new_handler_state) do
      {:ok, frame_type, encoded_data} ->
        updated_state = put_in(state.handlers.message_handler_state, new_handler_state)
        {:reply, frame_type, encoded_data, updated_state, stream_ref}

      {:error, reason} ->
        log_event(:error, :error_encoding_message, %{reason: reason}, state)
        updated_state = put_in(state.handlers.message_handler_state, new_handler_state)
        {:noreply, updated_state}
    end
  end

  defp handle_message_result(
         {:close, code, reason, new_handler_state},
         _message_handler,
         state,
         stream_ref
       ) do
    updated_state = put_in(state.handlers.message_handler_state, new_handler_state)
    {:reply, :close, {code, reason}, updated_state, stream_ref}
  end

  defp handle_message_result(
         {:error, reason, new_handler_state},
         _message_handler,
         state,
         _stream_ref
       ) do
    log_event(:error, :error_processing_message, %{reason: reason}, state)
    updated_state = put_in(state.handlers.message_handler_state, new_handler_state)
    {:noreply, updated_state}
  end

  # Formats disconnect reason for the connection handler
  defp format_disconnect_reason(:normal) do
    {:remote, 1000, "Connection closed normally"}
  end

  defp format_disconnect_reason(:closed) do
    {:remote, 1000, "Connection closed by server"}
  end

  defp format_disconnect_reason(:timeout) do
    {:error, :timeout}
  end

  defp format_disconnect_reason(:econnrefused) do
    {:error, :connection_refused}
  end

  defp format_disconnect_reason(other) do
    {:error, other}
  end

  # Logging helpers
  defp log_event(:connection, event, context, state) do
    if Map.has_key?(state, :logging_handler) and
         function_exported?(state.logging_handler, :log_connection_event, 3) do
      state.logging_handler.log_connection_event(event, context, state)
    else
      Logger.info("[CONNECTION] #{inspect(event)} | #{inspect(context)}")
    end
  end

  defp log_event(:message, event, context, state) do
    if Map.has_key?(state, :logging_handler) and
         function_exported?(state.logging_handler, :log_message_event, 3) do
      state.logging_handler.log_message_event(event, context, state)
    else
      Logger.debug("[MESSAGE] #{inspect(event)} | #{inspect(context)}")
    end
  end

  defp log_event(:error, event, context, state) do
    if Map.has_key?(state, :logging_handler) and
         function_exported?(state.logging_handler, :log_error_event, 3) do
      state.logging_handler.log_error_event(event, context, state)
    else
      Logger.error("[ERROR] #{inspect(event)} | #{inspect(context)}")
    end
  end
end
