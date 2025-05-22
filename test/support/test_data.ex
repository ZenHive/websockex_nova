defmodule WebsockexNew.TestData do
  @moduledoc """
  Provides structured test data and message generators for WebSocket testing.
  
  Includes:
  - Authentication message patterns
  - Subscription message formats
  - Error scenarios and edge cases
  - Large message generation
  - Protocol-specific test data
  """

  @doc """
  Returns authentication messages for different scenarios.
  """
  @spec auth_messages() :: %{valid: binary(), invalid: binary(), malformed: binary()}
  def auth_messages do
    %{
      valid: Jason.encode!(%{
        id: 1,
        method: "public/auth",
        params: %{
          grant_type: "client_credentials",
          client_id: "test_client_id",
          client_secret: "test_client_secret"
        }
      }),
      
      invalid: Jason.encode!(%{
        id: 2,
        method: "public/auth",
        params: %{
          grant_type: "client_credentials",
          client_id: "invalid_client",
          client_secret: "invalid_secret"
        }
      }),
      
      malformed: "{\"id\": 3, \"method\": \"public/auth\", \"params\": {invalid_json"
    }
  end

  @doc """
  Returns subscription messages for testing channel subscriptions.
  """
  @spec subscription_messages() :: [binary()]
  def subscription_messages do
    [
      # Valid subscription
      Jason.encode!(%{
        id: 10,
        method: "public/subscribe",
        params: %{
          channels: ["ticker.BTC-PERPETUAL"]
        }
      }),
      
      # Multiple channels
      Jason.encode!(%{
        id: 11,
        method: "public/subscribe",
        params: %{
          channels: ["ticker.BTC-PERPETUAL", "ticker.ETH-PERPETUAL"]
        }
      }),
      
      # Invalid channel
      Jason.encode!(%{
        id: 12,
        method: "public/subscribe",
        params: %{
          channels: ["invalid.channel.name"]
        }
      }),
      
      # Unsubscribe message
      Jason.encode!(%{
        id: 13,
        method: "public/unsubscribe",
        params: %{
          channels: ["ticker.BTC-PERPETUAL"]
        }
      })
    ]
  end

  @doc """
  Generates a large message of specified size in KB.
  """
  @spec generate_large_message(pos_integer()) :: binary()
  def generate_large_message(size_kb) do
    size_bytes = size_kb * 1024
    
    # Create a large data payload
    data_size = size_bytes - 100  # Reserve space for JSON structure
    large_data = String.duplicate("x", max(1, data_size))
    
    Jason.encode!(%{
      id: 999,
      method: "test/large_message",
      params: %{
        data: large_data,
        size_kb: size_kb,
        timestamp: System.system_time()
      }
    })
  end

  @doc """
  Returns various malformed messages for error testing.
  """
  @spec malformed_messages() :: [binary()]
  def malformed_messages do
    [
      # Invalid JSON
      "{invalid json}",
      
      # Missing required fields
      "{}",
      
      # Wrong data types
      Jason.encode!(%{id: "should_be_number", method: 123}),
      
      # Extremely nested structure
      Jason.encode!(create_deeply_nested_object(50)),
      
      # Binary data in JSON field
      "{\"data\": \"" <> Base.encode64(:crypto.strong_rand_bytes(1000)) <> "\"}",
      
      # Null bytes
      "{\0\"test\0\": \0\"value\0\"}",
      
      # Very long field names
      Jason.encode!(%{String.duplicate("very_long_field_name_", 100) => "value"}),
      
      # Array instead of object
      Jason.encode!([1, 2, 3, 4, 5])
    ]
  end

  @doc """
  Returns heartbeat/ping messages for connection testing.
  """
  @spec heartbeat_messages() :: [binary()]
  def heartbeat_messages do
    [
      # Standard ping
      Jason.encode!(%{
        id: 100,
        method: "public/test"
      }),
      
      # Heartbeat with timestamp
      Jason.encode!(%{
        id: 101,
        method: "public/get_time"
      }),
      
      # Custom heartbeat
      Jason.encode!(%{
        id: 102,
        method: "heartbeat",
        params: %{
          timestamp: System.system_time(:millisecond)
        }
      })
    ]
  end

  @doc """
  Returns error response messages for testing error handling.
  """
  @spec error_messages() :: [binary()]
  def error_messages do
    [
      # Authentication error
      Jason.encode!(%{
        id: 1,
        error: %{
          code: -32000,
          message: "Invalid client credentials"
        }
      }),
      
      # Rate limit error
      Jason.encode!(%{
        id: 2,
        error: %{
          code: -32001,
          message: "Rate limit exceeded"
        }
      }),
      
      # Invalid method error
      Jason.encode!(%{
        id: 3,
        error: %{
          code: -32601,
          message: "Method not found"
        }
      }),
      
      # Internal server error
      Jason.encode!(%{
        id: 4,
        error: %{
          code: -32603,
          message: "Internal error"
        }
      }),
      
      # Custom error with details
      Jason.encode!(%{
        id: 5,
        error: %{
          code: 10001,
          message: "Subscription failed",
          data: %{
            reason: "Channel not available",
            retry_after: 5000
          }
        }
      })
    ]
  end

  @doc """
  Generates market data messages for testing data handling.
  """
  @spec market_data_messages() :: [binary()]
  def market_data_messages do
    [
      # Ticker update
      Jason.encode!(%{
        method: "subscription",
        params: %{
          channel: "ticker.BTC-PERPETUAL",
          data: %{
            best_ask_amount: 10.0,
            best_ask_price: 50000.0,
            best_bid_amount: 5.0,
            best_bid_price: 49950.0,
            instrument_name: "BTC-PERPETUAL",
            timestamp: System.system_time(:millisecond)
          }
        }
      }),
      
      # Order book update
      Jason.encode!(%{
        method: "subscription",
        params: %{
          channel: "book.BTC-PERPETUAL",
          data: %{
            type: "snapshot",
            timestamp: System.system_time(:millisecond),
            instrument_name: "BTC-PERPETUAL",
            bids: [[49900.0, 10.5], [49850.0, 5.2]],
            asks: [[50100.0, 8.3], [50150.0, 12.1]]
          }
        }
      }),
      
      # Trade data
      Jason.encode!(%{
        method: "subscription",
        params: %{
          channel: "trades.BTC-PERPETUAL",
          data: [%{
            amount: 1.5,
            direction: "buy",
            instrument_name: "BTC-PERPETUAL",
            price: 50000.0,
            timestamp: System.system_time(:millisecond),
            trade_id: "12345",
            trade_seq: 1001
          }]
        }
      })
    ]
  end

  @doc """
  Generates messages for stress testing with varying sizes and complexities.
  """
  @spec stress_test_messages(pos_integer()) :: [binary()]
  def stress_test_messages(count) do
    for i <- 1..count do
      # Vary message types and sizes
      case rem(i, 4) do
        0 -> generate_auth_message(i)
        1 -> generate_subscription_message(i)
        2 -> generate_heartbeat_message(i)
        3 -> generate_market_data_message(i)
      end
    end
  end

  @doc """
  Returns binary test data for non-JSON protocols.
  """
  @spec binary_test_data() :: [binary()]
  def binary_test_data do
    [
      # Simple binary message
      <<1, 2, 3, 4, 5>>,
      
      # WebSocket ping frame
      <<0x89, 0x04, 0x70, 0x69, 0x6E, 0x67>>,
      
      # Large binary payload
      :crypto.strong_rand_bytes(1024),
      
      # Empty binary
      <<>>,
      
      # Binary with null bytes
      <<0, 1, 0, 2, 0, 3>>,
      
      # Very large binary (1MB)
      :crypto.strong_rand_bytes(1024 * 1024)
    ]
  end

  @doc """
  Returns protocol-specific test data for different WebSocket subprotocols.
  """
  @spec protocol_specific_data(atom()) :: [binary()]
  def protocol_specific_data(:wamp) do
    # WAMP protocol messages
    [
      Jason.encode!([1, "realm1", %{}]),  # HELLO
      Jason.encode!([2, "session123", %{}]),  # WELCOME
      Jason.encode!([6, 1, %{}]),  # ABORT
      Jason.encode!([3, "error", "test.error"])  # GOODBYE
    ]
  end

  def protocol_specific_data(:json_rpc) do
    # JSON-RPC 2.0 messages
    [
      Jason.encode!(%{jsonrpc: "2.0", method: "test", id: 1}),
      Jason.encode!(%{jsonrpc: "2.0", result: "success", id: 1}),
      Jason.encode!(%{jsonrpc: "2.0", error: %{code: -1, message: "error"}, id: 1})
    ]
  end

  def protocol_specific_data(:custom) do
    # Custom protocol messages
    [
      "CONNECT\n",
      "SEND /queue/test\nhello world\n\x00",
      "DISCONNECT\n"
    ]
  end

  def protocol_specific_data(_protocol) do
    # Default to generic messages
    subscription_messages()
  end

  # Private helper functions

  defp create_deeply_nested_object(depth) when depth <= 0 do
    "base_value"
  end

  defp create_deeply_nested_object(depth) do
    %{"nested_#{depth}" => create_deeply_nested_object(depth - 1)}
  end

  defp generate_auth_message(id) do
    Jason.encode!(%{
      id: id,
      method: "public/auth",
      params: %{
        grant_type: "client_credentials",
        client_id: "test_#{id}",
        client_secret: "secret_#{id}"
      }
    })
  end

  defp generate_subscription_message(id) do
    channels = ["ticker.BTC-#{id}", "ticker.ETH-#{id}"]
    
    Jason.encode!(%{
      id: id,
      method: "public/subscribe",
      params: %{channels: channels}
    })
  end

  defp generate_heartbeat_message(id) do
    Jason.encode!(%{
      id: id,
      method: "public/test",
      params: %{timestamp: System.system_time(:millisecond)}
    })
  end

  defp generate_market_data_message(id) do
    Jason.encode!(%{
      method: "subscription",
      params: %{
        channel: "ticker.TEST-#{id}",
        data: %{
          best_ask_price: 1000.0 + id,
          best_bid_price: 999.0 + id,
          timestamp: System.system_time(:millisecond)
        }
      }
    })
  end
end