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
    * `:adapter` - Adapter module implementing various behaviors
    * `:adapter_state` - State maintained by the adapter
    * `:callback_pids` - List of PIDs registered to receive event notifications
    * `:connection_info` - Connection information
    * `:auth_status` - Authentication status
    * `:access_token` - Access token for authentication
    * `:credentials` - Credentials for authentication
    * `:subscriptions` - Set of subscribed topics
    * `:subscription_timeout` - Subscription timeout
    * `:reconnect_attempts` - Number of reconnection attempts
    * `:last_error` - Last error encountered
    * `:rate_limit` - Rate limit configuration
    * `:logging` - Logging configuration
    * `:metrics` - Metrics configuration
    * `:extras` - Extensible/optional state
    * `:auth_expires_at` - Authentication expiration timestamp
    * `:auth_refresh_threshold` - Authentication refresh threshold
    * `:auth_error` - Authentication error
  """

  @typedoc "WebSocket transport module"
  @type transport :: module()

  @typedoc "WebSocket stream reference"
  @type stream_ref :: reference() | any()

  @typedoc "Adapter module implementing behaviors"
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
          auth_status: atom(),
          access_token: String.t() | nil,
          credentials: map() | nil,
          subscriptions: map(),
          subscription_timeout: integer() | nil,
          reconnect_attempts: non_neg_integer(),
          last_error: any(),
          auth_expires_at: integer() | nil,
          auth_refresh_threshold: integer() | nil,
          auth_error: any() | nil,
          # Handler/feature-specific state
          rate_limit: map(),
          logging: map(),
          metrics: map(),
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
    auth_status: :unauthenticated,
    access_token: nil,
    credentials: nil,
    subscriptions: %{},
    subscription_timeout: nil,
    reconnect_attempts: 0,
    last_error: nil,
    auth_expires_at: nil,
    auth_refresh_threshold: nil,
    auth_error: nil,
    rate_limit: %{},
    logging: %{},
    metrics: %{},
    adapter_state: %{},
    extras: %{}
  ]
end
