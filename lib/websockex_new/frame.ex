defmodule WebsockexNew.Frame do
  @moduledoc """
  WebSocket frame encoding and decoding utilities.
  """

  @type frame_type :: :text | :binary | :ping | :pong | :close
  @type frame :: {frame_type(), binary()}

  @doc """
  Encode text message as WebSocket frame.
  """
  @spec text(String.t()) :: frame()
  def text(message) when is_binary(message) do
    {:text, message}
  end

  @doc """
  Encode binary message as WebSocket frame.
  """
  @spec binary(binary()) :: frame()
  def binary(data) when is_binary(data) do
    {:binary, data}
  end

  @doc """
  Create ping frame.
  """
  @spec ping() :: frame()
  def ping do
    {:ping, <<>>}
  end

  @doc """
  Create pong frame with payload.
  """
  @spec pong(binary()) :: frame()
  def pong(payload \\ <<>>) when is_binary(payload) do
    {:pong, payload}
  end

  @doc """
  Decode incoming WebSocket frame.
  """
  @spec decode(tuple()) :: {:ok, frame()} | {:error, String.t()}
  def decode({:ws, :text, data}), do: {:ok, {:text, data}}
  def decode({:ws, :binary, data}), do: {:ok, {:binary, data}}
  def decode({:ws, :ping, data}), do: {:ok, {:ping, data}}
  def decode({:ws, :pong, data}), do: {:ok, {:pong, data}}
  def decode({:ws, :close, _}), do: {:ok, {:close, <<>>}}
  def decode(frame), do: {:error, "Unknown frame type: #{inspect(frame)}"}
end