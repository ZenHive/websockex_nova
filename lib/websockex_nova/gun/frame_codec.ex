defmodule WebsockexNova.Gun.FrameCodec do
  @moduledoc """
  Handles encoding and decoding of WebSocket frames.

  This module provides functionality for working with WebSocket frames in Gun.
  It handles various frame types (text, binary, ping, pong, close) and provides
  utilities for validating frames and working with close codes.

  The module uses a pluggable handler system that allows for custom frame handlers
  to be registered, supporting extensions like permessage-deflate and other WebSocket
  extensions.

  Gun WebSocket frames are represented as:
  - `{:text, binary()}` - Text frames
  - `{:binary, binary()}` - Binary frames
  - `:ping` or `{:ping, binary()}` - Ping frames
  - `:pong` or `{:pong, binary()}` - Pong frames
  - `:close` or `{:close, code()}` or `{:close, code(), binary()}` - Close frames
  """

  alias WebsockexNova.Gun.FrameHandlers.ControlFrameHandler

  @type frame ::
          {:text, binary()}
          | {:binary, binary()}
          | :ping
          | {:ping, binary()}
          | :pong
          | {:pong, binary()}
          | :close
          | {:close, non_neg_integer()}
          | {:close, non_neg_integer(), binary()}

  @type decode_result :: {:ok, frame()} | {:error, atom()}
  @type validate_result :: :ok | {:error, atom()}

  # Registry of frame handlers - can be extended at runtime
  @frame_handlers %{
    text: WebsockexNova.Gun.FrameHandlers.TextFrameHandler,
    binary: WebsockexNova.Gun.FrameHandlers.BinaryFrameHandler,
    ping: ControlFrameHandler,
    pong: ControlFrameHandler,
    close: ControlFrameHandler
  }

  # Table name for handler registry
  @handlers_table :websockex_nova_frame_handlers

  # Initialize the ETS table on module load - This is now called once at application startup
  @doc """
  Initializes the ETS table for frame handlers.

  This function creates the ETS table for storing frame handlers if it doesn't exist yet.
  It is called once at application startup to ensure the table exists before it's accessed.

  ## Returns

  * `:ok` - When the table is successfully initialized
  * `{:error, :table_exists}` - When the table already exists
  """
  @spec init_handlers_table() :: :ok | {:error, :table_exists}
  def init_handlers_table do
    case :ets.info(@handlers_table) do
      :undefined ->
        # Table doesn't exist, create it and populate with default handlers
        :ets.new(@handlers_table, [:named_table, :set, :public])

        # Initialize with default handlers
        Enum.each(@frame_handlers, fn {frame_type, handler} ->
          :ets.insert(@handlers_table, {frame_type, handler})
        end)

        :ok

      _ ->
        # Table already exists, nothing to do
        {:error, :table_exists}
    end
  end

  # Private helper to safely get frame handler with fallback
  defp safe_lookup_handler(frame_type) do
    case ensure_table_exists() do
      :ok ->
        case :ets.lookup(@handlers_table, frame_type) do
          [{^frame_type, handler}] ->
            handler

          [] ->
            # Use fallback from module attribute if no entry in ETS
            Map.get(
              @frame_handlers,
              frame_type,
              ControlFrameHandler
            )
        end

      {:error, _reason} ->
        # Fallback to module attribute if table doesn't exist
        Map.get(@frame_handlers, frame_type, ControlFrameHandler)
    end
  end

  # Ensure the table exists with fallback mechanism
  defp ensure_table_exists do
    case :ets.info(@handlers_table) do
      :undefined ->
        # Table doesn't exist, but should have been created at startup
        # This is a fallback mechanism for cases where init_handlers_table wasn't called
        init_handlers_table()

      _ ->
        :ok
    end
  end

  @doc """
  Encodes a WebSocket frame for sending via Gun.

  Takes a frame in the internal format and converts it to the format expected by Gun.
  Uses the appropriate frame handler based on the frame type.

  ## Examples

      iex> WebsockexNova.Gun.FrameCodec.encode_frame({:text, "Hello"})
      {:text, "Hello"}

      iex> WebsockexNova.Gun.FrameCodec.encode_frame(:ping)
      :ping

      iex> WebsockexNova.Gun.FrameCodec.encode_frame({:close, 1000, "Normal closure"})
      {:close, 1000, "Normal closure"}
  """
  @spec encode_frame(frame()) :: tuple() | atom()
  def encode_frame(frame) do
    frame_type = frame_type(frame)
    handler = safe_lookup_handler(frame_type)
    handler.encode_frame(frame)
  end

  @doc """
  Decodes a WebSocket frame received from Gun.

  Takes a frame in the Gun format and converts it to the internal format.
  Uses the appropriate frame handler based on the frame type.

  ## Examples

      iex> WebsockexNova.Gun.FrameCodec.decode_frame({:text, "Hello"})
      {:ok, {:text, "Hello"}}

      iex> WebsockexNova.Gun.FrameCodec.decode_frame(:ping)
      {:ok, :ping}

      iex> WebsockexNova.Gun.FrameCodec.decode_frame({:close, 1000, "Normal closure"})
      {:ok, {:close, 1000, "Normal closure"}}
  """
  @spec decode_frame(tuple() | atom()) :: decode_result()
  def decode_frame(frame) do
    frame_type = frame_type(frame)

    if frame_type == :invalid do
      {:error, :invalid_frame}
    else
      handler = safe_lookup_handler(frame_type)

      try do
        handler.decode_frame(frame)
      rescue
        _ -> {:error, :invalid_frame}
      end
    end
  end

  @doc """
  Validates a WebSocket frame.

  Checks if a frame is valid according to the WebSocket spec.
  Uses the appropriate frame handler based on the frame type.

  ## Examples

      iex> WebsockexNova.Gun.FrameCodec.validate_frame({:text, "Hello"})
      :ok

      iex> WebsockexNova.Gun.FrameCodec.validate_frame({:text, nil})
      {:error, :invalid_text_data}

      iex> WebsockexNova.Gun.FrameCodec.validate_frame({:close, 1000})
      :ok
  """
  @spec validate_frame(frame()) :: validate_result()
  def validate_frame(frame) do
    frame_type = frame_type(frame)
    handler = safe_lookup_handler(frame_type)
    handler.validate_frame(frame)
  rescue
    _ -> {:error, :invalid_frame}
  end

  @doc """
  Validates the size of a control frame payload.

  WebSocket protocol limits control frame payloads to 125 bytes.

  ## Parameters

  * `data` - Binary payload data to validate

  ## Returns

  * `:ok` - If the payload size is valid
  * `{:error, :control_frame_too_large}` - If payload exceeds 125 bytes
  """
  @spec validate_control_frame_size(binary()) :: validate_result()
  def validate_control_frame_size(data) when is_binary(data) do
    ControlFrameHandler.validate_control_frame_size(data)
  end

  @doc """
  Validates a WebSocket close code.

  ## Examples

      iex> WebsockexNova.Gun.FrameCodec.validate_close_code(1000)
      :ok

      iex> WebsockexNova.Gun.FrameCodec.validate_close_code(999)
      {:error, :invalid_close_code}

      iex> WebsockexNova.Gun.FrameCodec.validate_close_code(1005)
      {:error, :reserved_close_code}
  """
  @spec validate_close_code(non_neg_integer()) :: validate_result()
  def validate_close_code(code) do
    ControlFrameHandler.validate_close_code(code)
  end

  @doc """
  Checks if a WebSocket close code is valid.

  ## Examples

      iex> WebsockexNova.Gun.FrameCodec.is_valid_close_code?(1000)
      true

      iex> WebsockexNova.Gun.FrameCodec.is_valid_close_code?(999)
      false
  """
  @spec is_valid_close_code?(non_neg_integer()) :: boolean()
  def is_valid_close_code?(code) do
    case validate_close_code(code) do
      :ok -> true
      _ -> false
    end
  end

  @doc """
  Returns the meaning of a WebSocket close code.

  ## Examples

      iex> WebsockexNova.Gun.FrameCodec.close_code_meaning(1000)
      "Normal closure"

      iex> WebsockexNova.Gun.FrameCodec.close_code_meaning(3000)
      "Unknown close code"
  """
  @spec close_code_meaning(non_neg_integer()) :: String.t()
  def close_code_meaning(code) do
    case code do
      1000 -> "Normal closure"
      1001 -> "Going away"
      1002 -> "Protocol error"
      1003 -> "Unsupported data"
      1004 -> "Reserved"
      1005 -> "No status received"
      1006 -> "Abnormal closure"
      1007 -> "Invalid frame payload data"
      1008 -> "Policy violation"
      1009 -> "Message too big"
      1010 -> "Mandatory extension"
      1011 -> "Internal error"
      1012 -> "Service restart"
      1013 -> "Try again later"
      1014 -> "Bad gateway"
      1015 -> "TLS handshake"
      _ -> "Unknown close code"
    end
  end

  @doc """
  Determines the frame type of a WebSocket frame.

  ## Parameters

  * `frame` - The WebSocket frame

  ## Returns

  The frame type as an atom (`:text`, `:binary`, etc.)
  """
  @spec frame_type(frame()) :: atom()
  def frame_type(frame) do
    case frame do
      {:text, _} -> :text
      {:binary, _} -> :binary
      :ping -> :ping
      {:ping, _} -> :ping
      :pong -> :pong
      {:pong, _} -> :pong
      :close -> :close
      {:close, _} -> :close
      {:close, _, _} -> :close
      # If we can't determine the type, treat as invalid
      _ -> :invalid
    end
  end

  @doc """
  Gets the handler module for a specific frame type.

  Uses the built-in handler registry, which can be extended at runtime
  with `register_frame_handler/2`.

  ## Parameters

  * `frame_type` - The type of frame to get a handler for

  ## Returns

  The handler module for the specified frame type
  """
  @spec frame_handler_for(atom()) :: module()
  def frame_handler_for(frame_type) do
    safe_lookup_handler(frame_type)
  end

  @doc """
  Registers a custom frame handler for a specific frame type.

  This allows for extending the WebSocket frame handling with custom
  implementations, such as for handling extensions.

  ## Parameters

  * `frame_type` - The type of frame to register a handler for
  * `handler_module` - The module that implements the handler behavior

  ## Returns

  * `:ok` - If the handler was registered successfully
  * `{:error, :table_missing}` - If the handler registry table doesn't exist
  """
  @spec register_frame_handler(atom(), module() | nil) :: :ok | {:error, :table_missing}
  def register_frame_handler(frame_type, nil) do
    case ensure_table_exists() do
      :ok ->
        :ets.delete(@handlers_table, frame_type)
        :ok

      error ->
        error
    end
  end

  def register_frame_handler(frame_type, handler_module) do
    case ensure_table_exists() do
      :ok ->
        :ets.insert(@handlers_table, {frame_type, handler_module})
        :ok

      error ->
        error
    end
  end
end
