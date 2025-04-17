defmodule WebSockexNova.Gun.FrameCodec do
  @moduledoc """
  Handles encoding and decoding of WebSocket frames.

  This module provides functionality for working with WebSocket frames in Gun.
  It handles various frame types (text, binary, ping, pong, close) and provides
  utilities for validating frames and working with close codes.

  Gun WebSocket frames are represented as:
  - `{:text, binary()}` - Text frames
  - `{:binary, binary()}` - Binary frames
  - `:ping` or `{:ping, binary()}` - Ping frames
  - `:pong` or `{:pong, binary()}` - Pong frames
  - `:close` or `{:close, code()}` or `{:close, code(), binary()}` - Close frames
  """

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

  @doc """
  Encodes a WebSocket frame for sending via Gun.

  Takes a frame in the internal format and converts it to the format expected by Gun.

  ## Examples

      iex> WebSockexNova.Gun.FrameCodec.encode_frame({:text, "Hello"})
      {:text, "Hello"}

      iex> WebSockexNova.Gun.FrameCodec.encode_frame(:ping)
      :ping

      iex> WebSockexNova.Gun.FrameCodec.encode_frame({:close, 1000, "Normal closure"})
      {:close, 1000, "Normal closure"}
  """
  @spec encode_frame(frame()) :: tuple() | atom()
  def encode_frame(frame)

  # Text frames
  def encode_frame({:text, data}) when is_binary(data) do
    {:text, data}
  end

  # Binary frames
  def encode_frame({:binary, data}) when is_binary(data) do
    {:binary, data}
  end

  # Ping frames
  def encode_frame(:ping) do
    :ping
  end

  def encode_frame({:ping, data}) when is_binary(data) do
    {:ping, data}
  end

  # Pong frames
  def encode_frame(:pong) do
    :pong
  end

  def encode_frame({:pong, data}) when is_binary(data) do
    {:pong, data}
  end

  # Close frames
  def encode_frame(:close) do
    :close
  end

  def encode_frame({:close, code}) when is_integer(code) do
    {:close, code, <<>>}
  end

  def encode_frame({:close, code, reason}) when is_integer(code) and is_binary(reason) do
    {:close, code, reason}
  end

  @doc """
  Decodes a WebSocket frame received from Gun.

  Takes a frame in the Gun format and converts it to the internal format.

  ## Examples

      iex> WebSockexNova.Gun.FrameCodec.decode_frame({:text, "Hello"})
      {:ok, {:text, "Hello"}}

      iex> WebSockexNova.Gun.FrameCodec.decode_frame(:ping)
      {:ok, :ping}

      iex> WebSockexNova.Gun.FrameCodec.decode_frame({:close, 1000, "Normal closure"})
      {:ok, {:close, 1000, "Normal closure"}}
  """
  @spec decode_frame(tuple() | atom()) :: decode_result()
  def decode_frame(frame)

  # Text frames
  def decode_frame({:text, data}) when is_binary(data) do
    {:ok, {:text, data}}
  end

  # Binary frames
  def decode_frame({:binary, data}) when is_binary(data) do
    {:ok, {:binary, data}}
  end

  # Ping frames
  def decode_frame(:ping) do
    {:ok, :ping}
  end

  def decode_frame({:ping, data}) when is_binary(data) do
    {:ok, {:ping, data}}
  end

  # Pong frames
  def decode_frame(:pong) do
    {:ok, :pong}
  end

  def decode_frame({:pong, data}) when is_binary(data) do
    {:ok, {:pong, data}}
  end

  # Close frames
  def decode_frame(:close) do
    {:ok, :close}
  end

  def decode_frame({:close, code}) when is_integer(code) do
    {:ok, {:close, code, ""}}
  end

  def decode_frame({:close, code, reason}) when is_integer(code) and is_binary(reason) do
    {:ok, {:close, code, reason}}
  end

  # Unknown/invalid frames
  def decode_frame(_frame) do
    {:error, :invalid_frame}
  end

  @doc """
  Validates a WebSocket frame.

  Checks if a frame is valid according to the WebSocket spec.

  ## Examples

      iex> WebSockexNova.Gun.FrameCodec.validate_frame({:text, "Hello"})
      :ok

      iex> WebSockexNova.Gun.FrameCodec.validate_frame({:text, nil})
      {:error, :invalid_text_data}

      iex> WebSockexNova.Gun.FrameCodec.validate_frame({:close, 1000})
      :ok
  """
  @spec validate_frame(frame()) :: validate_result()
  def validate_frame(frame)

  # Text frames
  def validate_frame({:text, data}) when is_binary(data) do
    :ok
  end

  def validate_frame({:text, _data}) do
    {:error, :invalid_text_data}
  end

  # Binary frames
  def validate_frame({:binary, data}) when is_binary(data) do
    :ok
  end

  def validate_frame({:binary, _data}) do
    {:error, :invalid_binary_data}
  end

  # Ping frames
  def validate_frame(:ping) do
    :ok
  end

  def validate_frame({:ping, data}) when is_binary(data) do
    if byte_size(data) <= 125 do
      :ok
    else
      {:error, :control_frame_too_large}
    end
  end

  # Pong frames
  def validate_frame(:pong) do
    :ok
  end

  def validate_frame({:pong, data}) when is_binary(data) do
    if byte_size(data) <= 125 do
      :ok
    else
      {:error, :control_frame_too_large}
    end
  end

  # Close frames
  def validate_frame(:close) do
    :ok
  end

  def validate_frame({:close, code}) when is_integer(code) do
    validate_close_code(code)
  end

  def validate_frame({:close, code, reason}) when is_integer(code) and is_binary(reason) do
    validate_close_code(code)
  end

  # Unknown frame types
  def validate_frame(_frame) do
    {:error, :invalid_frame}
  end

  @doc """
  Validates a WebSocket close code.

  ## Examples

      iex> WebSockexNova.Gun.FrameCodec.validate_close_code(1000)
      :ok

      iex> WebSockexNova.Gun.FrameCodec.validate_close_code(999)
      {:error, :invalid_close_code}

      iex> WebSockexNova.Gun.FrameCodec.validate_close_code(1005)
      {:error, :reserved_close_code}
  """
  @spec validate_close_code(non_neg_integer()) :: validate_result()
  def validate_close_code(code) do
    cond do
      # Reserved codes that cannot be used
      code in [1005, 1006, 1015] ->
        {:error, :reserved_close_code}

      # Other reserved codes
      code in [1004] ->
        {:error, :reserved_close_code}

      # Valid ranges per WebSocket spec
      code in 1000..1003 or code in 1007..1014 or code in 3000..4999 ->
        :ok

      # Invalid codes
      true ->
        {:error, :invalid_close_code}
    end
  end

  @doc """
  Checks if a WebSocket close code is valid.

  ## Examples

      iex> WebSockexNova.Gun.FrameCodec.is_valid_close_code?(1000)
      true

      iex> WebSockexNova.Gun.FrameCodec.is_valid_close_code?(999)
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

      iex> WebSockexNova.Gun.FrameCodec.close_code_meaning(1000)
      "Normal closure"

      iex> WebSockexNova.Gun.FrameCodec.close_code_meaning(3000)
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
end
