defmodule WebsockexNova.Defaults.DefaultLoggingHandler do
  @moduledoc """
  Default implementation of the LoggingHandler behavior for WebsockexNova.

  This module provides standardized logging for connection, message, and error events using Elixir's Logger. It supports configurable log levels and formats (plain or JSON).

  ## Configuration

  The log level and format can be set in the handler state as:

      %{log_level: :info, log_format: :plain}

  If not set, defaults are :info and :plain.
  All logging state is now stored in the canonical WebsockexNova.ClientConn struct under the :logging field.
  """

  @behaviour WebsockexNova.Behaviors.LoggingHandler

  alias WebsockexNova.ClientConn

  require Logger

  @impl true
  def log_connection_event(event, context, %ClientConn{logging: logging} = _conn)
      when is_map(context) and is_map(logging) do
    event_map = ensure_map(event)
    log(:connection, event_map, context, logging)
    :ok
  end

  @impl true
  def log_message_event(event, context, %ClientConn{logging: logging} = _conn) when is_map(context) and is_map(logging) do
    event_map = ensure_map(event)
    log(:message, event_map, context, logging)
    :ok
  end

  @impl true
  def log_error_event(event, context, %ClientConn{logging: logging} = _conn) when is_map(context) and is_map(logging) do
    event_map = ensure_map(event)
    log(:error, event_map, context, logging)
    :ok
  end

  @doc """
  Initializes the DefaultLoggingHandler state in the canonical struct.
  Returns {:ok, conn} where conn is the canonical struct with logging config set.
  """
  @spec logging_init(map()) :: {:ok, ClientConn.t()}
  def logging_init(opts) when is_map(opts), do: {:ok, %ClientConn{logging: opts}}
  def logging_init(_), do: {:ok, %ClientConn{logging: %{}}}

  # Private helper functions

  defp log(category, event, context, logging) when is_map(event) and is_map(context) and is_map(logging) do
    level =
      case Map.get(logging, :log_level, :info) do
        l when l in [:debug, :info, :warn, :warning, :error] -> l
        _ -> :info
      end

    format = Map.get(logging, :log_format, :plain)
    msg = format_log(category, event, context, format)
    Logger.log(level, msg)
    :ok
  end

  defp format_log(category, event, context, :plain) do
    "[#{String.upcase(to_string(category))}] #{inspect(event)} | #{inspect(context)}"
  end

  defp format_log(category, event, context, :json) do
    data = %{
      category: category,
      event: event,
      context: context,
      timestamp: DateTime.utc_now()
    }

    Jason.encode!(data)
  end

  defp format_log(category, event, context, other) do
    "[LOG][#{inspect(other)}] #{inspect(event)} | #{inspect(context)} #{inspect(category)}"
  end

  # Ensure event is a map
  defp ensure_map(event) when is_map(event), do: event
  defp ensure_map(event) when is_binary(event), do: %{message: event}
  defp ensure_map(event) when is_atom(event), do: %{type: event}

  defp ensure_map(event) when is_tuple(event) do
    case event do
      {type, data} when is_atom(type) -> %{type: type, data: ensure_map(data)}
      _ -> %{value: inspect(event)}
    end
  end

  defp ensure_map(event), do: %{value: inspect(event)}
end
