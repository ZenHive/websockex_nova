defmodule WebSockexNova.Gun.ConnectionWrapper.MessageHandlers do
  @moduledoc """
  Handles Gun message processing for the ConnectionWrapper.

  This module provides a set of functions for handling different types of Gun messages,
  organized by category (connection lifecycle, WebSocket, HTTP, error messages).
  Each handler receives the relevant parameters and the current state, and returns
  an updated state.
  """

  require Logger
  alias WebSockexNova.Gun.ConnectionState

  @doc """
  Notifies a callback process of an event.

  ## Parameters

  * `callback_pid` - PID of the process to notify (or nil)
  * `message` - Message to send

  ## Returns

  * `:ok`
  """
  @spec notify(pid() | nil, term()) :: :ok
  def notify(nil, _message), do: :ok

  def notify(callback_pid, message) when is_pid(callback_pid) do
    send(callback_pid, {:websockex_nova, message})
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

    # Notify callback
    notify(state.callback_pid, {:connection_up, protocol})

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

  `{:noreply, updated_state}`
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
  def handle_connection_down(
        _gun_pid,
        protocol,
        reason,
        state,
        killed_streams \\ [],
        _unprocessed_streams \\ []
      ) do
    Logger.debug("Gun connection down: #{inspect(reason)}, protocol: #{inspect(protocol)}")

    # Log which streams were killed
    unless Enum.empty?(killed_streams) do
      Logger.debug("Streams killed on disconnect: #{inspect(killed_streams)}")
    end

    # Update state and clean up killed streams
    state =
      state
      |> ConnectionState.update_status(:disconnected)
      |> ConnectionState.record_error(reason)
      |> ConnectionState.remove_streams(killed_streams)

    # Notify callback
    notify(state.callback_pid, {:connection_down, reason})

    {:noreply, state}
  end

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
    notify(state.callback_pid, {:websocket_upgrade, stream_ref, headers})

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
  def handle_websocket_frame(_gun_pid, stream_ref, frame, state) do
    Logger.debug("Received WebSocket frame: #{inspect(frame)}")

    # Handle special case for close frames
    state =
      case frame do
        {:close, _code, _reason} ->
          Logger.debug("Received close frame for stream: #{inspect(stream_ref)}")
          ConnectionState.remove_stream(state, stream_ref)

        :close ->
          Logger.debug("Received close frame for stream: #{inspect(stream_ref)}")
          ConnectionState.remove_stream(state, stream_ref)

        _ ->
          state
      end

    # Notify callback
    notify(state.callback_pid, {:websocket_frame, stream_ref, frame})

    {:noreply, state}
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
end
