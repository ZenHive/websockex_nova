defmodule WebSockexNova.Gun.ConnectionState do
  @moduledoc """
  State structure for ConnectionWrapper.

  This module defines the state structure used by the ConnectionWrapper,
  providing better type safety and organization of state data.
  """

  alias WebSockexNova.Gun.ConnectionWrapper

  @typedoc "Connection state structure"
  @type t :: %__MODULE__{
          gun_pid: pid() | nil,
          host: String.t(),
          port: non_neg_integer(),
          status: ConnectionWrapper.status(),
          options: map(),
          callback_pid: pid() | nil,
          last_error: term() | nil,
          active_streams: %{reference() => atom()},
          reconnect_attempts: non_neg_integer(),
          handlers: map()
        }

  defstruct [
    :gun_pid,
    :host,
    :port,
    :status,
    :options,
    :callback_pid,
    :last_error,
    active_streams: %{},
    reconnect_attempts: 0,
    handlers: %{}
  ]

  @doc """
  Creates a new connection state.

  ## Parameters

  * `host` - The hostname to connect to
  * `port` - The port to connect to
  * `options` - Connection options

  ## Returns

  A new connection state struct
  """
  @spec new(String.t(), non_neg_integer(), map()) :: t()
  def new(host, port, options) do
    %__MODULE__{
      host: host,
      port: port,
      status: :initialized,
      options: options,
      callback_pid: Map.get(options, :callback_pid),
      active_streams: %{}
    }
  end

  @doc """
  Updates the connection status in the state.

  ## Parameters

  * `state` - Current connection state
  * `status` - New status to set

  ## Returns

  Updated connection state struct
  """
  @spec update_status(t(), ConnectionWrapper.status()) :: t()
  def update_status(state, status) do
    %{state | status: status}
  end

  @doc """
  Updates the Gun connection PID in the state.

  ## Parameters

  * `state` - Current connection state
  * `gun_pid` - The Gun connection process PID

  ## Returns

  Updated connection state struct
  """
  @spec update_gun_pid(t(), pid() | nil) :: t()
  def update_gun_pid(state, gun_pid) do
    %{state | gun_pid: gun_pid}
  end

  @doc """
  Records an error in the state.

  ## Parameters

  * `state` - Current connection state
  * `error` - Error to record

  ## Returns

  Updated connection state struct
  """
  @spec record_error(t(), term()) :: t()
  def record_error(state, error) do
    %{state | last_error: error}
  end

  @doc """
  Updates or adds a stream in the active streams map.

  ## Parameters

  * `state` - Current connection state
  * `stream_ref` - Stream reference
  * `status` - Stream status

  ## Returns

  Updated connection state struct
  """
  @spec update_stream(t(), reference(), atom()) :: t()
  def update_stream(state, stream_ref, status) do
    %{state | active_streams: Map.put(state.active_streams, stream_ref, status)}
  end

  @doc """
  Increments the reconnection attempt counter.

  ## Parameters

  * `state` - Current connection state

  ## Returns

  Updated connection state struct
  """
  @spec increment_reconnect_attempts(t()) :: t()
  def increment_reconnect_attempts(state) do
    %{state | reconnect_attempts: state.reconnect_attempts + 1}
  end

  @doc """
  Resets the reconnection attempt counter.

  ## Parameters

  * `state` - Current connection state

  ## Returns

  Updated connection state struct
  """
  @spec reset_reconnect_attempts(t()) :: t()
  def reset_reconnect_attempts(state) do
    %{state | reconnect_attempts: 0}
  end
end
