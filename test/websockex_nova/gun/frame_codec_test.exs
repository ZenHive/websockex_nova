defmodule WebSockexNova.Gun.FrameCodecTest do
  use ExUnit.Case, async: true

  alias WebSockexNova.Gun.FrameCodec

  describe "encoding text frames" do
    test "encode_frame/1 encodes text frames" do
      text = "Hello, WebSocket!"
      result = FrameCodec.encode_frame({:text, text})

      # Gun uses {:text, binary} tuples for text frames
      assert result == {:text, "Hello, WebSocket!"}
    end

    test "encode_frame/1 handles empty text frames" do
      result = FrameCodec.encode_frame({:text, ""})
      assert result == {:text, ""}
    end

    test "encode_frame/1 handles unicode text" do
      text = "こんにちは"
      result = FrameCodec.encode_frame({:text, text})
      assert result == {:text, "こんにちは"}
    end
  end

  describe "encoding binary frames" do
    test "encode_frame/1 encodes binary frames" do
      binary = <<1, 2, 3, 4, 5>>
      result = FrameCodec.encode_frame({:binary, binary})

      # Gun uses {:binary, binary} tuples for binary frames
      assert result == {:binary, <<1, 2, 3, 4, 5>>}
    end

    test "encode_frame/1 handles empty binary frames" do
      result = FrameCodec.encode_frame({:binary, <<>>})
      assert result == {:binary, <<>>}
    end
  end

  describe "encoding control frames" do
    test "encode_frame/1 encodes ping frames" do
      result = FrameCodec.encode_frame(:ping)
      assert result == :ping

      # Ping frames can include data
      data = <<1, 2, 3>>
      result_with_data = FrameCodec.encode_frame({:ping, data})
      assert result_with_data == {:ping, <<1, 2, 3>>}
    end

    test "encode_frame/1 encodes pong frames" do
      result = FrameCodec.encode_frame(:pong)
      assert result == :pong

      # Pong frames can include data
      data = <<1, 2, 3>>
      result_with_data = FrameCodec.encode_frame({:pong, data})
      assert result_with_data == {:pong, <<1, 2, 3>>}
    end

    test "encode_frame/1 encodes close frames" do
      # Close without reason
      result = FrameCodec.encode_frame(:close)
      assert result == :close

      # Close with code
      result_with_code = FrameCodec.encode_frame({:close, 1000})
      assert result_with_code == {:close, 1000, <<>>}

      # Close with code and reason
      result_with_reason = FrameCodec.encode_frame({:close, 1000, "Normal closure"})
      assert result_with_reason == {:close, 1000, "Normal closure"}
    end
  end

  describe "decoding frames" do
    test "decode_frame/1 decodes text frames" do
      gun_frame = {:text, "Hello, WebSocket!"}
      result = FrameCodec.decode_frame(gun_frame)

      assert result == {:ok, {:text, "Hello, WebSocket!"}}
    end

    test "decode_frame/1 decodes binary frames" do
      gun_frame = {:binary, <<1, 2, 3, 4, 5>>}
      result = FrameCodec.decode_frame(gun_frame)

      assert result == {:ok, {:binary, <<1, 2, 3, 4, 5>>}}
    end

    test "decode_frame/1 decodes ping frames" do
      gun_frame = :ping
      result = FrameCodec.decode_frame(gun_frame)

      assert result == {:ok, :ping}

      # Ping with data
      gun_frame_with_data = {:ping, <<1, 2, 3>>}
      result_with_data = FrameCodec.decode_frame(gun_frame_with_data)

      assert result_with_data == {:ok, {:ping, <<1, 2, 3>>}}
    end

    test "decode_frame/1 decodes pong frames" do
      gun_frame = :pong
      result = FrameCodec.decode_frame(gun_frame)

      assert result == {:ok, :pong}

      # Pong with data
      gun_frame_with_data = {:pong, <<1, 2, 3>>}
      result_with_data = FrameCodec.decode_frame(gun_frame_with_data)

      assert result_with_data == {:ok, {:pong, <<1, 2, 3>>}}
    end

    test "decode_frame/1 decodes close frames" do
      gun_frame = :close
      result = FrameCodec.decode_frame(gun_frame)

      assert result == {:ok, :close}

      # Close with code
      gun_frame_with_code = {:close, 1000}
      result_with_code = FrameCodec.decode_frame(gun_frame_with_code)

      assert result_with_code == {:ok, {:close, 1000, ""}}

      # Close with code and reason
      gun_frame_with_reason = {:close, 1000, "Normal closure"}
      result_with_reason = FrameCodec.decode_frame(gun_frame_with_reason)

      assert result_with_reason == {:ok, {:close, 1000, "Normal closure"}}
    end

    test "decode_frame/1 handles invalid frames" do
      result = FrameCodec.decode_frame({:unknown, "invalid"})
      assert result == {:error, :invalid_frame}
    end
  end

  describe "frame validation" do
    test "validate_frame/1 validates text frames" do
      assert FrameCodec.validate_frame({:text, "Valid text"}) == :ok
      assert FrameCodec.validate_frame({:text, ""}) == :ok
      assert FrameCodec.validate_frame({:text, nil}) == {:error, :invalid_text_data}
      assert FrameCodec.validate_frame({:text, 123}) == {:error, :invalid_text_data}
    end

    test "validate_frame/1 validates binary frames" do
      assert FrameCodec.validate_frame({:binary, <<1, 2, 3>>}) == :ok
      assert FrameCodec.validate_frame({:binary, <<>>}) == :ok
      assert FrameCodec.validate_frame({:binary, nil}) == {:error, :invalid_binary_data}
      # Strings are binaries in Elixir
      assert FrameCodec.validate_frame({:binary, "string"}) == :ok
    end

    test "validate_frame/1 validates ping/pong frames" do
      assert FrameCodec.validate_frame(:ping) == :ok
      assert FrameCodec.validate_frame(:pong) == :ok
      assert FrameCodec.validate_frame({:ping, <<1, 2, 3>>}) == :ok
      assert FrameCodec.validate_frame({:pong, <<1, 2, 3>>}) == :ok
      assert FrameCodec.validate_frame({:ping, "data"}) == :ok

      # Ping data should be <= 125 bytes as per WebSocket spec
      large_data = String.duplicate("a", 126)
      assert FrameCodec.validate_frame({:ping, large_data}) == {:error, :control_frame_too_large}
    end

    test "validate_frame/1 validates close frames" do
      assert FrameCodec.validate_frame(:close) == :ok
      assert FrameCodec.validate_frame({:close, 1000}) == :ok
      assert FrameCodec.validate_frame({:close, 1000, "Normal closure"}) == :ok

      # Invalid close codes
      assert FrameCodec.validate_frame({:close, 0}) == {:error, :invalid_close_code}
      assert FrameCodec.validate_frame({:close, 999}) == {:error, :invalid_close_code}
      assert FrameCodec.validate_frame({:close, 5000}) == {:error, :invalid_close_code}

      # Reserved close codes
      assert FrameCodec.validate_frame({:close, 1004}) == {:error, :reserved_close_code}
      assert FrameCodec.validate_frame({:close, 1005}) == {:error, :reserved_close_code}
      assert FrameCodec.validate_frame({:close, 1006}) == {:error, :reserved_close_code}
    end
  end

  describe "close codes" do
    test "close_code/1 provides description for standard close codes" do
      assert FrameCodec.close_code_meaning(1000) == "Normal closure"
      assert FrameCodec.close_code_meaning(1001) == "Going away"
      assert FrameCodec.close_code_meaning(1002) == "Protocol error"
      assert FrameCodec.close_code_meaning(1003) == "Unsupported data"
      assert FrameCodec.close_code_meaning(1007) == "Invalid frame payload data"
      assert FrameCodec.close_code_meaning(1008) == "Policy violation"
      assert FrameCodec.close_code_meaning(1009) == "Message too big"
      assert FrameCodec.close_code_meaning(1010) == "Mandatory extension"
      assert FrameCodec.close_code_meaning(1011) == "Internal error"
      assert FrameCodec.close_code_meaning(1012) == "Service restart"
      assert FrameCodec.close_code_meaning(1013) == "Try again later"
      assert FrameCodec.close_code_meaning(1014) == "Bad gateway"
      assert FrameCodec.close_code_meaning(1015) == "TLS handshake"
    end

    test "close_code/1 handles unknown close codes" do
      assert FrameCodec.close_code_meaning(3000) == "Unknown close code"
      assert FrameCodec.close_code_meaning(4000) == "Unknown close code"
    end

    test "is_valid_close_code?/1 checks if close code is valid" do
      # Valid codes
      assert FrameCodec.is_valid_close_code?(1000) == true
      assert FrameCodec.is_valid_close_code?(1001) == true
      assert FrameCodec.is_valid_close_code?(3000) == true
      assert FrameCodec.is_valid_close_code?(4000) == true

      # Invalid codes
      assert FrameCodec.is_valid_close_code?(0) == false
      assert FrameCodec.is_valid_close_code?(999) == false
      assert FrameCodec.is_valid_close_code?(5000) == false

      # Reserved codes
      assert FrameCodec.is_valid_close_code?(1005) == false
      assert FrameCodec.is_valid_close_code?(1006) == false
    end
  end
end
