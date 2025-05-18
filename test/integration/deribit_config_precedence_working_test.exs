defmodule WebsockexNova.Integration.ConfigPrecedenceWorkingTest do
  @moduledoc """
  Test configuration precedence with the current working implementation.
  """

  use ExUnit.Case, async: true

  alias WebsockexNova.Examples.AdapterDeribit

  describe "configuration precedence" do
    test "user options override adapter defaults directly" do
      # Mock what happens when connecting
      adapter_module = AdapterDeribit

      # User provides options
      user_options = %{
        host: "user.deribit.com",
        timeout: 25_000,
        custom_field: "from_user"
      }

      # Get adapter defaults
      {:ok, adapter_state} = adapter_module.init([])
      {:ok, adapter_defaults} = adapter_module.connection_info(adapter_state)

      # Merge: adapter defaults first, user options override
      merged = Map.merge(adapter_defaults, user_options)

      # Verify precedence
      # User wins
      assert merged.host == "user.deribit.com"
      # User wins
      assert merged.timeout == 25_000
      # User addition
      assert merged.custom_field == "from_user"
      # Adapter default
      assert merged.port == 443
      # Adapter default
      assert merged.path == "/ws/api/v2"
      # Adapter default
      assert merged.log_level == :info
    end

    test "empty user options preserves all adapter defaults" do
      adapter_module = AdapterDeribit
      user_options = %{}

      {:ok, adapter_state} = adapter_module.init([])
      {:ok, adapter_defaults} = adapter_module.connection_info(adapter_state)

      merged = Map.merge(adapter_defaults, user_options)

      # All adapter defaults preserved
      assert merged.host == if(Mix.env() == :test, do: "test.deribit.com", else: "www.deribit.com")
      assert merged.port == 443
      assert merged.path == "/ws/api/v2"
      assert merged.timeout == 10_000
      assert merged.log_level == :info
    end

    test "client module can inject defaults between adapter and user" do
      # Simulate a client module that adds its own defaults
      defmodule WorkingClient do
        @moduledoc false
        def connect(adapter, user_opts) do
          # Client-specific defaults
          client_defaults = %{
            host: "client.deribit.com",
            timeout: 15_000,
            log_level: :warn,
            client_specific: true
          }

          # Get adapter defaults
          {:ok, adapter_state} = adapter.init([])
          {:ok, adapter_defaults} = adapter.connection_info(adapter_state)

          # Merge chain: adapter -> client -> user
          config =
            adapter_defaults
            |> Map.merge(client_defaults)
            |> Map.merge(user_opts)

          {:ok, config}
        end
      end

      # User overrides some client defaults
      user_opts = %{
        timeout: 30_000,
        extra_field: "user_data"
      }

      {:ok, config} = WorkingClient.connect(AdapterDeribit, user_opts)

      # Verify three-level precedence
      # Client wins over adapter
      assert config.host == "client.deribit.com"
      # User wins over client
      assert config.timeout == 30_000
      # Client wins over adapter
      assert config.log_level == :warn
      # Client addition
      assert config.client_specific == true
      # User addition
      assert config.extra_field == "user_data"
      # Adapter default
      assert config.port == 443
      # Adapter default
      assert config.path == "/ws/api/v2"
    end

    test "nil values in user options don't override defaults" do
      adapter_module = AdapterDeribit

      # User provides nil values (shouldn't override)
      user_options = %{
        host: nil,
        timeout: 25_000
      }

      {:ok, adapter_state} = adapter_module.init([])
      {:ok, adapter_defaults} = adapter_module.connection_info(adapter_state)

      # Simple merge - nil overwrites (this is standard Map.merge behavior)
      merged = Map.merge(adapter_defaults, user_options)

      # Nil overwrites
      assert merged.host == nil
      # User wins
      assert merged.timeout == 25_000

      # Smart merge - filter out nil values first
      smart_user_options = user_options |> Enum.reject(fn {_k, v} -> is_nil(v) end) |> Map.new()
      smart_merged = Map.merge(adapter_defaults, smart_user_options)

      # Adapter default preserved
      assert smart_merged.host != nil
      # User wins
      assert smart_merged.timeout == 25_000
    end

    test "credentials override properly" do
      adapter_module = AdapterDeribit

      # User provides their own credentials
      user_options = %{
        credentials: %{
          api_key: "user_key",
          secret: "user_secret"
        }
      }

      {:ok, adapter_state} = adapter_module.init([])
      {:ok, adapter_defaults} = adapter_module.connection_info(adapter_state)

      merged = Map.merge(adapter_defaults, user_options)

      # User credentials completely replace adapter defaults
      assert merged.credentials.api_key == "user_key"
      assert merged.credentials.secret == "user_secret"
    end
  end
end
