defmodule WebsockexNova.Gun.ConnectionWrapper.ErrorHandler do
  @moduledoc """
  Standardized error handling for the Gun ConnectionWrapper.

  This module provides consistent error handling patterns for different
  types of errors encountered in the ConnectionWrapper. It ensures that:

  1. Errors are logged with appropriate context
  2. State is properly updated with error information
  3. Streams are cleaned up as needed
  4. Callbacks are notified with consistent error messages
  5. Proper return values are maintained
  """

  alias WebsockexNova.Gun.ConnectionState
  alias WebsockexNova.Gun.ConnectionWrapper.MessageHandlers

  require Logger

  @doc """
  Handles Gun-related connection errors.

  ## Parameters

  * `reason` - The error reason
  * `state` - Current connection state

  ## Returns

  `{:reply, {:error, reason}, state}` - For synchronous contexts
  """
  @spec handle_connection_error(term(), ConnectionState.t()) ::
          {:reply, {:error, term()}, ConnectionState.t()}
  def handle_connection_error(reason, state) do
    Logger.error("Connection error: #{inspect(reason)}")

    updated_state = ConnectionState.record_error(state, reason)

    # Notify callback if available
    if updated_state.callback_pid do
      MessageHandlers.notify(
        updated_state.callback_pid,
        {:connection_error, reason}
      )
    end

    {:reply, {:error, reason}, updated_state}
  end

  @doc """
  Handles stream-related errors.

  ## Parameters

  * `stream_ref` - Reference to the stream with the error
  * `reason` - The error reason
  * `state` - Current connection state

  ## Returns

  `{:reply, {:error, reason}, state}` - For synchronous contexts
  """
  @spec handle_stream_error(reference(), term(), ConnectionState.t()) ::
          {:reply, {:error, term()}, ConnectionState.t()}
  def handle_stream_error(stream_ref, reason, state) do
    Logger.error("Stream error: #{inspect(reason)} for stream: #{inspect(stream_ref)}")

    # Update state with error and clean up the stream
    updated_state =
      state
      |> ConnectionState.record_error(reason)
      |> ConnectionState.remove_stream(stream_ref)

    # Notify callback if available
    if updated_state.callback_pid do
      MessageHandlers.notify(
        updated_state.callback_pid,
        {:error, stream_ref, reason}
      )
    end

    {:reply, {:error, reason}, updated_state}
  end

  @doc """
  Handles async error response in handle_info callbacks.

  ## Parameters

  * `stream_ref` - Reference to the stream with the error (or nil)
  * `reason` - The error reason
  * `state` - Current connection state

  ## Returns

  `{:noreply, updated_state}` - For asynchronous contexts
  """
  @spec handle_async_error(reference() | nil, term(), ConnectionState.t()) ::
          {:noreply, ConnectionState.t()}
  def handle_async_error(stream_ref, reason, state) do
    Logger.error("Async error: #{inspect(reason)} for stream: #{inspect(stream_ref)}")

    # Update state with error and clean up the stream
    updated_state =
      state
      |> ConnectionState.record_error(reason)
      |> clean_stream_on_error(stream_ref)

    # Notify callback if available
    if updated_state.callback_pid do
      MessageHandlers.notify(
        updated_state.callback_pid,
        {:error, stream_ref, reason}
      )
    end

    {:noreply, updated_state}
  end

  @doc """
  Handles wait_for_websocket_upgrade errors.

  ## Parameters

  * `stream_ref` - Reference to the stream with the error
  * `reason` - The error reason
  * `state` - Current connection state

  ## Returns

  `{:reply, {:error, reason}, state}` - For synchronous contexts
  """
  @spec handle_upgrade_error(reference(), term(), ConnectionState.t()) ::
          {:reply, {:error, term()}, ConnectionState.t()}
  def handle_upgrade_error(stream_ref, reason, state) do
    Logger.error("WebSocket upgrade error: #{inspect(reason)} for stream: #{inspect(stream_ref)}")

    # Update state with error
    updated_state =
      state
      |> ConnectionState.record_error(reason)
      |> ConnectionState.remove_stream(stream_ref)

    # Notify callback if available
    if updated_state.callback_pid do
      MessageHandlers.notify(
        updated_state.callback_pid,
        {:websocket_upgrade_error, stream_ref, reason}
      )
    end

    {:reply, {:error, reason}, updated_state}
  end

  @doc """
  Handles transition errors when state machine transitions fail.

  ## Parameters

  * `current_state` - Current state name
  * `target_state` - Target state name
  * `reason` - The error reason
  * `state` - Current connection state

  ## Returns

  `{:noreply, state}` - For asynchronous contexts
  """
  @spec handle_transition_error(atom(), atom(), term(), ConnectionState.t()) ::
          {:noreply, ConnectionState.t()}
  def handle_transition_error(current_state, target_state, reason, state) do
    Logger.error(
      "Failed to transition from #{current_state} to #{target_state}: #{inspect(reason)}"
    )

    # Record the error
    updated_state =
      ConnectionState.record_error(
        state,
        {:transition_error, current_state, target_state, reason}
      )

    # Notify callback if available
    if updated_state.callback_pid do
      MessageHandlers.notify(
        updated_state.callback_pid,
        {:transition_error, current_state, target_state, reason}
      )
    end

    {:noreply, updated_state}
  end

  # Private helpers

  # Clean up a stream when an error occurs
  defp clean_stream_on_error(state, nil), do: state

  defp clean_stream_on_error(state, stream_ref) do
    Logger.debug("Cleaning up stream after error: #{inspect(stream_ref)}")
    ConnectionState.remove_stream(state, stream_ref)
  end
end
