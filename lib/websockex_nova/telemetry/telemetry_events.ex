defmodule WebsockexNova.Telemetry.TelemetryEvents do
  @moduledoc """
  Central registry and documentation for all telemetry events emitted by WebsockexNova.

  ## Event Names and Payloads

  ### Connection Events

    * `[:websockex_nova, :connection, :open]`
      - measurements: `%{duration: integer()}` (ms, optional)
      - metadata: `%{connection_id: term(), host: String.t(), port: integer()}`

    * `[:websockex_nova, :connection, :close]`
      - measurements: `%{duration: integer()}` (ms, optional)
      - metadata: `%{connection_id: term(), host: String.t(), port: integer(), reason: term()}`

    * `[:websockex_nova, :connection, :websocket_upgrade]`
      - measurements: `%{duration: integer()}` (ms, optional)
      - metadata: `%{connection_id: term(), stream_ref: reference(), headers: list()}`

  ### Message Events

    * `[:websockex_nova, :message, :sent]`
      - measurements: `%{size: integer(), latency: integer()}` (bytes, ms)
      - metadata: `%{connection_id: term(), stream_ref: reference(), frame_type: atom()}`

    * `[:websockex_nova, :message, :received]`
      - measurements: `%{size: integer(), latency: integer()}` (bytes, ms)
      - metadata: `%{connection_id: term(), stream_ref: reference(), frame_type: atom()}`

  ### Error Events

    * `[:websockex_nova, :error, :occurred]`
      - measurements: `%{}`
      - metadata: `%{connection_id: term(), stream_ref: reference() | nil, reason: term(), context: map()}`

  ## Usage

  Use these event names and payloads when emitting or subscribing to telemetry events.
  """

  @connection_open [:websockex_nova, :connection, :open]
  @connection_close [:websockex_nova, :connection, :close]
  @connection_websocket_upgrade [:websockex_nova, :connection, :websocket_upgrade]
  @message_sent [:websockex_nova, :message, :sent]
  @message_received [:websockex_nova, :message, :received]
  @error_occurred [:websockex_nova, :error, :occurred]
  @ownership_transfer [:websockex_nova, :connection, :ownership_transfer, :received]
  @subscription_restored [:websockex_nova, :subscription, :restored]
  @subscription_restoration_failed [:websockex_nova, :subscription, :restoration_failed]

  def connection_open, do: @connection_open
  def connection_close, do: @connection_close
  def connection_websocket_upgrade, do: @connection_websocket_upgrade
  def message_sent, do: @message_sent
  def message_received, do: @message_received
  def error_occurred, do: @error_occurred

  @doc """
  Event emitted when an ownership transfer is received from another process.

  ## Measurements

  Empty map (timing is not relevant for this event)

  ## Metadata

  * `:gun_pid` - The Gun process PID
  * `:host` - Hostname of the connection
  * `:port` - Port number of the connection
  * `:stream_count` - Number of active streams transferred
  """
  @spec ownership_transfer_received :: list(atom())
  def ownership_transfer_received, do: @ownership_transfer

  @doc """
  Event emitted when a subscription is successfully restored after reconnection.

  ## Measurements

  * `:duration` - Time taken to restore the subscription in milliseconds

  ## Metadata

  * `:connection_id` - The connection identifier
  * `:subscription_id` - The subscription identifier
  * `:channel` - The channel being subscribed to
  """
  @spec subscription_restored :: list(atom())
  def subscription_restored, do: @subscription_restored

  @doc """
  Event emitted when a subscription restoration fails after reconnection.

  ## Measurements

  * `:duration` - Time taken before failure in milliseconds

  ## Metadata

  * `:connection_id` - The connection identifier
  * `:subscription_id` - The subscription identifier
  * `:channel` - The channel that failed to subscribe
  * `:reason` - The failure reason
  """
  @spec subscription_restoration_failed :: list(atom())
  def subscription_restoration_failed, do: @subscription_restoration_failed
end
