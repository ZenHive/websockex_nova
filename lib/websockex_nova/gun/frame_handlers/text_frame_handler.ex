defmodule WebSockexNova.Gun.FrameHandlers.TextFrameHandler do
  @moduledoc """
  Handler for WebSocket text frames.

  Implements encoding, decoding, and validation specific to text frames.
  """

  @behaviour WebSockexNova.Gun.FrameHandlers.FrameHandler

  @impl true
  def validate_frame({:text, data}) when is_binary(data) do
    :ok
  end

  def validate_frame({:text, _data}) do
    {:error, :invalid_text_data}
  end

  @impl true
  def encode_frame({:text, data}) when is_binary(data) do
    {:text, data}
  end

  @impl true
  def decode_frame({:text, data}) when is_binary(data) do
    {:ok, {:text, data}}
  end

  def decode_frame(frame) do
    {:error, {:invalid_text_frame, frame}}
  end
end
