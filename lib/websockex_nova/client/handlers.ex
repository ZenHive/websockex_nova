defmodule WebsockexNova.Client.Handlers do
  @moduledoc """
  Utility functions for registering various handler behaviors with WebsockexNova connections.

  This module provides helper functions to set up behavior handlers for WebSocket connections,
  ensuring that appropriate defaults are used when not explicitly provided.
  """

  @doc """
  Configures handlers for a WebSocket connection based on the adapter module.

  This function examines the adapter module to determine which behaviors it implements,
  and configures the connection options accordingly. For any behavior not implemented
  by the adapter, it falls back to the default implementation.

  ## Parameters

  * `adapter` - Module implementing one or more WebsockexNova behaviors
  * `options` - Connection options (may already contain handler configurations)

  ## Returns

  * Updated options map with all handler configurations
  """
  @spec configure_handlers(module(), map()) :: map()
  def configure_handlers(adapter, options) when is_atom(adapter) and is_map(options) do
    options
    |> configure_connection_handler(adapter)
    |> configure_message_handler(adapter)
    |> configure_subscription_handler(adapter)
    |> configure_auth_handler(adapter)
    |> configure_error_handler(adapter)
    |> configure_rate_limit_handler(adapter)
    |> configure_logging_handler(adapter)
    |> configure_metrics_collector(adapter)
  end

  # Configure connection handler
  defp configure_connection_handler(options, adapter) do
    if Map.has_key?(options, :connection_handler) do
      options
    else
      if implements?(adapter, WebsockexNova.Behaviors.ConnectionHandler) do
        Map.put(options, :connection_handler, adapter)
      else
        Map.put(options, :connection_handler, WebsockexNova.Defaults.DefaultConnectionHandler)
      end
    end
  end

  # Configure message handler
  defp configure_message_handler(options, adapter) do
    if Map.has_key?(options, :message_handler) do
      options
    else
      if implements?(adapter, WebsockexNova.Behaviors.MessageHandler) do
        Map.put(options, :message_handler, adapter)
      else
        Map.put(options, :message_handler, WebsockexNova.Defaults.DefaultMessageHandler)
      end
    end
  end

  # Configure subscription handler
  defp configure_subscription_handler(options, adapter) do
    if Map.has_key?(options, :subscription_handler) do
      options
    else
      if implements?(adapter, WebsockexNova.Behaviors.SubscriptionHandler) do
        Map.put(options, :subscription_handler, adapter)
      else
        Map.put(options, :subscription_handler, WebsockexNova.Defaults.DefaultSubscriptionHandler)
      end
    end
  end

  # Configure auth handler
  defp configure_auth_handler(options, adapter) do
    if Map.has_key?(options, :auth_handler) do
      options
    else
      if implements?(adapter, WebsockexNova.Behaviors.AuthHandler) do
        Map.put(options, :auth_handler, adapter)
      else
        Map.put(options, :auth_handler, WebsockexNova.Defaults.DefaultAuthHandler)
      end
    end
  end

  # Configure error handler
  defp configure_error_handler(options, adapter) do
    if Map.has_key?(options, :error_handler) do
      options
    else
      if implements?(adapter, WebsockexNova.Behaviors.ErrorHandler) do
        Map.put(options, :error_handler, adapter)
      else
        Map.put(options, :error_handler, WebsockexNova.Defaults.DefaultErrorHandler)
      end
    end
  end

  # Configure rate limit handler
  defp configure_rate_limit_handler(options, adapter) do
    if Map.has_key?(options, :rate_limit_handler) do
      options
    else
      if implements?(adapter, WebsockexNova.Behaviors.RateLimitHandler) do
        Map.put(options, :rate_limit_handler, adapter)
      else
        Map.put(options, :rate_limit_handler, WebsockexNova.Defaults.DefaultRateLimitHandler)
      end
    end
  end

  # Configure logging handler
  defp configure_logging_handler(options, adapter) do
    if Map.has_key?(options, :logging_handler) do
      options
    else
      if implements?(adapter, WebsockexNova.Behaviors.LoggingHandler) do
        Map.put(options, :logging_handler, adapter)
      else
        Map.put(options, :logging_handler, WebsockexNova.Defaults.DefaultLoggingHandler)
      end
    end
  end

  # Configure metrics collector
  defp configure_metrics_collector(options, adapter) do
    if Map.has_key?(options, :metrics_collector) do
      options
    else
      if implements?(adapter, WebsockexNova.Behaviors.MetricsCollector) do
        Map.put(options, :metrics_collector, adapter)
      else
        Map.put(options, :metrics_collector, WebsockexNova.Defaults.DefaultMetricsCollector)
      end
    end
  end

  # Check if a module implements a behavior
  defp implements?(module, behavior) do
    :attributes
    |> module.__info__()
    |> Keyword.get_values(:behaviour)
    |> List.flatten()
    |> Enum.member?(behavior)
  rescue
    # Handle case where module doesn't exist or doesn't have __info__
    _ -> false
  end
end
