defmodule WebsockexNova.Defaults.DefaultAuthHandlerTest do
  use ExUnit.Case, async: true

  alias WebsockexNova.Defaults.DefaultAuthHandler

  describe "DefaultAuthHandler.init/1" do
    test "initializes with valid credentials" do
      options = %{
        credentials: %{
          api_key: "test_key",
          secret: "test_secret"
        }
      }

      assert {:ok, state} = DefaultAuthHandler.init(options)
      assert state.auth_status == :unauthenticated
      assert state.auth_refresh_threshold == 60
    end

    test "initializes with valid token credentials" do
      options = %{
        credentials: %{
          token: "valid_token"
        }
      }

      assert {:ok, state} = DefaultAuthHandler.init(options)
      assert state.auth_status == :unauthenticated
    end

    test "fails initialization with invalid credentials" do
      options = %{
        credentials: %{
          # Missing secret
          api_key: "test_key"
        }
      }

      assert {:error, :invalid_credentials} = DefaultAuthHandler.init(options)
    end

    test "fails initialization with empty credentials" do
      options = %{
        credentials: %{
          api_key: "",
          secret: ""
        }
      }

      assert {:error, :invalid_credentials} = DefaultAuthHandler.init(options)
    end

    test "accepts list options" do
      options = [
        credentials: %{
          api_key: "test_key",
          secret: "test_secret"
        }
      ]

      assert {:ok, state} = DefaultAuthHandler.init(options)
      assert state.auth_status == :unauthenticated
    end
  end

  describe "DefaultAuthHandler.generate_auth_data/1" do
    test "generates auth data with API key and secret" do
      state = %{
        credentials: %{
          api_key: "test_key",
          secret: "test_secret"
        },
        auth_status: :unauthenticated
      }

      assert {:ok, auth_data, ^state} = DefaultAuthHandler.generate_auth_data(state)
      assert auth_data.type == "auth"
      assert auth_data.api_key == "test_key"
      assert is_binary(auth_data.signature)
      assert is_integer(auth_data.timestamp)
    end

    test "generates auth data with token" do
      state = %{
        credentials: %{
          token: "test_token"
        },
        auth_status: :unauthenticated
      }

      assert {:ok, auth_data, ^state} = DefaultAuthHandler.generate_auth_data(state)
      assert auth_data.type == "auth"
      assert auth_data.token == "test_token"
      assert is_integer(auth_data.timestamp)
    end

    test "fails with missing credentials" do
      state = %{auth_status: :unauthenticated}
      assert {:error, :missing_credentials, ^state} = DefaultAuthHandler.generate_auth_data(state)
    end

    test "fails with invalid credentials" do
      state = %{
        # Missing secret
        credentials: %{api_key: "test_key"},
        auth_status: :unauthenticated
      }

      assert {:error, :missing_credentials, ^state} = DefaultAuthHandler.generate_auth_data(state)
    end
  end

  describe "DefaultAuthHandler.handle_auth_response/2" do
    setup do
      state = %{
        credentials: %{
          api_key: "test_key",
          secret: "test_secret"
        },
        auth_status: :unauthenticated
      }

      {:ok, state: state}
    end

    test "processes successful authentication with expires_at", %{state: state} do
      expires_at = System.system_time(:second) + 3600
      response = %{"type" => "auth_success", "expires_at" => expires_at}

      assert {:ok, updated_state} = DefaultAuthHandler.handle_auth_response(response, state)
      assert updated_state.auth_status == :authenticated
      assert updated_state.auth_expires_at == expires_at
    end

    test "processes successful authentication with expires_in", %{state: state} do
      response = %{"type" => "auth_success", "expires_in" => 3600}
      current_time = System.system_time(:second)

      assert {:ok, updated_state} = DefaultAuthHandler.handle_auth_response(response, state)
      assert updated_state.auth_status == :authenticated
      assert updated_state.auth_expires_at >= current_time + 3600
      # Allow for slight delay
      assert updated_state.auth_expires_at <= current_time + 3610
    end

    test "processes successful authentication with token", %{state: state} do
      response = %{
        "type" => "auth_success",
        "token" => "new_token",
        "expires_at" => System.system_time(:second) + 3600
      }

      assert {:ok, updated_state} = DefaultAuthHandler.handle_auth_response(response, state)
      assert updated_state.auth_status == :authenticated
      assert updated_state.credentials.token == "new_token"
    end

    test "processes authentication error with reason", %{state: state} do
      response = %{"type" => "auth_error", "reason" => "invalid_signature"}

      assert {:error, "invalid_signature", updated_state} =
               DefaultAuthHandler.handle_auth_response(response, state)

      assert updated_state.auth_status == :failed
      assert updated_state.auth_error == "invalid_signature"
    end

    test "processes authentication error with message", %{state: state} do
      response = %{"type" => "auth_error", "message" => "Authentication failed"}

      assert {:error, "Authentication failed", updated_state} =
               DefaultAuthHandler.handle_auth_response(response, state)

      assert updated_state.auth_status == :failed
      assert updated_state.auth_error == "Authentication failed"
    end

    test "ignores unrelated messages", %{state: state} do
      response = %{"type" => "other_message"}

      assert {:ok, ^state} = DefaultAuthHandler.handle_auth_response(response, state)
    end
  end

  describe "DefaultAuthHandler.needs_reauthentication?/1" do
    test "detects failed authentication status" do
      state = %{
        credentials: %{api_key: "test_key", secret: "test_secret"},
        auth_status: :failed
      }

      assert DefaultAuthHandler.needs_reauthentication?(state) == true
    end

    test "detects expiring authentication" do
      state = %{
        credentials: %{api_key: "test_key", secret: "test_secret"},
        auth_status: :authenticated,
        # 30 seconds from now
        auth_expires_at: System.system_time(:second) + 30
      }

      assert DefaultAuthHandler.needs_reauthentication?(state) == true
    end

    test "respects custom refresh threshold" do
      # Set threshold to 120 seconds
      state = %{
        credentials: %{api_key: "test_key", secret: "test_secret"},
        auth_status: :authenticated,
        # 90 seconds from now
        auth_expires_at: System.system_time(:second) + 90,
        auth_refresh_threshold: 120
      }

      assert DefaultAuthHandler.needs_reauthentication?(state) == true

      # Now with default threshold (60), this shouldn't need refresh
      state = Map.delete(state, :auth_refresh_threshold)
      assert DefaultAuthHandler.needs_reauthentication?(state) == false
    end

    test "returns false for valid authentication" do
      state = %{
        credentials: %{api_key: "test_key", secret: "test_secret"},
        auth_status: :authenticated,
        # 10 minutes from now
        auth_expires_at: System.system_time(:second) + 600
      }

      assert DefaultAuthHandler.needs_reauthentication?(state) == false
    end

    test "returns false when not authenticated yet" do
      state = %{
        credentials: %{api_key: "test_key", secret: "test_secret"},
        auth_status: :unauthenticated
      }

      assert DefaultAuthHandler.needs_reauthentication?(state) == false
    end

    test "returns false when no expiration time is set" do
      state = %{
        credentials: %{api_key: "test_key", secret: "test_secret"},
        # No auth_expires_at
        auth_status: :authenticated
      }

      assert DefaultAuthHandler.needs_reauthentication?(state) == false
    end
  end
end
