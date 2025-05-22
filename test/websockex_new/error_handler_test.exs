defmodule WebsockexNew.ErrorHandlerTest do
  use ExUnit.Case, async: true

  alias WebsockexNew.ErrorHandler

  describe "categorize_error/1" do
    test "categorizes connection errors correctly" do
      assert {:connection_error, {:error, :econnrefused}} = ErrorHandler.categorize_error({:error, :econnrefused})
      assert {:connection_error, {:error, :nxdomain}} = ErrorHandler.categorize_error({:error, :nxdomain})

      assert {:connection_error, {:error, {:tls_alert, :bad_certificate}}} =
               ErrorHandler.categorize_error({:error, {:tls_alert, :bad_certificate}})

      assert {:connection_error, {:gun_down, :closed}} =
               ErrorHandler.categorize_error({:gun_down, :pid, :ws, :closed, []})

      assert {:connection_error, {:gun_error, :timeout}} =
               ErrorHandler.categorize_error({:gun_error, :pid, :ref, :timeout})
    end

    test "categorizes timeout errors correctly" do
      assert {:timeout_error, {:error, :timeout}} = ErrorHandler.categorize_error({:error, :timeout})
    end

    test "categorizes protocol errors correctly" do
      assert {:protocol_error, {:error, :invalid_frame}} = ErrorHandler.categorize_error({:error, :invalid_frame})
      assert {:protocol_error, {:error, :frame_too_large}} = ErrorHandler.categorize_error({:error, :frame_too_large})

      assert {:protocol_error, {:error, {:bad_frame, :invalid_opcode}}} =
               ErrorHandler.categorize_error({:error, {:bad_frame, :invalid_opcode}})
    end

    test "categorizes authentication errors correctly" do
      assert {:auth_error, {:error, :unauthorized}} = ErrorHandler.categorize_error({:error, :unauthorized})
      assert {:auth_error, {:error, :invalid_credentials}} = ErrorHandler.categorize_error({:error, :invalid_credentials})
      assert {:auth_error, {:error, :token_expired}} = ErrorHandler.categorize_error({:error, :token_expired})
    end

    test "categorizes unknown errors correctly" do
      assert {:unknown_error, {:error, :some_random_error}} = ErrorHandler.categorize_error({:error, :some_random_error})
      assert {:unknown_error, :unexpected_data} = ErrorHandler.categorize_error(:unexpected_data)
    end
  end

  describe "recoverable?/1" do
    test "returns true for recoverable errors" do
      assert ErrorHandler.recoverable?({:error, :econnrefused})
      assert ErrorHandler.recoverable?({:error, :timeout})
      assert ErrorHandler.recoverable?({:gun_down, :pid, :ws, :closed, []})
    end

    test "returns false for non-recoverable errors" do
      refute ErrorHandler.recoverable?({:error, :invalid_frame})
      refute ErrorHandler.recoverable?({:error, :unauthorized})
      refute ErrorHandler.recoverable?({:error, :invalid_credentials})
      refute ErrorHandler.recoverable?({:error, :some_unknown_error})
    end
  end

  describe "handle_error/1" do
    test "returns :reconnect for connection errors" do
      assert :reconnect = ErrorHandler.handle_error({:error, :econnrefused})
      assert :reconnect = ErrorHandler.handle_error({:error, :timeout})
      assert :reconnect = ErrorHandler.handle_error({:gun_down, :pid, :ws, :closed, []})
    end

    test "returns :stop for protocol and auth errors" do
      assert :stop = ErrorHandler.handle_error({:error, :invalid_frame})
      assert :stop = ErrorHandler.handle_error({:error, :unauthorized})
      assert :stop = ErrorHandler.handle_error({:error, :invalid_credentials})
    end

    test "returns :stop for unknown errors" do
      assert :stop = ErrorHandler.handle_error({:error, :some_unknown_error})
      assert :stop = ErrorHandler.handle_error(:unexpected_data)
    end
  end
end
