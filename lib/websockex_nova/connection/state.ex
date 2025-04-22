defmodule WebsockexNova.Connection.State do
  @moduledoc """
  State struct for WebsockexNova.Connection GenServer.
  Encapsulates all data required for robust Gun/WebSocket lifecycle management,
  buffering, request/response correlation, and handler module integration.
  """

  @enforce_keys [
    :adapter,
    :adapter_state,
    :connection_handler,
    :message_handler,
    :subscription_handler,
    :auth_handler,
    :error_handler,
    :rate_limit_handler,
    :logging_handler,
    :metrics_collector,
    :wrapper_pid,
    :transport_mod,
    :transport_state
  ]
  defstruct [
    :adapter,
    :adapter_state,
    :wrapper_pid,
    :ws_stream_ref,
    # :connecting | :connected | :disconnected | :reconnecting | :closed
    :status,
    :connection_handler,
    :message_handler,
    :subscription_handler,
    :auth_handler,
    :error_handler,
    :rate_limit_handler,
    :logging_handler,
    :metrics_collector,
    :reconnect_attempts,
    # for backoff strategy (can be nil or a struct)
    :backoff_state,
    :last_error,
    # merged config/options
    :config,
    :transport_mod,
    :transport_state,
    # [frame]
    frame_buffer: [],
    # [{frame, id, from}]
    request_buffer: [],
    # %{id => from}
    pending_requests: %{},
    # %{id => timer_ref}
    pending_timeouts: %{}
  ]
end
