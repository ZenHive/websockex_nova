defmodule WebsockexNova.ClientConn do
  @moduledoc """
  Struct representing a client connection, including the process pid and WebSocket stream_ref.
  """
  defstruct [:pid, :stream_ref]

  @type t :: %__MODULE__{
          pid: pid(),
          stream_ref: reference() | nil
        }
end
