defmodule WebsockexNova.Gun.FrameHandlers.ControlFrameHandler do
  @moduledoc """
  Handler for WebSocket control frames (ping, pong, close).

  Implements encoding, decoding, and validation specific to control frames.
  """

  @behaviour WebsockexNova.Gun.FrameHandlers.FrameHandler

  # Maximum control frame payload size per WebSocket protocol
  @max_control_payload_size 125

  @impl true
  def validate_frame(:ping), do: :ok
  def validate_frame(:pong), do: :ok
  def validate_frame(:close), do: :ok

  def validate_frame({:ping, data}) when is_binary(data), do: validate_control_frame_size(data)
  def validate_frame({:pong, data}) when is_binary(data), do: validate_control_frame_size(data)

  def validate_frame({:close, code}) when is_integer(code), do: validate_close_code(code)

  def validate_frame({:close, code, reason}) when is_integer(code) and is_binary(reason),
    do: validate_close_code(code)

  def validate_frame(_frame), do: {:error, :invalid_control_frame}

  @impl true
  def encode_frame(:ping), do: :ping
  def encode_frame(:pong), do: :pong
  def encode_frame(:close), do: :close

  def encode_frame({:ping, data}) when is_binary(data), do: {:ping, data}
  def encode_frame({:pong, data}) when is_binary(data), do: {:pong, data}

  def encode_frame({:close, code}) when is_integer(code), do: {:close, code, <<>>}

  def encode_frame({:close, code, reason}) when is_integer(code) and is_binary(reason),
    do: {:close, code, reason}

  @impl true
  def decode_frame(:ping), do: {:ok, :ping}
  def decode_frame(:pong), do: {:ok, :pong}
  def decode_frame(:close), do: {:ok, :close}

  def decode_frame({:ping, data}) when is_binary(data), do: {:ok, {:ping, data}}
  def decode_frame({:pong, data}) when is_binary(data), do: {:ok, {:pong, data}}

  def decode_frame({:close, code}) when is_integer(code), do: {:ok, {:close, code, ""}}

  def decode_frame({:close, code, reason}) when is_integer(code) and is_binary(reason),
    do: {:ok, {:close, code, reason}}

  def decode_frame(frame), do: {:error, {:invalid_control_frame, frame}}

  @doc """
  Validates that a control frame payload isn't too large.

  WebSocket protocol limits control frame payloads to 125 bytes.

  ## Parameters

  * `data` - The binary payload to check

  ## Returns

  * `:ok` - If the payload size is valid
  * `{:error, :control_frame_too_large}` - If the payload is too large
  """
  def validate_control_frame_size(data) when is_binary(data) do
    if byte_size(data) <= @max_control_payload_size do
      :ok
    else
      {:error, :control_frame_too_large}
    end
  end

  @doc """
  Validates a WebSocket close code according to the protocol.

  ## Parameters

  * `code` - The close code to validate

  ## Returns

  * `:ok` - If the close code is valid
  * `{:error, reason}` - If the close code is invalid or reserved
  """
  def validate_close_code(code) do
    cond do
      # Reserved codes that cannot be used
      code in [1005, 1006, 1015] -> {:error, :reserved_close_code}
      # Other reserved codes
      code in [1004] -> {:error, :reserved_close_code}
      # Valid ranges per WebSocket spec
      code in 1000..1003 or code in 1007..1014 or code in 3000..4999 -> :ok
      # Invalid codes
      true -> {:error, :invalid_close_code}
    end
  end
end
