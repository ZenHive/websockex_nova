defmodule WebsockexNova.Behaviors.LoggingHandler do
  @moduledoc """
  Defines the behavior for standardized, configurable logging in WebsockexNova.

  The LoggingHandler behavior enables pluggable, context-aware logging for connection, message, and error events. This allows applications to customize log levels, formats, and destinations, supporting both structured and unstructured logging.

  ## Usage

  All Gun pipeline modules, helpers, and test/mock handlers now use the logging handler for connection, message, and error events. If a logging handler is not present in the connection state, logging falls back to Elixir's Logger.

  ### Configuring a Custom Logging Handler

  To use a custom logging handler, add it to your connection state:

      state = %{logging_handler: MyApp.LoggingHandler, ...}

  Your handler module must implement the `WebsockexNova.Behaviors.LoggingHandler` behavior.

  ### Implementing the LoggingHandler Behavior

      defmodule MyApp.LoggingHandler do
        @behaviour WebsockexNova.Behaviors.LoggingHandler

        @impl true
        def log_connection_event(event, context, state) do
          # Custom connection event logging
          :ok
        end

        @impl true
        def log_message_event(event, context, state) do
          # Custom message event logging
          :ok
        end

        @impl true
        def log_error_event(event, context, state) do
          # Custom error event logging
          :ok
        end
      end

  ### Example: Plugging in a Custom Handler

      state = %{logging_handler: MyApp.LoggingHandler, ...}
      # Pass this state to your connection pipeline

  ### Example: Capturing Log Events in Tests

      defmodule MyTest.LoggingHandler do
        @behaviour WebsockexNova.Behaviors.LoggingHandler
        def log_connection_event(event, context, state), do: send(self(), {:log, :connection, event, context}); :ok
        def log_message_event(event, context, state), do: send(self(), {:log, :message, event, context}); :ok
        def log_error_event(event, context, state), do: send(self(), {:log, :error, event, context}); :ok
      end

      # In your test setup:
      state = %{logging_handler: MyTest.LoggingHandler, ...}

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
  """

  @typedoc "Handler state"
  @type state :: map()

  @typedoc "Event type for connection, message, or error events."
  @type event :: atom() | String.t() | map()

  @typedoc "Context information about the event (e.g., connection details, message payload, error info)."
  @type context :: map()

  @typedoc "Log level (:debug, :info, :warn, :error)."
  @type log_level :: :debug | :info | :warn | :error

  @typedoc "Log format (:plain, :json, or custom atom)."
  @type log_format :: :plain | :json | atom()

  @doc """
  Log a connection lifecycle event (e.g., connect, disconnect, reconnect).
  Returns:
    - `:ok`
  """
  @callback log_connection_event(event, context, state) :: :ok

  @doc """
  Log a message event (send/receive).
  Returns:
    - `:ok`
  """
  @callback log_message_event(event, context, state) :: :ok

  @doc """
  Log an error event with context.
  Returns:
    - `:ok`
  """
  @callback log_error_event(event, context, state) :: :ok
end
