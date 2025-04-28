alias WebsockexNova.Client
alias WebsockexNova.Examples.ClientDeribit

# .iex.exs -- WebsockexNova debugging helpers

import IEx.Helpers
require Logger

# All helpers are now in WebsockexNova.IExHelpers

defmodule WebsockexNova.IExHelpers do
  @moduledoc """
  IEx helpers for inspecting WebsockexNova connection state.

  Usage in IEx:
    import WebsockexNova.IExHelpers
    conn, state = get_conn_state(conn)
    print_conn(conn)
    print_adapter(conn)
    print_handlers(conn)
    print_full_config(conn)
  """

  # Helper to get the canonical conn and adapter state from a running connection
  # Usage: {conn, state} = get_conn_state(conn)
  def get_conn_state(conn) do
    state = :sys.get_state(conn.transport_pid)
    {conn, state}
  end

  # Helper to pretty-print the top-level fields of conn
  # Usage: print_conn(conn)
  def print_conn(conn) do
    IO.puts("\n=== WebsockexNova.ClientConn (top-level) ===")
    conn
    |> Map.from_struct()
    |> Enum.reject(fn {k, _v} -> k in [:adapter_state, :connection_handler_settings, :auth_handler_settings, :subscription_handler_settings, :error_handler_settings, :message_handler_settings, :extras] end)
    |> Enum.each(fn {k, v} -> IO.puts("#{k}: #{inspect(v, pretty: true)}") end)
    IO.puts("\n--- Handler/Feature State ---")
    IO.puts("rate_limit: #{inspect(conn.rate_limit, pretty: true)}")
    IO.puts("logging: #{inspect(conn.logging, pretty: true)}")
    IO.puts("metrics: #{inspect(conn.metrics, pretty: true)}")
    IO.puts("subscriptions: #{inspect(conn.subscriptions, pretty: true)}")
    IO.puts("reconnection: #{inspect(conn.reconnection, pretty: true)}")
    IO.puts("auth_status: #{inspect(conn.auth_status)}")
    IO.puts("auth_expires_at: #{inspect(conn.auth_expires_at)}")
    IO.puts("auth_refresh_threshold: #{inspect(conn.auth_refresh_threshold)}")
    IO.puts("last_error: #{inspect(conn.last_error)}")
    IO.puts("\n--- Handler Settings ---")
    IO.puts("connection_handler_settings: #{inspect(conn.connection_handler_settings, pretty: true)}")
    IO.puts("auth_handler_settings: #{inspect(conn.auth_handler_settings, pretty: true)}")
    IO.puts("subscription_handler_settings: #{inspect(conn.subscription_handler_settings, pretty: true)}")
    IO.puts("error_handler_settings: #{inspect(conn.error_handler_settings, pretty: true)}")
    IO.puts("message_handler_settings: #{inspect(conn.message_handler_settings, pretty: true)}")
    IO.puts("\n--- Extras ---")
    IO.puts("extras: #{inspect(conn.extras, pretty: true)}")
    # Print full config if present in extras or handler settings
    full_config = conn.extras[:full_config] || conn.connection_handler_settings[:full_config]
    if full_config do
      IO.puts("\n--- Full Adapter Config (from :full_config) ---")
      IO.inspect(full_config, pretty: true)
    end
    :ok
  end

  # Helper to print the adapter module and its state
  # Usage: print_adapter(conn)
  def print_adapter(conn) do
    IO.puts("\n=== Adapter Info ===")
    IO.puts("adapter: #{inspect(conn.adapter)}")
    IO.puts("adapter_state: #{inspect(conn.adapter_state, pretty: true)}")
    :ok
  end

  # Helper to print all handler-specific state in detail
  # Usage: print_handlers(conn)
  def print_handlers(conn) do
    IO.puts("\n=== Handler State ===")
    IO.puts("connection_handler_settings: #{inspect(conn.connection_handler_settings, pretty: true)}")
    IO.puts("auth_handler_settings: #{inspect(conn.auth_handler_settings, pretty: true)}")
    IO.puts("subscription_handler_settings: #{inspect(conn.subscription_handler_settings, pretty: true)}")
    IO.puts("error_handler_settings: #{inspect(conn.error_handler_settings, pretty: true)}")
    IO.puts("message_handler_settings: #{inspect(conn.message_handler_settings, pretty: true)}")
    :ok
  end

  # Helper to print just the full config if present
  # Usage: print_full_config(conn)
  def print_full_config(conn) do
    full_config = conn.extras[:full_config] || conn.connection_handler_settings[:full_config]
    if full_config do
      IO.puts("\n=== Full Adapter Config (from :full_config) ===")
      IO.inspect(full_config, pretty: true)
    else
      IO.puts("No :full_config found in conn.extras or conn.connection_handler_settings.")
    end
    :ok
  end
end

# Make helpers available directly in IEx
import WebsockexNova.IExHelpers

# Usage:
#   {conn, state} = get_conn_state(conn)
#   print_conn(conn)
#   print_adapter(conn)
#   print_handlers(conn)
#   print_full_config(conn)
