defmodule WebsockexNova.ClientConn do
  @moduledoc """
  Represents a connection to a WebSocket server using WebsockexNova.

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
  """

  @typedoc "WebSocket transport module"
  @type transport :: module()

  @typedoc "WebSocket stream reference"
  @type stream_ref :: reference() | any()

  @typedoc "Adapter module implementing behaviors"
  @type adapter :: module()

  @typedoc "Adapter state"
  @type adapter_state :: any()

  @typedoc "Client connection structure"
  @type t :: %__MODULE__{
          transport: transport(),
          transport_pid: pid(),
          stream_ref: stream_ref(),
          adapter: adapter(),
          adapter_state: adapter_state(),
          callback_pids: list(pid()),
          connection_info: map()
        }

  defstruct [
    :transport,
    :transport_pid,
    :stream_ref,
    :adapter,
    :adapter_state,
    callback_pids: [],
    connection_info: %{}
  ]
end
