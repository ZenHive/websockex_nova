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
    Logger.debug("BehaviorBridge: handling gun_up with protocol: #{inspect(protocol)}")

    # First update the connection state through the ConnectionManager
    # This ensures the proper state transitions are tracked
    case ConnectionManager.transition_to(state, :connected) do
      {:ok, new_state} ->
        Logger.debug("BehaviorBridge: State transitioned to :connected")

        # Update the Gun PID in state if needed
        state_with_pid = ConnectionState.update_gun_pid(new_state, gun_pid)

        # Prepare connection info for the behavior callback
        extra_info = %{protocol: protocol}

        # Call the connection handler's handle_connect callback
        case BehaviorHelpers.call_handle_connect(state_with_pid, extra_info) do
          {:ok, updated_state} ->
            # No special action needed, just return the updated state
            {:noreply, updated_state}

          {:reply, _frame_type, _data, updated_state} ->
            # Handler wants to send a frame, but we may not have a WebSocket stream yet
            # We'll just log this and ignore the reply for now - in a real implementation
            # we might want to queue this message for later delivery
            Logger.info("Connection handler requested frame send on connect, but no stream available yet")
            {:noreply, updated_state}

          {:close, code, reason, updated_state} ->
            # Handler wants to close the connection - unusual but we'll respect it
            Logger.warning("Connection handler requested close on connect: code=#{code}, reason=#{reason}")
            {:stop, {:close_requested, code, reason}, updated_state}

          {:stop, reason, updated_state} ->
            # Handler wants to stop the process
            {:stop, reason, updated_state}

          other ->
            # Unexpected return - log and continue with original state
            Logger.error("Unexpected return from handle_connect: #{inspect(other)}")
            {:noreply, state_with_pid}
        end

      {:error, reason} ->
        # Could not transition to connected state
        Logger.error("BehaviorBridge: Failed to transition to :connected state: #{inspect(reason)}")
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
  def handle_gun_down(_gun_pid, _protocol, reason, state, killed_streams \\ [], _unprocessed_streams \\ []) do
    Logger.debug("BehaviorBridge: handling gun_down with reason: #{inspect(reason)}")

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
            # No reconnection requested
            Logger.debug("BehaviorBridge: Connection handler did not request reconnection")
            {:noreply, updated_state}

          {:reconnect, updated_state} ->
            # Reconnection requested
            Logger.debug("BehaviorBridge: Connection handler requested reconnection")
            {:noreply, {:reconnect, updated_state}}

          {:stop, stop_reason, updated_state} ->
            # Stop requested by handler
            Logger.debug("BehaviorBridge: Connection handler requested stop: #{inspect(stop_reason)}")
            {:stop, stop_reason, updated_state}
        end

      {:error, transition_reason} ->
        # Could not transition to disconnected state
        Logger.error("BehaviorBridge: Failed to transition to :disconnected state: #{inspect(transition_reason)}")
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
    # Extract frame type and data
    {frame_type, frame_data} = normalize_frame(frame)

    Logger.debug("BehaviorBridge: handling websocket frame type: #{inspect(frame_type)}")

    # Call the connection handler's handle_frame callback
    case BehaviorHelpers.call_handle_frame(state, frame_type, frame_data, stream_ref) do
      {:ok, handler_state} ->
        # No reply needed from connection handler, check if we should process the message
        if frame_type == :text do
          # For text frames, try to process them as JSON messages
          process_text_message(gun_pid, stream_ref, frame_data, handler_state)
        else
          # For other frame types, just return the updated state
          {:noreply, handler_state}
        end

      {:reply, reply_frame_type, reply_data, updated_state, ^stream_ref} ->
        # Connection handler wants to send a reply
        {:reply, reply_frame_type, reply_data, updated_state, stream_ref}

      {:close, code, reason, updated_state, ^stream_ref} ->
        # Connection handler wants to close the connection
        {:reply, :close, {code, reason}, updated_state, stream_ref}
    end
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
    Logger.debug("BehaviorBridge: handling websocket upgrade")

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
        # Could not transition to websocket_connected state
        Logger.error("BehaviorBridge: Failed to transition to :websocket_connected state: #{inspect(transition_reason)}")
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
    Logger.debug("BehaviorBridge: handling error: #{inspect(error)}")

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
  @spec should_reconnect?(term(), non_neg_integer(), ConnectionState.t()) :: {boolean(), non_neg_integer() | nil}
  def should_reconnect?(error, attempt, state) do
    Logger.debug("BehaviorBridge: checking if should reconnect for error: #{inspect(error)}, attempt: #{attempt}")

    error_handler = Map.get(state.handlers, :error_handler)
    error_handler_state = Map.get(state.handlers, :error_handler_state)

    if error_handler && error_handler_state && function_exported?(error_handler, :should_reconnect?, 3) do
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

  # Processes a text message as JSON, calling the message handler if applicable
  defp process_text_message(_gun_pid, stream_ref, frame_data, state) do
    message_handler = Map.get(state.handlers, :message_handler)
    message_handler_state = Map.get(state.handlers, :message_handler_state)

    if message_handler && message_handler_state do
      try do
        # Try to decode the JSON
        case @json_library.decode(frame_data) do
          {:ok, decoded} ->
            # Validate the message
            case message_handler.validate_message(decoded) do
              {:ok, validated_message} ->
                # Process the message
                case message_handler.handle_message(validated_message, message_handler_state) do
                  {:ok, new_handler_state} ->
                    # No reply needed
                    updated_state = put_in(state.handlers.message_handler_state, new_handler_state)
                    {:noreply, updated_state}

                  {:reply, reply_message, new_handler_state} ->
                    # Send a reply
                    case message_handler.encode_message(reply_message, new_handler_state) do
                      {:ok, frame_type, encoded_data} ->
                        # Update state and return the reply
                        updated_state = put_in(state.handlers.message_handler_state, new_handler_state)
                        {:reply, frame_type, encoded_data, updated_state, stream_ref}

                      {:error, reason} ->
                        # Error encoding the message
                        Logger.error("Error encoding message: #{inspect(reason)}")
                        updated_state = put_in(state.handlers.message_handler_state, new_handler_state)
                        {:noreply, updated_state}
                    end

                  {:reply_many, messages, new_handler_state} ->
                    # In a real implementation, we'd need to handle sending multiple messages
                    # For this bridge implementation, we'll just send the first one
                    Logger.warning("reply_many not fully implemented, sending first message only")
                    [first_message | _rest] = messages

                    case message_handler.encode_message(first_message, new_handler_state) do
                      {:ok, frame_type, encoded_data} ->
                        updated_state = put_in(state.handlers.message_handler_state, new_handler_state)
                        {:reply, frame_type, encoded_data, updated_state, stream_ref}

                      {:error, reason} ->
                        Logger.error("Error encoding message: #{inspect(reason)}")
                        updated_state = put_in(state.handlers.message_handler_state, new_handler_state)
                        {:noreply, updated_state}
                    end

                  {:close, code, reason, new_handler_state} ->
                    # Close the connection
                    updated_state = put_in(state.handlers.message_handler_state, new_handler_state)
                    {:reply, :close, {code, reason}, updated_state, stream_ref}

                  {:error, reason, new_handler_state} ->
                    # Error processing the message
                    Logger.error("Error processing message: #{inspect(reason)}")
                    updated_state = put_in(state.handlers.message_handler_state, new_handler_state)
                    {:noreply, updated_state}
                end

              {:error, reason, _message} ->
                # Invalid message
                Logger.debug("Invalid message: #{inspect(reason)}")
                {:noreply, state}
            end

          {:error, reason} ->
            # Failed to decode JSON
            Logger.debug("Failed to decode JSON: #{inspect(reason)}")
            {:noreply, state}
        end
      rescue
        e ->
          # Exception during message processing
          Logger.error("Exception during message processing: #{inspect(e)}")
          {:noreply, state}
      end
    else
      # No message handler available
      {:noreply, state}
    end
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
end
