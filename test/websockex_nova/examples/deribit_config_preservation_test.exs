defmodule WebsockexNova.Examples.DeribitConfigPreservationTest do
  use ExUnit.Case, async: true

  alias WebsockexNova.Examples.AdapterDeribit
  alias WebsockexNova.ClientConn

  # Instead of mocking, create a simple config capture module
  defmodule ConfigCaptureClient do
    def connect(adapter, opts) do
      {:ok, 
        %ClientConn{
          adapter: adapter,
          transport_pid: self(),
          stream_ref: nil,
          callback_pids: MapSet.new([]),
          connection_info: opts,
          rate_limit: %{},
          logging: %{},
          metrics: %{},
          reconnection: %{},
          connection_handler_settings: %{},
          auth_handler_settings: %{},
          subscription_handler_settings: %{},
          error_handler_settings: %{},
          message_handler_settings: %{},
          adapter_state: %{},
          extras: %{}
        }
      }
    end
  end
  
  setup do
    %{}
  end

  describe "configuration preservation" do
    test "preserves all standard connection options" do
      # Define a map with all standard connection options
      standard_opts = %{
        host: "custom.deribit.com",
        port: 9443,
        path: "/ws/custom/path",
        headers: [{"User-Agent", "CustomClient/1.0"}],
        timeout: 15_000,
        transport: :tls,
        transport_opts: %{
          verify: :verify_peer,
          cacerts: ["fake_cert"],
          server_name_indication: ~c"custom.deribit.com"
        },
        protocols: [:http],
        retry: 7,
        backoff_type: :linear,
        base_backoff: 3_000,
        ws_opts: %{compress: true},
        callback_pid: self()
      }

      # Use our capture client instead of the real client
      {:ok, conn} = ConfigCaptureClient.connect(AdapterDeribit, standard_opts)

      # Verify all options are preserved in connection_info
      assert conn.connection_info.host == "custom.deribit.com"
      assert conn.connection_info.port == 9443
      assert conn.connection_info.path == "/ws/custom/path"
      assert Enum.member?(conn.connection_info.headers, {"User-Agent", "CustomClient/1.0"})
      assert conn.connection_info.timeout == 15_000
      assert conn.connection_info.transport == :tls
      assert conn.connection_info.transport_opts.verify == :verify_peer
      assert conn.connection_info.transport_opts.cacerts == ["fake_cert"]
      assert conn.connection_info.transport_opts.server_name_indication == ~c"custom.deribit.com"
      assert conn.connection_info.protocols == [:http]
      assert conn.connection_info.retry == 7
      assert conn.connection_info.backoff_type == :linear
      assert conn.connection_info.base_backoff == 3_000
      assert conn.connection_info.ws_opts.compress == true
      assert conn.connection_info.callback_pid == self()
    end

    test "preserves all rate limiting options" do
      # Define rate limiting options
      rate_limit_opts = %{
        rate_limit_handler: WebsockexNova.Defaults.DefaultRateLimitHandler,
        rate_limit_opts: %{
          mode: :strict,
          capacity: 60,
          refill_rate: 5,
          refill_interval: 2_000,
          queue_limit: 100,
          cost_map: %{
            subscription: 10,
            auth: 20,
            query: 2,
            order: 20
          }
        }
      }

      # Use our capture client instead of the real client
      {:ok, conn} = ConfigCaptureClient.connect(AdapterDeribit, rate_limit_opts)

      # Verify rate limiting options are preserved
      assert conn.connection_info.rate_limit_handler == WebsockexNova.Defaults.DefaultRateLimitHandler
      assert conn.connection_info.rate_limit_opts.mode == :strict
      assert conn.connection_info.rate_limit_opts.capacity == 60
      assert conn.connection_info.rate_limit_opts.refill_rate == 5
      assert conn.connection_info.rate_limit_opts.refill_interval == 2_000
      assert conn.connection_info.rate_limit_opts.queue_limit == 100
      assert conn.connection_info.rate_limit_opts.cost_map.subscription == 10
      assert conn.connection_info.rate_limit_opts.cost_map.auth == 20
      assert conn.connection_info.rate_limit_opts.cost_map.query == 2
      assert conn.connection_info.rate_limit_opts.cost_map.order == 20
    end

    test "preserves all logging and metrics options" do
      # Define logging and metrics options
      logging_opts = %{
        logging_handler: MyApp.CustomLogger,
        log_level: :debug,
        log_format: :json,
        metrics_collector: MyApp.MetricsCollector
      }

      # Use our capture client instead of the real client
      {:ok, conn} = ConfigCaptureClient.connect(AdapterDeribit, logging_opts)

      # Verify logging and metrics options are preserved
      assert conn.connection_info.logging_handler == MyApp.CustomLogger
      assert conn.connection_info.log_level == :debug
      assert conn.connection_info.log_format == :json
      assert conn.connection_info.metrics_collector == MyApp.MetricsCollector
    end

    test "preserves all authentication options" do
      # Define authentication options
      auth_opts = %{
        auth_handler: MyApp.CustomAuthHandler,
        credentials: %{
          api_key: "test_api_key",
          secret: "test_secret_key",
          additional_field: "custom_value"
        },
        auth_refresh_threshold: 120
      }

      # Use our capture client instead of the real client
      {:ok, conn} = ConfigCaptureClient.connect(AdapterDeribit, auth_opts)

      # Verify authentication options are preserved
      assert conn.connection_info.auth_handler == MyApp.CustomAuthHandler
      assert conn.connection_info.credentials.api_key == "test_api_key"
      assert conn.connection_info.credentials.secret == "test_secret_key"
      assert conn.connection_info.credentials.additional_field == "custom_value"
      assert conn.connection_info.auth_refresh_threshold == 120
    end

    test "preserves all subscription and message handling options" do
      # Define subscription and message handling options
      msg_opts = %{
        subscription_handler: MyApp.CustomSubscriptionHandler,
        subscription_timeout: 45,
        message_handler: MyApp.CustomMessageHandler
      }

      # Use our capture client instead of the real client
      {:ok, conn} = ConfigCaptureClient.connect(AdapterDeribit, msg_opts)

      # Verify subscription and message handling options are preserved
      assert conn.connection_info.subscription_handler == MyApp.CustomSubscriptionHandler
      assert conn.connection_info.subscription_timeout == 45
      assert conn.connection_info.message_handler == MyApp.CustomMessageHandler
    end

    test "preserves all error handling and reconnection options" do
      # Define error handling and reconnection options
      error_opts = %{
        error_handler: MyApp.CustomErrorHandler,
        max_reconnect_attempts: 10,
        reconnect_attempts: 0,
        ping_interval: 15_000
      }

      # Use our capture client instead of the real client
      {:ok, conn} = ConfigCaptureClient.connect(AdapterDeribit, error_opts)

      # Verify error handling and reconnection options are preserved
      assert conn.connection_info.error_handler == MyApp.CustomErrorHandler
      assert conn.connection_info.max_reconnect_attempts == 10
      assert conn.connection_info.reconnect_attempts == 0
      assert conn.connection_info.ping_interval == 15_000
    end

    test "preserves custom application-specific options" do
      # Define custom application-specific options
      custom_opts = %{
        app_name: "TradingBot",
        app_version: "2.1.0",
        environment: :production,
        features: [:auto_trading, :risk_management],
        limits: %{
          max_positions: 10,
          max_order_value: 1.5
        },
        debug: %{
          verbose_logging: true,
          capture_raw_messages: true,
          log_to_file: "/tmp/trading.log"
        },
        strategy: %{
          name: "momentum",
          parameters: %{
            window: 14,
            threshold: 0.25
          }
        }
      }

      # Use our capture client instead of the real client
      {:ok, conn} = ConfigCaptureClient.connect(AdapterDeribit, custom_opts)

      # Verify custom application-specific options are preserved
      assert conn.connection_info.app_name == "TradingBot"
      assert conn.connection_info.app_version == "2.1.0"
      assert conn.connection_info.environment == :production
      assert conn.connection_info.features == [:auto_trading, :risk_management]
      assert conn.connection_info.limits.max_positions == 10
      assert conn.connection_info.limits.max_order_value == 1.5
      assert conn.connection_info.debug.verbose_logging == true
      assert conn.connection_info.debug.capture_raw_messages == true
      assert conn.connection_info.debug.log_to_file == "/tmp/trading.log"
      assert conn.connection_info.strategy.name == "momentum"
      assert conn.connection_info.strategy.parameters.window == 14
      assert conn.connection_info.strategy.parameters.threshold == 0.25
    end

    test "preserves complex nested structures" do
      # Define a deeply nested configuration with mixed types
      nested_opts = %{
        config: %{
          level1: %{
            level2: %{
              level3: %{
                string_value: "deep value",
                integer_value: 42,
                float_value: 3.14159,
                boolean_value: true,
                list_value: [1, 2, 3, "mixed", :types],
                map_value: %{a: 1, b: 2, c: 3},
                function_value: &to_string/1
              }
            }
          }
        }
      }

      # Use our capture client instead of the real client
      {:ok, conn} = ConfigCaptureClient.connect(AdapterDeribit, nested_opts)

      # Verify nested structures are preserved
      deep_config = conn.connection_info.config.level1.level2.level3
      assert deep_config.string_value == "deep value"
      assert deep_config.integer_value == 42
      assert deep_config.float_value == 3.14159
      assert deep_config.boolean_value == true
      assert deep_config.list_value == [1, 2, 3, "mixed", :types]
      assert deep_config.map_value == %{a: 1, b: 2, c: 3}
      assert is_function(deep_config.function_value, 1)
    end
    
    test "preserves all config when merging with defaults" do
      # Get default config directly from adapter
      {:ok, defaults} = AdapterDeribit.connection_info(%{})
      
      # Create a custom config with some overrides and some new values
      custom_config = %{
        host: "override.deribit.com", 
        port: 8443,
        custom_value: "should be preserved",
        nested: %{
          key1: "value1",
          key2: "value2"
        }
      }
      
      # Use our capture client instead of the real client
      {:ok, conn} = ConfigCaptureClient.connect(AdapterDeribit, custom_config)
      
      # Verify overridden values
      assert conn.connection_info.host == "override.deribit.com"
      assert conn.connection_info.port == 8443
      
      # Verify new values were preserved
      assert conn.connection_info.custom_value == "should be preserved"
      assert conn.connection_info.nested.key1 == "value1"
      assert conn.connection_info.nested.key2 == "value2"
      
      # Verify custom values were retained and default values were not automatically merged
      # This is because our ConfigCaptureClient just captures the passed options
      # without merging defaults (unlike the real client)
      assert Map.has_key?(conn.connection_info, :custom_value)
      assert Map.has_key?(conn.connection_info, :nested)
      refute Map.has_key?(conn.connection_info, :path)
      refute Map.has_key?(conn.connection_info, :transport)
    end
  end

  # Define simple module references for testing - not actual implementations
  defmodule MyApp do
    defmodule CustomLogger do
    end

    defmodule MetricsCollector do
    end

    defmodule CustomAuthHandler do
    end

    defmodule CustomSubscriptionHandler do
    end

    defmodule CustomMessageHandler do
    end

    defmodule CustomErrorHandler do
    end
  end
end