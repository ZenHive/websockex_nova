defmodule WebsockexNova.Gun.FrameHandlers.FrameHandler do
  @moduledoc """
  Behavior defining how to handle different types of WebSocket frames.

  This behavior allows for pluggable frame handling, making it easy to
  extend with custom frame types or specialized processing.
  """

  @doc """
  Validates a frame of a specific type.

  ## Parameters

  * `frame` - The frame to validate

  ## Returns

  * `:ok` - If the frame is valid
  * `{:error, reason}` - If the frame is invalid
  """
  @callback validate_frame(frame :: term()) :: :ok | {:error, atom()}

  @doc """
  Encodes a frame for sending via Gun.

  ## Parameters

  * `frame` - The frame to encode

  ## Returns

  The encoded frame ready for sending through Gun.
  """
  @callback encode_frame(frame :: term()) :: term()

  @doc """
  Decodes a frame received from Gun.

  ## Parameters

  * `frame` - The frame received from Gun

  ## Returns

  * `{:ok, decoded_frame}` - Successfully decoded frame
  * `{:error, reason}` - Error decoding the frame
  """
  @callback decode_frame(frame :: term()) :: {:ok, term()} | {:error, atom()}
end
