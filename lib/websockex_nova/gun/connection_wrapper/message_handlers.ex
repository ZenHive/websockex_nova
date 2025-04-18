defmodule WebsockexNova.Gun.ConnectionWrapper.MessageHandlers do
  @moduledoc """
  Handles Gun message processing for the ConnectionWrapper.

  This module provides a set of functions for handling different types of Gun messages,
  organized by category (connection lifecycle, WebSocket, HTTP, error messages).
  Each handler receives the relevant parameters and the current state, and returns
  an updated state.
  """

  alias WebsockexNova.Gun.ConnectionState
  alias WebsockexNova.Gun.Helpers.BehaviorHelpers

  require Logger

  @doc """
  Notifies a callback process of an event.

  ## Parameters

  * `callback_pid` - PID of the process to notify (or nil)
  * `message` - Message to send

  ## Returns

  * `:ok`
  """
  @spec notify(pid() | nil, term()) :: :ok
  def notify(nil, message) do
    Logger.debug("No callback PID provided, can't send message: #{inspect(message)}")
    :ok
  end

  # @doc """
  # Notifies the callback process of a WebSocket event.

  # ## Parameters

  # * `callback_pid` - PID of the callback process to notify, if any
  # * `message` - The message to send to the callback
  # """
  def notify(callback_pid, message) when is_pid(callback_pid) do
    Logger.debug("→ Sending message to callback #{inspect(callback_pid)}: #{inspect(message)}")

    if Process.alive?(callback_pid) do
      send(callback_pid, {:websockex_nova, message})
      Logger.debug("✓ Message sent to callback: #{inspect(message)}")
    else
      Logger.error("✗ Callback process #{inspect(callback_pid)} is not alive, message not sent")
    end

    :ok
  end

  #
  # Connection lifecycle message handlers
  #

  @doc """
  Handles the `:gun_up` message when a connection is established.

  ## Parameters

  * `gun_pid` - The Gun connection PID
  * `protocol` - The protocol that was negotiated
  * `state` - Current connection state

  ## Returns

  `{:noreply, updated_state}`
  """
  @spec handle_connection_up(pid(), atom(), ConnectionState.t()) ::
          {:noreply, ConnectionState.t()}
  def handle_connection_up(gun_pid, protocol, state) do
    Logger.debug("Gun connection established with protocol: #{inspect(protocol)}")

    # Update state
    state =
      state
      |> ConnectionState.update_gun_pid(gun_pid)
      |> ConnectionState.update_status(:connected)
      |> ConnectionState.reset_reconnect_attempts()

    # Notify callback using connection_up message which test is expecting
    Logger.debug("Sending connection_up notification with protocol: #{inspect(protocol)}")
    notify(state.callback_pid, {:connection_up, protocol})

    # Call behavior callback for connection established
    extra_info = %{protocol: protocol}

    state =
      case BehaviorHelpers.call_handle_connect(state, extra_info) do
        {:ok, updated_state} ->
          updated_state

        {:reply, frame_type, data, updated_state} ->
          # If a reply is requested, we'll need to find an active websocket stream
          # to send the frame on. If none is available, we'll just log a warning.
          if websocket_stream = find_websocket_stream(updated_state) do
            :gun.ws_send(updated_state.gun_pid, websocket_stream, {frame_type, data})
          else
            Logger.warning("Cannot send frame: no active websocket stream available")
          end

          updated_state

        {:close, code, reason, updated_state} ->
          # Similarly, if a close is requested, we need a stream
          if websocket_stream = find_websocket_stream(updated_state) do
            :gun.ws_send(updated_state.gun_pid, websocket_stream, {:close, code, reason})
          else
            Logger.warning("Cannot send close frame: no active websocket stream available")
          end

          updated_state

        {:stop, _reason, updated_state} ->
          # We'll let the caller handle the stop action
          updated_state

        {:error, _reason} ->
          # If there's an error, just keep the original state
          state
      end

    {:noreply, state}
  end

  @doc """
  Handles the `:gun_down` message when a connection is lost.

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
  @spec handle_connection_down(
          pid(),
          atom(),
          term(),
          ConnectionState.t(),
          [reference()] | nil,
          [reference()] | nil
        ) ::
          {:noreply, ConnectionState.t()}
          | {:noreply, {:reconnect, ConnectionState.t()}}
          | {:stop, term(), ConnectionState.t()}
  def handle_connection_down(_gun_pid, protocol, reason, state, killed_streams \\ [], _unprocessed_streams \\ []) do
    Logger.debug("Gun connection down: #{inspect(reason)}, protocol: #{inspect(protocol)}")

    # Log which streams were killed
    if !Enum.empty?(killed_streams) do
      Logger.debug("Streams killed on disconnect: #{inspect(killed_streams)}")
    end

    # Update state and clean up killed streams
    state =
      state
      |> ConnectionState.update_status(:disconnected)
      |> ConnectionState.record_error(reason)
      |> clean_up_killed_streams(killed_streams)

    # This message pattern must match what the test expects
    Logger.debug("Sending connection_down notification: protocol=#{inspect(protocol)}, reason=#{inspect(reason)}")

    notify(state.callback_pid, {:connection_down, protocol, reason})

    # Call behavior callback for disconnection
    result = BehaviorHelpers.call_handle_disconnect(state, reason)

    # Handle the result of the callback
    case result do
      {:ok, updated_state} ->
        # No reconnection needed
        {:noreply, updated_state}

      {:reconnect, updated_state} ->
        # Delegate reconnection to the ConnectionManager through the main module
        # We'll signal this by returning a special tuple
        {:noreply, {:reconnect, updated_state}}

      {:stop, reason, updated_state} ->
        # Signal that we should stop
        {:stop, reason, updated_state}
    end
  end

  # Helper function to clean up killed streams safely
  defp clean_up_killed_streams(state, killed_streams) when is_list(killed_streams) do
    ConnectionState.remove_streams(state, killed_streams)
  end

  defp clean_up_killed_streams(state, _), do: state

  #
  # WebSocket message handlers
  #

  @doc """
  Handles the `:gun_upgrade` message when a WebSocket upgrade succeeds.

  ## Parameters

  * `gun_pid` - The Gun connection PID
  * `stream_ref` - Reference to the stream that was upgraded
  * `headers` - Response headers from the upgrade
  * `state` - Current connection state

  ## Returns

  `{:noreply, updated_state}`
  """
  @spec handle_websocket_upgrade(pid(), reference(), list(), ConnectionState.t()) ::
          {:noreply, ConnectionState.t()}
  def handle_websocket_upgrade(_gun_pid, stream_ref, headers, state) do
    Logger.debug("WebSocket upgrade successful for stream: #{inspect(stream_ref)}")

    # Update state
    state =
      state
      |> ConnectionState.update_status(:websocket_connected)
      |> ConnectionState.update_stream(stream_ref, :websocket)

    # Notify callback
    Logger.debug("Sending websocket_upgrade notification: stream=#{inspect(stream_ref)}")
    notify(state.callback_pid, {:websocket_upgrade, stream_ref, headers})

    # Call behavior callback for connect again, with updated info
    protocol = extract_protocol_from_headers(headers)
    path = Map.get(state.options, :path, "/")

    extra_info = %{
      protocol: protocol,
      path: path,
      stream_ref: stream_ref,
      headers: headers
    }

    state =
      case BehaviorHelpers.call_handle_connect(state, extra_info) do
        {:ok, updated_state} ->
          updated_state

        {:reply, frame_type, data, updated_state} ->
          # Send the frame on the newly established websocket stream
          :gun.ws_send(updated_state.gun_pid, stream_ref, {frame_type, data})
          updated_state

        {:close, code, reason, updated_state} ->
          # Send a close frame if requested
          :gun.ws_send(updated_state.gun_pid, stream_ref, {:close, code, reason})
          updated_state

        {:stop, _reason, updated_state} ->
          # Let the caller handle the stop
          updated_state

        {:error, _reason} ->
          # If there's an error, just keep the state as is
          state
      end

    {:noreply, state}
  end

  @doc """
  Handles the `:gun_ws` message when a WebSocket frame is received.

  ## Parameters

  * `gun_pid` - The Gun connection PID
  * `stream_ref` - Reference to the stream that received the frame
  * `frame` - The WebSocket frame
  * `state` - Current connection state

  ## Returns

  `{:noreply, updated_state}`
  """
  @spec handle_websocket_frame(pid(), reference(), tuple() | atom(), ConnectionState.t()) ::
          {:noreply, ConnectionState.t()}
  def handle_websocket_frame(gun_pid, stream_ref, frame, state) do
    Logger.debug("Received WebSocket frame: #{inspect(frame)}")

    # Handle special case for close frames
    state =
      case frame do
        {:close, code, reason} ->
          Logger.debug("Received close frame for stream: #{inspect(stream_ref)}, code=#{code}, reason=#{inspect(reason)}")

          ConnectionState.remove_stream(state, stream_ref)

        :close ->
          Logger.debug("Received close frame for stream: #{inspect(stream_ref)}")
          ConnectionState.remove_stream(state, stream_ref)

        _ ->
          state
      end

    # Notify callback - this is required for tests to pass
    Logger.debug("Sending websocket_frame notification: stream=#{inspect(stream_ref)}, frame=#{inspect(frame)}")

    notify(state.callback_pid, {:websocket_frame, stream_ref, frame})

    # Extract frame data to pass to behavior callback
    {frame_type, frame_data} = extract_frame_data(frame)

    # Call behavior callback for frame received
    result = BehaviorHelpers.call_handle_frame(state, frame_type, frame_data, stream_ref)

    # Handle response from the callback
    case result do
      {:ok, updated_state} ->
        {:noreply, updated_state}

      {:reply, reply_type, reply_data, updated_state, stream_ref} ->
        # Send reply frame
        :gun.ws_send(gun_pid, stream_ref, {reply_type, reply_data})
        {:noreply, updated_state}

      {:close, code, reason, updated_state, stream_ref} ->
        # Send close frame
        :gun.ws_send(gun_pid, stream_ref, {:close, code, reason})
        {:noreply, updated_state}
    end
  end

  #
  # Error message handlers
  #

  @doc """
  Handles the `:gun_error` message when an error occurs.

  ## Parameters

  * `gun_pid` - The Gun connection PID
  * `stream_ref` - Reference to the stream with the error, or nil
  * `reason` - The error reason
  * `state` - Current connection state

  ## Returns

  `{:noreply, updated_state}`
  """
  @spec handle_error(pid(), reference() | nil, term(), ConnectionState.t()) ::
          {:noreply, ConnectionState.t()}
  def handle_error(_gun_pid, stream_ref, reason, state) do
    Logger.error("Gun error: #{inspect(reason)} for stream: #{inspect(stream_ref)}")

    # Update state and clean up the stream with error
    state =
      state
      |> ConnectionState.record_error(reason)
      |> clean_stream_on_error(stream_ref)

    # Notify callback
    Logger.debug("Sending error notification: stream=#{inspect(stream_ref)}, reason=#{inspect(reason)}")

    notify(state.callback_pid, {:error, stream_ref, reason})

    {:noreply, state}
  end

  #
  # HTTP message handlers
  #

  @doc """
  Handles the `:gun_response` message when an HTTP response is received.

  ## Parameters

  * `gun_pid` - The Gun connection PID
  * `stream_ref` - Reference to the stream
  * `is_fin` - Whether this is the final message
  * `status` - HTTP status code
  * `headers` - HTTP response headers
  * `state` - Current connection state

  ## Returns

  `{:noreply, updated_state}`
  """
  @spec handle_http_response(pid(), reference(), atom(), integer(), list(), ConnectionState.t()) ::
          {:noreply, ConnectionState.t()}
  def handle_http_response(_gun_pid, stream_ref, is_fin, status, headers, state) do
    Logger.debug("HTTP response: #{status} for stream: #{inspect(stream_ref)}")

    # If this is the final message and it's not a successful upgrade, clean up the stream
    state =
      if is_fin == :fin and (status < 200 or status >= 300) do
        Logger.debug("Cleaning up stream after final HTTP response: #{inspect(stream_ref)}")
        ConnectionState.remove_stream(state, stream_ref)
      else
        state
      end

    # Notify callback
    Logger.debug("Sending http_response notification: stream=#{inspect(stream_ref)}, status=#{status}")

    notify(state.callback_pid, {:http_response, stream_ref, is_fin, status, headers})

    {:noreply, state}
  end

  @doc """
  Handles the `:gun_data` message when HTTP data is received.

  ## Parameters

  * `gun_pid` - The Gun connection PID
  * `stream_ref` - Reference to the stream
  * `is_fin` - Whether this is the final message
  * `data` - The response data
  * `state` - Current connection state

  ## Returns

  `{:noreply, updated_state}`
  """
  @spec handle_http_data(pid(), reference(), atom(), binary(), ConnectionState.t()) ::
          {:noreply, ConnectionState.t()}
  def handle_http_data(_gun_pid, stream_ref, is_fin, data, state) do
    Logger.debug("HTTP data received for stream: #{inspect(stream_ref)}")

    # If this is the final message, clean up the stream
    state =
      if is_fin == :fin do
        Logger.debug("Cleaning up stream after final HTTP data: #{inspect(stream_ref)}")
        ConnectionState.remove_stream(state, stream_ref)
      else
        state
      end

    # Notify callback
    Logger.debug("Sending http_data notification: stream=#{inspect(stream_ref)}")
    notify(state.callback_pid, {:http_data, stream_ref, is_fin, data})

    {:noreply, state}
  end

  # Private helper functions

  # Cleans up a stream when an error occurs
  defp clean_stream_on_error(state, nil), do: state

  defp clean_stream_on_error(state, stream_ref) do
    Logger.debug("Cleaning up stream after error: #{inspect(stream_ref)}")
    ConnectionState.remove_stream(state, stream_ref)
  end

  # Find the first active WebSocket stream in the state
  defp find_websocket_stream(state) do
    case Enum.find(state.active_streams, fn {_ref, status} -> status == :websocket end) do
      nil -> nil
      {stream_ref, _} -> stream_ref
    end
  end

  # Extract protocol from headers
  defp extract_protocol_from_headers(headers) do
    case Enum.find(headers, fn {name, _} -> name == "sec-websocket-protocol" end) do
      nil -> nil
      {_, protocol} -> protocol
    end
  end

  # Extract frame type and data from different frame formats
  defp extract_frame_data(frame) do
    case frame do
      {:text, data} -> {:text, data}
      {:binary, data} -> {:binary, data}
      :ping -> {:ping, ""}
      :pong -> {:pong, ""}
      :close -> {:close, ""}
      {:close, code, reason} -> {:close, "#{code}:#{reason}"}
      other -> {:unknown, inspect(other)}
    end
  end
end
