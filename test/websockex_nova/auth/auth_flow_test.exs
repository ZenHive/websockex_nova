defmodule WebsockexNova.Auth.AuthFlowTest do
  use ExUnit.Case, async: true

  alias WebsockexNova.Auth.AuthFlow
  alias WebsockexNova.Behaviors.AuthHandler

  # Define a mock AuthHandler for testing
  defmodule MockAuthHandler do
    @moduledoc false
    @behaviour AuthHandler

    @impl true
    def generate_auth_data(%{credentials: nil} = state) do
      {:error, :missing_credentials, state}
    end

    def generate_auth_data(%{credentials: credentials} = state) do
      auth_data = %{
        type: "auth",
        timestamp: System.system_time(:second),
        api_key: credentials.api_key,
        signature: "mock_signature_#{credentials.secret}"
      }

      {:ok, auth_data, state}
    end

    @impl true
    def handle_auth_response(%{"type" => "auth_success", "expires_at" => expires_at}, state) do
      updated_state =
        state
        |> Map.put(:auth_status, :authenticated)
        |> Map.put(:auth_expires_at, expires_at)

      {:ok, updated_state}
    end

    def handle_auth_response(%{"type" => "auth_error", "reason" => reason}, state) do
      updated_state =
        state
        |> Map.put(:auth_status, :failed)
        |> Map.put(:auth_error, reason)

      {:error, reason, updated_state}
    end

    def handle_auth_response(_response, state) do
      {:ok, state}
    end

    @impl true
    def needs_reauthentication?(state) do
      cond do
        Map.get(state, :auth_status) == :failed -> true
        not Map.has_key?(state, :auth_expires_at) -> false
        state.auth_expires_at < System.system_time(:second) + 60 -> true
        true -> false
      end
    end
  end

  describe "AuthFlow.authenticate/2" do
    setup do
      handlers =
        Map.put(%{auth_handler: MockAuthHandler}, {:auth_handler, :state}, %{
          credentials: %{api_key: "test_key", secret: "test_secret"},
          auth_status: :unauthenticated
        })

      state = %{handlers: handlers}
      {:ok, state: state}
    end

    test "performs initial authentication successfully", %{state: state} do
      send_frame_called = self()

      send_frame_fn = fn _conn, frame_type, frame_data, _stream_ref ->
        send(send_frame_called, {:send_frame, frame_type, frame_data})
        :ok
      end

      # Simulate auth flow with successful response
      {result, updated_state} =
        AuthFlow.authenticate(state, send_frame_fn)

      # Should return ok and not update state yet (waiting for response)
      assert result == :ok
      assert updated_state == state

      # Verify send_frame was called with auth data
      assert_received {:send_frame, :text, frame_data}
      assert is_binary(frame_data)
      decoded_data = Jason.decode!(frame_data)
      assert decoded_data["type"] == "auth"
      assert decoded_data["api_key"] == "test_key"

      # Simulate auth response from server
      auth_response = %{
        "type" => "auth_success",
        "expires_at" => System.system_time(:second) + 3600
      }

      # Process auth response
      {:ok, state_after_auth} =
        AuthFlow.handle_auth_response(auth_response, updated_state)

      # Verify state was updated with auth information
      auth_handler_state = state_after_auth.handlers[{:auth_handler, :state}]
      assert auth_handler_state.auth_status == :authenticated
      assert auth_handler_state.auth_expires_at == auth_response["expires_at"]
    end

    test "handles authentication failure", %{state: state} do
      send_frame_fn = fn _conn, frame_type, frame_data, _stream_ref ->
        send(self(), {:send_frame, frame_type, frame_data})
        :ok
      end

      # Simulate auth flow
      {:ok, updated_state} =
        AuthFlow.authenticate(state, send_frame_fn)

      # Simulate auth error response from server
      auth_response = %{
        "type" => "auth_error",
        "reason" => "invalid_credentials"
      }

      # Process auth error response
      {:error, reason, state_after_auth} =
        AuthFlow.handle_auth_response(auth_response, updated_state)

      # Verify state was updated with auth error
      assert reason == "invalid_credentials"
      auth_handler_state = state_after_auth.handlers[{:auth_handler, :state}]
      assert auth_handler_state.auth_status == :failed
      assert auth_handler_state.auth_error == "invalid_credentials"
    end

    test "handles missing credentials", %{state: state} do
      # Remove credentials from state
      state = put_in(state.handlers[{:auth_handler, :state}].credentials, nil)

      send_frame_fn = fn _conn, _frame_type, _frame_data, _stream_ref ->
        flunk("send_frame should not be called when credentials are missing")
      end

      # Simulate auth flow with missing credentials
      {:error, :missing_credentials, _updated_state} =
        AuthFlow.authenticate(state, send_frame_fn)
    end
  end

  describe "AuthFlow.check_reauthentication/2" do
    setup do
      handlers =
        Map.put(%{auth_handler: MockAuthHandler}, {:auth_handler, :state}, %{
          credentials: %{api_key: "test_key", secret: "test_secret"},
          auth_status: :authenticated,
          auth_expires_at: System.system_time(:second) + 30
        })

      # Set expiration to 30 seconds from now (needs reauthentication)
      state = %{handlers: handlers}
      {:ok, state: state}
    end

    test "detects when reauthentication is needed", %{state: state} do
      send_frame_called = self()

      send_frame_fn = fn _conn, frame_type, frame_data, _stream_ref ->
        send(send_frame_called, {:send_frame, frame_type, frame_data})
        :ok
      end

      # Check if reauthentication is needed
      {result, updated_state} = AuthFlow.check_reauthentication(state, send_frame_fn)

      # Should return :reauthenticated and keep state the same
      assert result == :reauthenticated
      assert updated_state == state

      # Verify send_frame was called with auth data
      assert_received {:send_frame, :text, frame_data}
      decoded_data = Jason.decode!(frame_data)
      assert decoded_data["type"] == "auth"
    end

    test "does nothing when reauthentication is not needed", %{state: state} do
      # Update expiration to be far in the future
      state =
        put_in(
          state.handlers[{:auth_handler, :state}].auth_expires_at,
          System.system_time(:second) + 3600
        )

      send_frame_fn = fn _conn, _frame_type, _frame_data, _stream_ref ->
        flunk("send_frame should not be called when reauthentication is not needed")
      end

      # Check if reauthentication is needed
      {:ok, ^state} = AuthFlow.check_reauthentication(state, send_frame_fn)
    end

    test "handles failed auth state", %{state: state} do
      # Update auth status to failed
      state = put_in(state.handlers[{:auth_handler, :state}].auth_status, :failed)

      send_frame_called = self()

      send_frame_fn = fn _conn, frame_type, frame_data, _stream_ref ->
        send(send_frame_called, {:send_frame, frame_type, frame_data})
        :ok
      end

      # Attempt reauthentication
      {result, updated_state} = AuthFlow.check_reauthentication(state, send_frame_fn)

      # Should return :reauthenticated and keep state the same
      assert result == :reauthenticated
      assert updated_state == state

      # Verify send_frame was called with auth data
      assert_received {:send_frame, :text, _frame_data}
    end
  end
end
