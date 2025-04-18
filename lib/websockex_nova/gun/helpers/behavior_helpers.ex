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
  def call_handle_connect(state, extra_info \\ %{}) do
    handler_module = Map.get(state.handlers, :connection_handler)
    handler_state = Map.get(state.handlers, :connection_handler_state)

    Logger.debug("BehaviorHelpers - call_handle_connect called with handler_module: #{inspect(handler_module)}")

    if handler_module && handler_state do
      # Build connection info for the handler
      conn_info = %{
        host: state.host,
        port: state.port,
        path: Map.get(extra_info, :path, "/"),
        protocol: Map.get(extra_info, :protocol),
        transport: Map.get(state.options, :transport, :tcp)
      }

      Logger.debug("BehaviorHelpers - Calling handle_connect with conn_info: #{inspect(conn_info)}")

      # Call the handler and process response
      case handler_module.handle_connect(conn_info, handler_state) do
        {:ok, new_handler_state} ->
          {:ok, ConnectionState.update_connection_handler_state(state, new_handler_state)}

        {:reply, frame_type, data, new_handler_state} ->
          # Store the handler state and the frame to send
          updated_state =
            ConnectionState.update_connection_handler_state(state, new_handler_state)

          {:reply, frame_type, data, updated_state}

        {:close, code, reason, new_handler_state} ->
          # Store the handler state and return close info
          updated_state =
            ConnectionState.update_connection_handler_state(state, new_handler_state)

          {:close, code, reason, updated_state}

        {:stop, reason, new_handler_state} ->
          # Update state but return stop directive
          updated_state =
            ConnectionState.update_connection_handler_state(state, new_handler_state)

          {:stop, reason, updated_state}

        other ->
          Logger.error("Invalid return from handle_connect: #{inspect(other)}")
          {:error, :invalid_handler_return}
      end
    else
      Logger.debug("BehaviorHelpers - Skipping call_handle_connect, no handler_module or handler_state")

      {:ok, state}
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
  def call_handle_disconnect(state, reason) do
    handler_module = Map.get(state.handlers, :connection_handler)
    handler_state = Map.get(state.handlers, :connection_handler_state)

    Logger.debug("BehaviorHelpers - call_handle_disconnect with reason: #{inspect(reason)}")
    Logger.debug("BehaviorHelpers - handler_module: #{inspect(handler_module)}")

    # Check if test_pid is properly stored
    if handler_state != nil && is_map(handler_state) do
      if Map.has_key?(handler_state, :test_pid) do
        test_pid = Map.get(handler_state, :test_pid)
        Logger.debug("BehaviorHelpers - handler_state has test_pid: #{inspect(test_pid)}")
      else
        Logger.debug("BehaviorHelpers - handler_state has no test_pid")
      end

      Logger.debug("BehaviorHelpers - handler_state keys: #{inspect(Map.keys(handler_state))}")
    else
      Logger.debug("BehaviorHelpers - handler_state is nil or not a map")
    end

    if handler_module && handler_state do
      # Format the reason for the handler
      formatted_reason = format_disconnect_reason(reason)
      Logger.debug("BehaviorHelpers - formatted_reason: #{inspect(formatted_reason)}")

      # Call the handler
      try do
        Logger.debug("BehaviorHelpers - Calling handle_disconnect with reason: #{inspect(formatted_reason)}")

        case handler_module.handle_disconnect(formatted_reason, handler_state) do
          {:ok, new_handler_state} ->
            Logger.debug("BehaviorHelpers - handle_disconnect returned {:ok, state}")

            updated_state =
              ConnectionState.update_connection_handler_state(state, new_handler_state)

            {:ok, updated_state}

          {:reconnect, new_handler_state} ->
            Logger.debug("BehaviorHelpers - handle_disconnect returned {:reconnect, state}")

            updated_state =
              ConnectionState.update_connection_handler_state(state, new_handler_state)

            {:reconnect, updated_state}

          {:stop, stop_reason, new_handler_state} ->
            Logger.debug("BehaviorHelpers - handle_disconnect returned {:stop, reason, state}")

            updated_state =
              ConnectionState.update_connection_handler_state(state, new_handler_state)

            {:stop, stop_reason, updated_state}

          other ->
            Logger.error("Invalid return from handle_disconnect: #{inspect(other)}")
            {:ok, state}
        end
      rescue
        e ->
          Logger.error("Error in call_handle_disconnect: #{inspect(e)}")
          {:ok, state}
      end
    else
      Logger.debug("BehaviorHelpers - Skipping call_handle_disconnect, no handler_module or handler_state")

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
  def call_handle_frame(state, frame_type, frame_data, stream_ref) do
    handler_module = Map.get(state.handlers, :connection_handler)
    handler_state = Map.get(state.handlers, :connection_handler_state)

    Logger.debug("BehaviorHelpers - call_handle_frame for frame_type: #{inspect(frame_type)}")

    # Check if test_pid is properly stored
    if handler_state != nil && is_map(handler_state) do
      if Map.has_key?(handler_state, :test_pid) do
        test_pid = Map.get(handler_state, :test_pid)
        Logger.debug("BehaviorHelpers - handler_state has test_pid: #{inspect(test_pid)}")
      else
        Logger.debug("BehaviorHelpers - handler_state has no test_pid")
      end
    end

    if handler_module && handler_state do
      # Call the handler
      try do
        Logger.debug(
          "BehaviorHelpers - Calling handle_frame with type: #{inspect(frame_type)}, data: #{inspect(frame_data)}"
        )

        case handler_module.handle_frame(frame_type, frame_data, handler_state) do
          {:ok, new_handler_state} ->
            Logger.debug("BehaviorHelpers - handle_frame returned {:ok, state}")

            updated_state =
              ConnectionState.update_connection_handler_state(state, new_handler_state)

            {:ok, updated_state}

          {:reply, reply_type, reply_data, new_handler_state} ->
            Logger.debug("BehaviorHelpers - handle_frame returned {:reply, ...}")

            updated_state =
              ConnectionState.update_connection_handler_state(state, new_handler_state)

            {:reply, reply_type, reply_data, updated_state, stream_ref}

          {:close, code, reason, new_handler_state} ->
            Logger.debug("BehaviorHelpers - handle_frame returned {:close, ...}")

            updated_state =
              ConnectionState.update_connection_handler_state(state, new_handler_state)

            {:close, code, reason, updated_state, stream_ref}

          other ->
            Logger.error("Invalid return from handle_frame: #{inspect(other)}")
            {:ok, state}
        end
      rescue
        e ->
          Logger.error("Error in call_handle_frame: #{inspect(e)}, #{Exception.format_stacktrace()}")

          {:ok, state}
      end
    else
      Logger.debug("BehaviorHelpers - Skipping call_handle_frame, no handler_module or handler_state")

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
  def call_handle_timeout(state) do
    handler_module = Map.get(state.handlers, :connection_handler)
    handler_state = Map.get(state.handlers, :connection_handler_state)

    if handler_module && is_map(handler_state) do
      # Check if the handler implements handle_timeout
      if function_exported?(handler_module, :handle_timeout, 1) do
        case handler_module.handle_timeout(handler_state) do
          {:ok, new_handler_state} ->
            updated_state =
              ConnectionState.update_connection_handler_state(state, new_handler_state)

            {:ok, updated_state}

          {:reconnect, new_handler_state} ->
            updated_state =
              ConnectionState.update_connection_handler_state(state, new_handler_state)

            {:reconnect, updated_state}

          {:stop, stop_reason, new_handler_state} ->
            updated_state =
              ConnectionState.update_connection_handler_state(state, new_handler_state)

            {:stop, stop_reason, updated_state}

          other ->
            Logger.error("Invalid return from handle_timeout: #{inspect(other)}")
            {:ok, state}
        end
      else
        # If handle_timeout is not implemented, default to reconnect
        {:reconnect, state}
      end
    else
      {:reconnect, state}
    end
  end

  # Private helper functions

  # Format disconnect reason for the handler
  defp format_disconnect_reason(reason) do
    cond do
      is_tuple(reason) && elem(reason, 0) == :remote ->
        case reason do
          {:remote, code, message} when is_integer(code) and is_binary(message) ->
            {:remote, code, message}

          _ ->
            {:remote, 1006, "Connection closed abnormally"}
        end

      is_tuple(reason) && elem(reason, 0) == :local ->
        case reason do
          {:local, code, message} when is_integer(code) and is_binary(message) ->
            {:local, code, message}

          _ ->
            {:local, 1000, "Normal closure"}
        end

      true ->
        {:error, reason}
    end
  end
end
