defmodule WebsockexNova.Defaults.DefaultLoggingHandler do
  @moduledoc """
  Default implementation of the LoggingHandler behavior for WebsockexNova.

  This module provides standardized logging for connection, message, and error events using Elixir's Logger. It supports configurable log levels and formats (plain or JSON).

  ## Configuration

  The log level and format can be set in the handler state as:

      %{log_level: :info, log_format: :plain}

  If not set, defaults are :info and :plain.
  """

  @behaviour WebsockexNova.Behaviors.LoggingHandler

  require Logger

  @impl true
  def log_connection_event(event, context, state) do
    log(:connection, event, context, state)
  end

  @impl true
  def log_message_event(event, context, state) do
    log(:message, event, context, state)
  end

  @impl true
  def log_error_event(event, context, state) do
    log(:error, event, context, state)
  end

  defp log(category, event, context, state) do
    level =
      case Map.get(state, :log_level, :info) do
        l when l in [:debug, :info, :warn, :warning, :error] -> l
        _ -> :info
      end

    format = Map.get(state, :log_format, :plain)
    msg = format_log(category, event, context, format)
    Logger.log(level, msg)
    :ok
  end

  defp format_log(category, event, context, :plain) do
    "[#{String.upcase(to_string(category))}] #{inspect(event)} | #{inspect(context)}"
  end

  defp format_log(category, event, context, :json) do
    data = %{category: category, event: event, context: context, timestamp: DateTime.utc_now()}
    Jason.encode!(data)
  end

  defp format_log(_category, event, context, other) do
    "[LOG][#{inspect(other)}] #{inspect(event)} | #{inspect(context)}"
  end

  @doc """
  Initializes the DefaultLoggingHandler state.

  Returns {:ok, opts} where opts is the options map (or empty map).
  """
  @spec init(map()) :: {:ok, map()}
  def init(opts) when is_map(opts), do: {:ok, opts}
end
