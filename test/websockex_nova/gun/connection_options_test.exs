defmodule WebsockexNova.Gun.ConnectionOptionsTest do
  use ExUnit.Case, async: true

  alias WebsockexNova.Gun.ConnectionOptions

  describe "parse_and_validate/1" do
    test "returns merged options when all are valid" do
      opts = %{transport: :tls, protocols: [:http2], retry: 3, base_backoff: 2000}
      assert {:ok, result} = ConnectionOptions.parse_and_validate(opts)
      assert result.transport == :tls
      assert result.protocols == [:http2]
      assert result.retry == 3
      assert result.base_backoff == 2000
    end

    test "fills in defaults for missing options" do
      assert {:ok, result} = ConnectionOptions.parse_and_validate(%{})
      assert result.transport == :tls
      assert result.protocols == [:http]
      assert result.retry == 5
      assert result.base_backoff == 1000
    end

    test "validates transport option" do
      assert {:error, msg} = ConnectionOptions.parse_and_validate(%{transport: :udp})
      assert msg =~ "Invalid or missing :transport option"
    end

    test "validates protocols as a list" do
      assert {:error, msg} = ConnectionOptions.parse_and_validate(%{protocols: :http})
      assert msg =~ ":protocols must be a list"
    end

    test "validates retry as non-negative integer or :infinity" do
      assert {:error, msg} = ConnectionOptions.parse_and_validate(%{retry: -1})
      assert msg =~ ":retry must be a non-negative integer or :infinity"
      assert {:ok, _} = ConnectionOptions.parse_and_validate(%{retry: :infinity})
    end

    test "validates base_backoff as positive integer" do
      assert {:error, msg} = ConnectionOptions.parse_and_validate(%{base_backoff: 0})
      assert msg =~ ":base_backoff must be a positive integer"
      assert {:error, msg} = ConnectionOptions.parse_and_validate(%{base_backoff: -100})
      assert msg =~ ":base_backoff must be a positive integer"
    end
  end
end
