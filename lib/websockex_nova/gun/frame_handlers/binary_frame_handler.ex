defmodule WebSockexNova.Gun.FrameHandlers.BinaryFrameHandler do
  @moduledoc """
  Handler for WebSocket binary frames.

  Implements encoding, decoding, and validation specific to binary frames.
  """

  @behaviour WebSockexNova.Gun.FrameHandlers.FrameHandler

  @impl true
  def validate_frame({:binary, data}) when is_binary(data) do
    :ok
  end

  def validate_frame({:binary, _data}) do
    {:error, :invalid_binary_data}
  end

  @impl true
  def encode_frame({:binary, data}) when is_binary(data) do
    {:binary, data}
  end

  @impl true
  def decode_frame({:binary, data}) when is_binary(data) do
    {:ok, {:binary, data}}
  end

  def decode_frame(frame) do
    {:error, {:invalid_binary_frame, frame}}
  end
end
