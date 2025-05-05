defmodule WebsockexNova.ClientConn do
  @moduledoc """
  Canonical state for a WebSocket client connection.
  All core application/session state is explicit and top-level.
  Handler/feature-specific state is namespaced in maps (e.g., :rate_limit, :logging, :metrics).
  Adapter-specific state is kept in :adapter_state. :extras is for extensibility.

  This struct contains all the information needed to interact with a WebSocket connection,
  including the transport layer implementation, transport process, stream reference,
  adapter module, and adapter state.

  ## Fields

    * `:transport` - The transport module implementing `WebsockexNova.Transport`
    * `:transport_pid` - PID of the transport process
    * `:stream_ref` - WebSocket stream reference
    * `:adapter` - Adapter module implementing various behaviours
    * `:adapter_state` - State maintained by the adapter (stores auth status, auth tokens, credentials, subscriptions, etc.)
    * `:callback_pids` - List of PIDs registered to receive event notifications
    * `:connection_info` - Connection information and initial configuration
    * `:rate_limit` - Rate limit configuration
    * `:logging` - Logging configuration
    * `:metrics` - Metrics configuration
    * `:reconnection` - Reconnection configuration map for error handler
    * `:connection_handler_settings` - State specific to the connection handler
    * `:auth_handler_settings` - State specific to the auth handler
    * `:subscription_handler_settings` - State specific to the subscription handler
    * `:error_handler_settings` - State specific to the error handler
    * `:message_handler_settings` - State specific to the message handler
    * `:extras` - Extensible/optional state
  """

  @typedoc "WebSocket transport module"
  @type transport :: module()

  @typedoc "WebSocket stream reference"
  @type stream_ref :: reference() | any()

  @typedoc "Adapter module implementing behaviours"
  @type adapter :: module()

  @typedoc "Client connection structure (canonical state)"
  @type t :: %__MODULE__{
          # Core connection/session state
          transport: transport(),
          transport_pid: pid(),
          stream_ref: stream_ref(),
          adapter: adapter(),
          callback_pids: MapSet.t(pid()),
          connection_info: map(),
          # Handler/feature-specific state
          rate_limit: map(),
          logging: map(),
          metrics: map(),
          reconnection: map(),
          connection_handler_settings: map(),
          auth_handler_settings: map(),
          subscription_handler_settings: map(),
          error_handler_settings: map(),
          message_handler_settings: map(),
          # Adapter-specific state
          adapter_state: map(),
          # Extensible/optional
          extras: map()
        }

  defstruct [
    :transport,
    :transport_pid,
    :stream_ref,
    :adapter,
    callback_pids: MapSet.new(),
    connection_info: %{},
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
  ]
end
