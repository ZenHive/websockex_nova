defmodule WebsockexNova.Integration.ConfigPrecedenceAdvancedTest do
  @moduledoc """
  Advanced configuration precedence tests covering complex settings
  like reconnection policies, rate limiting, auth, error handling, etc.
  """

  use ExUnit.Case, async: true

  alias WebsockexNova.Defaults.DefaultAuthHandler
  alias WebsockexNova.Defaults.DefaultRateLimitHandler
  alias WebsockexNova.Defaults.DefaultSubscriptionHandler
  alias WebsockexNova.Examples.AdapterDeribit

  describe "advanced configuration precedence" do
    test "reconnection configuration precedence" do
      # Define a client with custom reconnection defaults
      defmodule ReconnectClient do
        @moduledoc false
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
          config =
            adapter_defaults
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
        # Override client
        max_reconnect_attempts: 50,
        # Override client
        base_backoff: 10_000,
        # Add new field
        custom_reconnect_field: true
      }

      {:ok, config} = ReconnectClient.connect(AdapterDeribit, user_opts)

      # Verify complex precedence
      # User wins
      assert config.max_reconnect_attempts == 50
      # Client wins over adapter
      assert config.retry == 15
      # Client wins over adapter
      assert config.backoff_type == :exponential
      # User wins
      assert config.base_backoff == 10_000
      # Client wins
      assert config.ping_interval == 45_000
      # User addition
      assert config.custom_reconnect_field == true

      # Adapter defaults still present
      # Client wins over adapter
      assert config.subscription_timeout == 60
      # Adapter default
      assert config.auth_refresh_threshold == 60
    end

    test "rate limiting configuration precedence" do
      # Define a client with custom rate limiting
      defmodule RateLimitClient do
        @moduledoc false
        def connect(adapter, user_opts) do
          client_defaults = %{
            rate_limit_handler: DefaultRateLimitHandler,
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
          config =
            adapter_defaults
            |> deep_merge(client_defaults)
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
          # Override
          capacity: 300,
          cost_map: %{
            # Override
            subscription: 5,
            # Add new
            custom_operation: 25
          }
        }
      }

      {:ok, config} = RateLimitClient.connect(AdapterDeribit, user_opts)

      # Check nested configuration precedence
      assert config.rate_limit_handler == DefaultRateLimitHandler
      # Client default
      assert config.rate_limit_opts.mode == :strict
      # User override
      assert config.rate_limit_opts.capacity == 300
      # Client default
      assert config.rate_limit_opts.refill_rate == 20
      # Client default
      assert config.rate_limit_opts.queue_limit == 500

      # Cost map is partially overridden
      # User override
      assert config.rate_limit_opts.cost_map.subscription == 5
      # Client default
      assert config.rate_limit_opts.cost_map.auth == 20
      # User addition
      assert config.rate_limit_opts.cost_map.custom_operation == 25
      # Client default
      assert config.rate_limit_opts.cost_map.order == 15
    end

    test "authentication configuration precedence" do
      # Define a client with auth defaults
      defmodule AuthClient do
        @moduledoc false
        def connect(adapter, user_opts) do
          client_defaults = %{
            credentials: %{
              api_key: "default_client_key",
              secret: "default_client_secret",
              environment: :test
            },
            auth_handler: DefaultAuthHandler,
            auth_refresh_threshold: 120,
            auth_auto_refresh: true,
            auth_retry_attempts: 3
          }

          {:ok, adapter_state} = adapter.init([])
          {:ok, adapter_defaults} = adapter.connection_info(adapter_state)

          config =
            adapter_defaults
            |> deep_merge(client_defaults)
            |> deep_merge(user_opts)

          {:ok, config}
        end

        # Deep merge helper (special handling for credentials)
        defp deep_merge(left, right) do
          Map.merge(left, right, fn
            # Credentials are replaced completely
            :credentials, _v1, v2 -> v2
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
      # Not in user opts
      refute Map.has_key?(config.credentials, :environment)

      # Other auth settings
      assert config.auth_handler == DefaultAuthHandler
      # User override
      assert config.auth_refresh_threshold == 300
      # Client default
      assert config.auth_auto_refresh == true
      # Client default
      assert config.auth_retry_attempts == 3
      # User addition
      assert config.custom_auth_field == "user_auth_data"
    end

    test "handler configuration precedence" do
      # Define a client with custom handlers
      defmodule HandlerClient do
        @moduledoc false
        def connect(adapter, user_opts) do
          client_defaults = %{
            # Custom handlers at client level
            connection_handler: CustomConnectionHandler,
            message_handler: CustomMessageHandler,
            error_handler: CustomErrorHandler,
            logging_handler: CustomLoggingHandler,
            # Keep some defaults
            subscription_handler: DefaultSubscriptionHandler,
            rate_limit_handler: DefaultRateLimitHandler,
            # Handler-specific settings
            logging_opts: %{
              level: :debug,
              format: :json,
              include_metadata: true
            }
          }

          {:ok, adapter_state} = adapter.init([])
          {:ok, adapter_defaults} = adapter.connection_info(adapter_state)

          config =
            adapter_defaults
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
          # Override client default
          level: :warn,
          custom_log_field: true
        }
      }

      {:ok, config} = HandlerClient.connect(AdapterDeribit, user_opts)

      # Verify handler precedence
      # Client default
      assert config.connection_handler == CustomConnectionHandler
      # User override
      assert config.message_handler == UserMessageHandler
      # Client default
      assert config.error_handler == CustomErrorHandler
      # User override
      assert config.logging_handler == UserLoggingHandler
      assert config.subscription_handler == DefaultSubscriptionHandler
      # User addition
      assert config.metrics_collector == UserMetricsCollector

      # Handler options
      # User override
      assert config.logging_opts.level == :warn
      # Client default
      assert config.logging_opts.format == :json
      # Client default
      assert config.logging_opts.include_metadata == true
      # User addition
      assert config.logging_opts.custom_log_field == true
    end

    test "transport and connection options precedence" do
      # Define a client with transport defaults
      defmodule TransportClient do
        @moduledoc false
        def connect(adapter, user_opts) do
          client_defaults = %{
            transport: :tls,
            transport_opts: %{
              verify: :verify_peer,
              cacerts: :public_key.cacerts_get(),
              depth: 3,
              server_name_indication: ~c"client.deribit.com",
              versions: [:"tlsv1.3", :"tlsv1.2"]
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
          config =
            adapter_defaults
            |> deep_merge(client_defaults)
            |> deep_merge(user_opts)

          {:ok, config}
        end

        defp deep_merge(left, right) do
          Map.merge(left, right, fn
            _k, %{} = v1, %{} = v2 -> deep_merge(v1, v2)
            # Replace lists
            _k, v1, v2 when is_list(v1) and is_list(v2) -> v2
            _k, _v1, v2 -> v2
          end)
        end
      end

      # User customizes transport
      user_opts = %{
        transport_opts: %{
          # Override for testing
          verify: :verify_none,
          custom_tls_option: true
        },
        headers: [
          # Replace entire list
          {"user-agent", "CustomClient/2.0"},
          {"x-custom-header", "custom-value"}
        ],
        ws_opts: %{
          # Override
          max_frame_size: 2_000_000
        }
      }

      {:ok, config} = TransportClient.connect(AdapterDeribit, user_opts)

      # Transport options
      # Client default
      assert config.transport == :tls
      # User override
      assert config.transport_opts.verify == :verify_none
      # Client default
      assert config.transport_opts.depth == 3
      # User addition
      assert config.transport_opts.custom_tls_option == true
      assert config.transport_opts.server_name_indication == ~c"client.deribit.com"

      # Headers completely replaced (not merged)
      assert config.headers == [
               {"user-agent", "CustomClient/2.0"},
               {"x-custom-header", "custom-value"}
             ]

      # WebSocket options
      # Client default
      assert config.ws_opts.compress == true
      # User override
      assert config.ws_opts.max_frame_size == 2_000_000

      # Protocols
      # Client default
      assert config.protocols == [:http2, :http]
    end

    test "complete configuration with all levels" do
      # Test with all configuration levels
      defmodule CompleteClient do
        @moduledoc false
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

          config =
            adapter_defaults
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
      # User wins
      assert config.host == "production.deribit.com"
      # Client wins
      assert config.timeout == 20_000
      # Client wins
      assert config.max_reconnect_attempts == 25
      # Adapter default
      assert config.port == 443
      # Client addition
      assert config.client_id == "complete_client_v1"
      # User addition
      assert config.session_id == "user_session_123"

      # Nested features (with deep merge)
      # User override
      assert config.features.debug_mode == true
      # User addition
      assert config.features.custom_feature == "enabled"
      # Client default preserved
      assert config.features.auto_heartbeat == true
      # Client default preserved
      assert config.features.auto_resubscribe == true
    end
  end
end
