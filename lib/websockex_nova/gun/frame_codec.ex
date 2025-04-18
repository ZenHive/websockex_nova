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
      :ok -> lookup_handler_from_table(frame_type)
      {:error, _reason} -> default_handler(frame_type)
    end
  end

  defp lookup_handler_from_table(frame_type) do
    case :ets.lookup(@handlers_table, frame_type) do
      [{^frame_type, handler}] -> handler
      [] -> default_handler(frame_type)
    end
  end

  defp default_handler(frame_type), do: Map.get(@frame_handlers, frame_type, ControlFrameHandler)

  # Ensure the table exists with fallback mechanism
  defp ensure_table_exists do
    case :ets.info(@handlers_table) do
      :undefined -> init_handlers_table()
      _ -> :ok
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
    frame
    |> frame_type()
    |> safe_lookup_handler()
    |> encode_with_handler(frame)
  end

  defp encode_with_handler(handler, frame), do: handler.encode_frame(frame)

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
    case frame_type(frame) do
      :invalid -> {:error, :invalid_frame}
      type -> decode_with_handler(type, frame)
    end
  end

  defp decode_with_handler(type, frame) do
    handler = safe_lookup_handler(type)

    try do
      handler.decode_frame(frame)
    rescue
      _ -> {:error, :invalid_frame}
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
    frame
    |> frame_type()
    |> safe_lookup_handler()
    |> validate_with_handler(frame)
  rescue
    _ -> {:error, :invalid_frame}
  end

  defp validate_with_handler(handler, frame), do: handler.validate_frame(frame)

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

      iex> WebsockexNova.Gun.FrameCodec.valid_close_code?(1000)
      true

      iex> WebsockexNova.Gun.FrameCodec.valid_close_code?(999)
      false
  """
  @spec valid_close_code?(non_neg_integer()) :: boolean()
  def valid_close_code?(code) do
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
  def close_code_meaning(1000), do: "Normal closure"
  def close_code_meaning(1001), do: "Going away"
  def close_code_meaning(1002), do: "Protocol error"
  def close_code_meaning(1003), do: "Unsupported data"
  def close_code_meaning(1004), do: "Reserved"
  def close_code_meaning(1005), do: "No status received"
  def close_code_meaning(1006), do: "Abnormal closure"
  def close_code_meaning(1007), do: "Invalid frame payload data"
  def close_code_meaning(1008), do: "Policy violation"
  def close_code_meaning(1009), do: "Message too big"
  def close_code_meaning(1010), do: "Mandatory extension"
  def close_code_meaning(1011), do: "Internal error"
  def close_code_meaning(1012), do: "Service restart"
  def close_code_meaning(1013), do: "Try again later"
  def close_code_meaning(1014), do: "Bad gateway"
  def close_code_meaning(1015), do: "TLS handshake"
  def close_code_meaning(_), do: "Unknown close code"

  @doc """
  Determines the frame type of a WebSocket frame.

  ## Parameters

  * `frame` - The WebSocket frame

  ## Returns

  The frame type as an atom (`:text`, `:binary`, etc.)
  """
  @spec frame_type(frame()) :: atom()
  def frame_type({:text, _}), do: :text
  def frame_type({:binary, _}), do: :binary
  def frame_type(:ping), do: :ping
  def frame_type({:ping, _}), do: :ping
  def frame_type(:pong), do: :pong
  def frame_type({:pong, _}), do: :pong
  def frame_type(:close), do: :close
  def frame_type({:close, _}), do: :close
  def frame_type({:close, _, _}), do: :close
  def frame_type(_), do: :invalid

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
