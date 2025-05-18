defmodule WebsockexNova.Integration.ConfigPrecedenceAdvancedTest do
  use ExUnit.Case, async: true

  alias WebsockexNova.Examples.AdapterDeribit

  @moduledoc """
  Advanced configuration precedence tests covering complex settings
  like reconnection policies, rate limiting, auth, error handling, etc.
  """

  describe "advanced configuration precedence" do
    test "reconnection configuration precedence" do
      # Define a client with custom reconnection defaults
      defmodule ReconnectClient do
        def connect(adapter, user_opts) do
          client_defaults = %{
            max_reconnect_attempts: 20,
            reconnect_attempts: 0,
            retry: 15,
            backoff_type: :exponential,
            base_backoff: 5000,
            # Add some other complex configs
            ping_interval: 45_000,
            subscription_timeout: 60
          }

          {:ok, adapter_state} = adapter.init([])
          {:ok, adapter_defaults} = adapter.connection_info(adapter_state)

          # Three-level merge
          config = adapter_defaults
                  |> deep_merge(client_defaults)
                  |> deep_merge(user_opts)

          {:ok, config}
        end

        # Deep merge helper
        defp deep_merge(left, right) do
          Map.merge(left, right, fn
            _k, %{} = v1, %{} = v2 -> deep_merge(v1, v2)
            _k, _v1, v2 -> v2
          end)
        end
      end

      # User overrides some reconnection settings
      user_opts = %{
        max_reconnect_attempts: 50,    # Override client
        base_backoff: 10_000,         # Override client
        custom_reconnect_field: true   # Add new field
      }

      {:ok, config} = ReconnectClient.connect(AdapterDeribit, user_opts)

      # Verify complex precedence
      assert config.max_reconnect_attempts == 50        # User wins
      assert config.retry == 15                         # Client wins over adapter
      assert config.backoff_type == :exponential        # Client wins over adapter
      assert config.base_backoff == 10_000              # User wins
      assert config.ping_interval == 45_000             # Client wins
      assert config.custom_reconnect_field == true      # User addition

      # Adapter defaults still present
      assert config.subscription_timeout == 60          # Client wins over adapter
      assert config.auth_refresh_threshold == 60        # Adapter default
    end

    test "rate limiting configuration precedence" do
      # Define a client with custom rate limiting
      defmodule RateLimitClient do
        def connect(adapter, user_opts) do
          client_defaults = %{
            rate_limit_handler: WebsockexNova.Defaults.DefaultRateLimitHandler,
            rate_limit_opts: %{
              mode: :strict,
              capacity: 200,
              refill_rate: 20,
              refill_interval: 2000,
              queue_limit: 500,
              cost_map: %{
                subscription: 10,
                auth: 20,
                query: 2,
                order: 15,
                cancel: 5
              }
            }
          }

          {:ok, adapter_state} = adapter.init([])
          {:ok, adapter_defaults} = adapter.connection_info(adapter_state)

          # Deep merge for nested maps
          config = deep_merge(adapter_defaults, client_defaults)
                  |> deep_merge(user_opts)

          {:ok, config}
        end

        # Simple deep merge helper
        defp deep_merge(left, right) do
          Map.merge(left, right, fn
            _k, %{} = v1, %{} = v2 -> deep_merge(v1, v2)
            _k, _v1, v2 -> v2
          end)
        end
      end

      # User fine-tunes rate limiting
      user_opts = %{
        rate_limit_opts: %{
          capacity: 300,                    # Override
          cost_map: %{
            subscription: 5,                # Override
            custom_operation: 25            # Add new
          }
        }
      }

      {:ok, config} = RateLimitClient.connect(AdapterDeribit, user_opts)

      # Check nested configuration precedence
      assert config.rate_limit_handler == WebsockexNova.Defaults.DefaultRateLimitHandler
      assert config.rate_limit_opts.mode == :strict           # Client default
      assert config.rate_limit_opts.capacity == 300           # User override
      assert config.rate_limit_opts.refill_rate == 20         # Client default
      assert config.rate_limit_opts.queue_limit == 500        # Client default

      # Cost map is partially overridden
      assert config.rate_limit_opts.cost_map.subscription == 5       # User override
      assert config.rate_limit_opts.cost_map.auth == 20             # Client default
      assert config.rate_limit_opts.cost_map.custom_operation == 25 # User addition
      assert config.rate_limit_opts.cost_map.order == 15            # Client default
    end

    test "authentication configuration precedence" do
      # Define a client with auth defaults
      defmodule AuthClient do
        def connect(adapter, user_opts) do
          client_defaults = %{
            credentials: %{
              api_key: "default_client_key",
              secret: "default_client_secret",
              environment: :test
            },
            auth_handler: WebsockexNova.Defaults.DefaultAuthHandler,
            auth_refresh_threshold: 120,
            auth_auto_refresh: true,
            auth_retry_attempts: 3
          }

          {:ok, adapter_state} = adapter.init([])
          {:ok, adapter_defaults} = adapter.connection_info(adapter_state)

          config = adapter_defaults
                  |> deep_merge(client_defaults)
                  |> deep_merge(user_opts)

          {:ok, config}
        end

        # Deep merge helper (special handling for credentials)
        defp deep_merge(left, right) do
          Map.merge(left, right, fn
            :credentials, _v1, v2 -> v2  # Credentials are replaced completely
            _k, %{} = v1, %{} = v2 -> deep_merge(v1, v2)
            _k, _v1, v2 -> v2
          end)
        end
      end

      # User provides real credentials
      user_opts = %{
        credentials: %{
          api_key: "real_user_key",
          secret: "real_user_secret"
          # Note: environment not provided, should be removed
        },
        auth_refresh_threshold: 300,
        custom_auth_field: "user_auth_data"
      }

      {:ok, config} = AuthClient.connect(AdapterDeribit, user_opts)

      # User credentials completely replace defaults
      assert config.credentials.api_key == "real_user_key"
      assert config.credentials.secret == "real_user_secret"
      refute Map.has_key?(config.credentials, :environment)  # Not in user opts

      # Other auth settings
      assert config.auth_handler == WebsockexNova.Defaults.DefaultAuthHandler
      assert config.auth_refresh_threshold == 300       # User override
      assert config.auth_auto_refresh == true           # Client default
      assert config.auth_retry_attempts == 3            # Client default
      assert config.custom_auth_field == "user_auth_data"  # User addition
    end

    test "handler configuration precedence" do
      # Define a client with custom handlers
      defmodule HandlerClient do
        def connect(adapter, user_opts) do
          client_defaults = %{
            # Custom handlers at client level
            connection_handler: CustomConnectionHandler,
            message_handler: CustomMessageHandler,
            error_handler: CustomErrorHandler,
            logging_handler: CustomLoggingHandler,
            # Keep some defaults
            subscription_handler: WebsockexNova.Defaults.DefaultSubscriptionHandler,
            rate_limit_handler: WebsockexNova.Defaults.DefaultRateLimitHandler,
            # Handler-specific settings
            logging_opts: %{
              level: :debug,
              format: :json,
              include_metadata: true
            }
          }

          {:ok, adapter_state} = adapter.init([])
          {:ok, adapter_defaults} = adapter.connection_info(adapter_state)

          config = adapter_defaults
                  |> deep_merge(client_defaults)
                  |> deep_merge(user_opts)

          {:ok, config}
        end

        # Deep merge helper
        defp deep_merge(left, right) do
          Map.merge(left, right, fn
            _k, %{} = v1, %{} = v2 -> deep_merge(v1, v2)
            _k, _v1, v2 -> v2
          end)
        end
      end

      # User overrides specific handlers
      user_opts = %{
        message_handler: UserMessageHandler,
        logging_handler: UserLoggingHandler,
        metrics_collector: UserMetricsCollector,
        logging_opts: %{
          level: :warn,  # Override client default
          custom_log_field: true
        }
      }

      {:ok, config} = HandlerClient.connect(AdapterDeribit, user_opts)

      # Verify handler precedence
      assert config.connection_handler == CustomConnectionHandler    # Client default
      assert config.message_handler == UserMessageHandler           # User override
      assert config.error_handler == CustomErrorHandler             # Client default
      assert config.logging_handler == UserLoggingHandler           # User override
      assert config.subscription_handler == WebsockexNova.Defaults.DefaultSubscriptionHandler
      assert config.metrics_collector == UserMetricsCollector       # User addition

      # Handler options
      assert config.logging_opts.level == :warn                     # User override
      assert config.logging_opts.format == :json                    # Client default
      assert config.logging_opts.include_metadata == true           # Client default
      assert config.logging_opts.custom_log_field == true           # User addition
    end

    test "transport and connection options precedence" do
      # Define a client with transport defaults
      defmodule TransportClient do
        def connect(adapter, user_opts) do
          client_defaults = %{
            transport: :tls,
            transport_opts: %{
              verify: :verify_peer,
              cacerts: :public_key.cacerts_get(),
              depth: 3,
              server_name_indication: ~c"client.deribit.com",
              versions: [:'tlsv1.3', :'tlsv1.2']
            },
            protocols: [:http2, :http],
            headers: [
              {"user-agent", "ClientDeribit/1.0"},
              {"x-client-version", "1.0.0"}
            ],
            ws_opts: %{
              compress: true,
              max_frame_size: 1_000_000
            }
          }

          {:ok, adapter_state} = adapter.init([])
          {:ok, adapter_defaults} = adapter.connection_info(adapter_state)

          # Deep merge for nested options
          config = deep_merge(adapter_defaults, client_defaults)
                  |> deep_merge(user_opts)

          {:ok, config}
        end

        defp deep_merge(left, right) do
          Map.merge(left, right, fn
            _k, %{} = v1, %{} = v2 -> deep_merge(v1, v2)
            _k, v1, v2 when is_list(v1) and is_list(v2) -> v2  # Replace lists
            _k, _v1, v2 -> v2
          end)
        end
      end

      # User customizes transport
      user_opts = %{
        transport_opts: %{
          verify: :verify_none,           # Override for testing
          custom_tls_option: true
        },
        headers: [
          {"user-agent", "CustomClient/2.0"},  # Replace entire list
          {"x-custom-header", "custom-value"}
        ],
        ws_opts: %{
          max_frame_size: 2_000_000       # Override
        }
      }

      {:ok, config} = TransportClient.connect(AdapterDeribit, user_opts)

      # Transport options
      assert config.transport == :tls                               # Client default
      assert config.transport_opts.verify == :verify_none           # User override
      assert config.transport_opts.depth == 3                       # Client default
      assert config.transport_opts.custom_tls_option == true        # User addition
      assert config.transport_opts.server_name_indication == ~c"client.deribit.com"

      # Headers completely replaced (not merged)
      assert config.headers == [
        {"user-agent", "CustomClient/2.0"},
        {"x-custom-header", "custom-value"}
      ]

      # WebSocket options
      assert config.ws_opts.compress == true                        # Client default
      assert config.ws_opts.max_frame_size == 2_000_000            # User override

      # Protocols
      assert config.protocols == [:http2, :http]                    # Client default
    end

    test "complete configuration with all levels" do
      # Test with all configuration levels
      defmodule CompleteClient do
        def connect(adapter, user_opts) do
          client_defaults = %{
            # Override adapter defaults
            host: "complete-client.deribit.com",
            timeout: 20_000,
            max_reconnect_attempts: 25,

            # Add client-specific configurations
            client_id: "complete_client_v1",
            features: %{
              auto_heartbeat: true,
              auto_resubscribe: true,
              debug_mode: false
            }
          }

          {:ok, adapter_state} = adapter.init([])
          {:ok, adapter_defaults} = adapter.connection_info(adapter_state)

          config = adapter_defaults
                  |> deep_merge(client_defaults)
                  |> deep_merge(user_opts)

          {:ok, config}
        end

        # Deep merge helper
        defp deep_merge(left, right) do
          Map.merge(left, right, fn
            _k, %{} = v1, %{} = v2 -> deep_merge(v1, v2)
            _k, _v1, v2 -> v2
          end)
        end
      end

      # User provides final overrides
      user_opts = %{
        host: "production.deribit.com",
        features: %{
          debug_mode: true,
          custom_feature: "enabled"
        },
        session_id: "user_session_123"
      }

      {:ok, config} = CompleteClient.connect(AdapterDeribit, user_opts)

      # Final precedence verification
      assert config.host == "production.deribit.com"        # User wins
      assert config.timeout == 20_000                       # Client wins
      assert config.max_reconnect_attempts == 25            # Client wins
      assert config.port == 443                             # Adapter default
      assert config.client_id == "complete_client_v1"       # Client addition
      assert config.session_id == "user_session_123"        # User addition

      # Nested features (with deep merge)
      assert config.features.debug_mode == true             # User override
      assert config.features.custom_feature == "enabled"    # User addition
      assert config.features.auto_heartbeat == true         # Client default preserved
      assert config.features.auto_resubscribe == true       # Client default preserved
    end
  end
end
