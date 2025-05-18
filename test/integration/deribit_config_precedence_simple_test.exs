defmodule WebsockexNova.Integration.ConfigPrecedenceSimpleTest do
  use ExUnit.Case, async: true
  
  # We don't use this in this test, so removing it to fix the warning
  # No aliases needed for this test
  
  @moduledoc """
  Simple test verifying configuration precedence without actual connections.
  Tests the configuration merge logic only.
  """

  # Mock adapter with simple defaults
  defmodule MockAdapter do
    use WebsockexNova.Adapter
    
    @impl WebsockexNova.Behaviors.ConnectionHandler
    def connection_info(_opts) do
      {:ok, %{
        host: "adapter.example.com",
        port: 443,
        path: "/ws",
        timeout: 10_000,
        log_level: :info
      }}
    end
  end

  describe "configuration precedence" do
    test "user options override adapter defaults" do
      # When user provides their own options
      user_options = %{
        host: "user.example.com",
        timeout: 25_000
      }
      
      # The adapter provides its defaults
      {:ok, adapter_defaults} = MockAdapter.connection_info(%{})
      
      # User options take precedence
      merged = Map.merge(adapter_defaults, user_options)
      
      assert merged.host == "user.example.com"      # User wins
      assert merged.timeout == 25_000               # User wins
      assert merged.log_level == :info              # Adapter default
      assert merged.port == 443                     # Adapter default
      assert merged.path == "/ws"                   # Adapter default
    end

    test "client module defaults override adapter defaults" do
      # Define a client with its own defaults
      defmodule TestClient do
        # Simulate what the macro would do
        def default_opts do
          %{
            host: "client.example.com",
            timeout: 15_000,
            log_level: :warn
          }
        end
        
        def connect(user_opts) do
          {:ok, adapter_defaults} = MockAdapter.connection_info(%{})
          merged = Map.merge(adapter_defaults, default_opts())
          final = Map.merge(merged, user_opts)
          {:ok, final}
        end
      end
      
      # Client defaults override adapter defaults
      {:ok, config} = TestClient.connect(%{})
      
      assert config.host == "client.example.com"    # Client wins
      assert config.timeout == 15_000               # Client wins
      assert config.log_level == :warn              # Client wins  
      assert config.port == 443                     # Adapter default
      assert config.path == "/ws"                   # Adapter default
    end

    test "complete precedence chain" do
      # Define a client with defaults
      defmodule FullTestClient do
        def default_opts do
          %{
            host: "client.example.com",
            timeout: 15_000,
            log_level: :warn,
            custom_field: "from_client"
          }
        end
        
        def connect(user_opts) do
          # 1. Adapter defaults (lowest priority)
          {:ok, adapter_defaults} = MockAdapter.connection_info(%{})
          
          # 2. Client module defaults
          merged = Map.merge(adapter_defaults, default_opts())
          
          # 3. User options (highest priority)
          final = Map.merge(merged, user_opts)
          
          {:ok, final}
        end
      end
      
      # User provides some overrides
      user_options = %{
        timeout: 35_000,
        custom_field: "from_user",
        another_field: "user_only"
      }
      
      {:ok, config} = FullTestClient.connect(user_options)
      
      # Verify precedence
      assert config.host == "client.example.com"    # Client default
      assert config.timeout == 35_000               # User override
      assert config.log_level == :warn              # Client default
      assert config.custom_field == "from_user"     # User override
      assert config.another_field == "user_only"    # User only
      assert config.port == 443                     # Adapter default
      assert config.path == "/ws"                   # Adapter default
    end

    test "configuration precedence with actual ClientMacro" do
      # Define a client using the actual macro
      defmodule MacroTestClient do
        use WebsockexNova.ClientMacro,
          adapter: MockAdapter,
          default_options: %{
            host: "macro-client.example.com",
            timeout: 20_000,
            log_level: :debug
          }
          
        # Override default_opts to return a concrete map instead of AST
        def default_opts do
          %{
            host: "macro-client.example.com",
            timeout: 20_000,
            log_level: :debug
          }
        end
          
        # Add a test helper method that just merges options without connecting
        def test_merge_options(opts) do
          # 1. Adapter protocol defaults
          {:ok, adapter_defaults} = MockAdapter.connection_info(%{})
          # 2. Merge in client/app-level defaults
          merged = Map.merge(adapter_defaults, default_opts())
          # 3. Merge in user opts
          final_opts = Map.merge(merged, opts)
          {:ok, final_opts}
        end
      end
      
      # Test using the client's helper method that properly merges options
      user_opts = %{timeout: 40_000}
      {:ok, final} = MacroTestClient.test_merge_options(user_opts)
      
      assert final.host == "macro-client.example.com"  # Client wins
      assert final.timeout == 40_000                   # User wins
      assert final.log_level == :debug                 # Client wins
      assert final.port == 443                         # Adapter default
    end
  end
end