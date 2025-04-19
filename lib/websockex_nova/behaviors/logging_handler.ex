defmodule WebsockexNova.Behaviors.LoggingHandler do
  @moduledoc """
  Defines the behavior for standardized, configurable logging in WebsockexNova.

  The LoggingHandler behavior enables pluggable, context-aware logging for connection, message, and error events. This allows applications to customize log levels, formats, and destinations, supporting both structured and unstructured logging.

  ## Usage

  Implement this behavior to control how connection, message, and error events are logged. You may use the default implementation or provide your own for advanced formatting, filtering, or integration with external systems.

  ## Callbacks

  * `log_connection_event/3` - Log a connection lifecycle event
  * `log_message_event/3` - Log a message send/receive event
  * `log_error_event/3` - Log an error event with context

  ## Configuration

  Implementations should support configuration for log level (e.g., :debug, :info, :warn, :error) and log format (e.g., :plain, :json). These can be provided via handler state or options.

  ## Example

  ```elixir
  defmodule MyApp.LoggingHandler do
    @behaviour WebsockexNova.Behaviors.LoggingHandler

    @impl true
    def log_connection_event(event, context, state) do
      # Custom logging logic
      :ok
    end

    @impl true
    def log_message_event(event, context, state) do
      # Custom logging logic
      :ok
    end

    @impl true
    def log_error_event(event, context, state) do
      # Custom logging logic
      :ok
    end
  end
  ```
  """

  @typedoc """
  Event type for connection, message, or error events.
  """
  @type event :: atom() | String.t() | map()

  @typedoc """
  Context information about the event (e.g., connection details, message payload, error info).
  """
  @type context :: map()

  @typedoc """
  Handler state - can be any term.
  """
  @type state :: term()

  @typedoc """
  Log level (:debug, :info, :warn, :error).
  """
  @type log_level :: :debug | :info | :warn | :error

  @typedoc """
  Log format (:plain, :json, or custom atom).
  """
  @type log_format :: :plain | :json | atom()

  @doc """
  Log a connection lifecycle event (e.g., connect, disconnect, reconnect).

  ## Parameters
  * `event` - The connection event (atom, string, or map)
  * `context` - Additional context (map)
  * `state` - Current handler state

  ## Returns
  * `:ok`
  """
  @callback log_connection_event(event(), context(), state()) :: :ok

  @doc """
  Log a message event (send/receive).

  ## Parameters
  * `event` - The message event (atom, string, or map)
  * `context` - Additional context (map)
  * `state` - Current handler state

  ## Returns
  * `:ok`
  """
  @callback log_message_event(event(), context(), state()) :: :ok

  @doc """
  Log an error event with context.

  ## Parameters
  * `event` - The error event (atom, string, or map)
  * `context` - Additional context (map)
  * `state` - Current handler state

  ## Returns
  * `:ok`
  """
  @callback log_error_event(event(), context(), state()) :: :ok
end
