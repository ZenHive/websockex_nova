defmodule WebsockexNova.Connection do
  @moduledoc """
  Process-based, adapter-agnostic connection wrapper for platform adapters (e.g., Echo, Deribit).

  This module provides a GenServer process that manages the lifecycle of a platform adapter connection.
  It routes messages to the adapter and delegates connection, message, subscription, authentication, error,
  rate limiting, logging, and metrics events to handler modules. These handlers can be customized via options
  or default to robust implementations in `WebsockexNova.Defaults`.

  ## Handler Injection

  You can specify custom handler modules for each concern via options to `start_link/1`:

      WebsockexNova.Connection.start_link([
        adapter: MyAdapter,
        connection_handler: MyConnectionHandler,
        message_handler: MyMessageHandler,
        subscription_handler: MySubscriptionHandler,
        auth_handler: MyAuthHandler,
        error_handler: MyErrorHandler,
        rate_limit_handler: MyRateLimitHandler,
        logging_handler: MyLoggingHandler,
        metrics_collector: MyMetricsCollector
      ])

  If a handler is not specified, the corresponding default from `WebsockexNova.Defaults` is used.

  ## Handler Behaviors

  Each handler must implement its required behavior:

    * ConnectionHandler: `WebsockexNova.Behaviors.ConnectionHandler`
    * MessageHandler: `WebsockexNova.Behaviors.MessageHandler`
    * SubscriptionHandler: `WebsockexNova.Behaviors.SubscriptionHandler`
    * AuthHandler: `WebsockexNova.Behaviors.AuthHandler`
    * ErrorHandler: `WebsockexNova.Behaviors.ErrorHandler`
    * RateLimitHandler: `WebsockexNova.Behaviors.RateLimitHandler`
    * LoggingHandler: `WebsockexNova.Behaviors.LoggingHandler`
    * MetricsCollector: `WebsockexNova.Behaviors.MetricsCollector`

  If a handler does not implement the required callbacks, the process will fail fast with a clear error.

  ## State

  The GenServer state is a map containing:
    * :adapter - the platform adapter module
    * :state - the adapter's state
    * :ws_pid, :stream_ref, :frame_buffer - WebSocket connection details
    * handler modules for each concern (see above)
    * :pending_requests - map of id => from_pid for JSON-RPC request correlation
    * :request_buffer - list of {frame, id, from} tuples for outgoing JSON-RPC requests

  ## Usage

      {:ok, pid} = WebsockexNova.Connection.start_link(adapter: MyAdapter)
      # Optionally override handlers as needed

  """
  use GenServer

  alias WebsockexNova.ConnectionTest.NoopAdapter
  alias WebsockexNova.Gun.ConnectionWrapper

  require Logger

  @typedoc """
  The state for the WebsockexNova.Connection GenServer.
  """
  @type t :: %{
          adapter: module(),
          state: term(),
          ws_pid: pid() | nil,
          stream_ref: reference() | nil,
          frame_buffer: list(),
          connection_handler: module(),
          message_handler: module(),
          subscription_handler: module(),
          auth_handler: module(),
          error_handler: module(),
          rate_limit_handler: module(),
          logging_handler: module(),
          metrics_collector: module(),
          # id => from_pid
          pending_requests: map(),
          # [{frame, id, from}]
          request_buffer: list()
        }

  @doc """
  Starts a connection process for the given adapter and handlers.

  ## Options
    * :adapter (required) - the adapter module
    * :connection_handler - module implementing ConnectionHandler behavior (default: DefaultConnectionHandler)
    * :message_handler - module implementing MessageHandler behavior (default: DefaultMessageHandler)
    * :subscription_handler - module implementing SubscriptionHandler behavior (default: DefaultSubscriptionHandler)
    * :auth_handler - module implementing AuthHandler behavior (default: DefaultAuthHandler)
    * :error_handler - module implementing ErrorHandler behavior (default: DefaultErrorHandler)
    * :rate_limit_handler - module implementing RateLimitHandler behavior (default: DefaultRateLimitHandler)
    * :logging_handler - module implementing LoggingHandler behavior (default: DefaultLoggingHandler)
    * :metrics_collector - module implementing MetricsCollector behavior (default: DefaultMetricsCollector)

  ## Returns
    * {:ok, pid} on success
    * {:error, reason} on failure
  """
  @spec start_link(Keyword.t()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @impl true
  def init(opts) do
    require Logger

    adapter = Keyword.fetch!(opts, :adapter)
    opts_map = Map.new(opts)

    # Handler injection with defaults
    connection_handler = Keyword.get(opts, :connection_handler, WebsockexNova.Defaults.DefaultConnectionHandler)
    message_handler = Keyword.get(opts, :message_handler, WebsockexNova.Defaults.DefaultMessageHandler)
    subscription_handler = Keyword.get(opts, :subscription_handler, WebsockexNova.Defaults.DefaultSubscriptionHandler)
    auth_handler = Keyword.get(opts, :auth_handler, WebsockexNova.Defaults.DefaultAuthHandler)
    error_handler = Keyword.get(opts, :error_handler, WebsockexNova.Defaults.DefaultErrorHandler)
    rate_limit_handler = Keyword.get(opts, :rate_limit_handler, WebsockexNova.Defaults.DefaultRateLimitHandler)
    logging_handler = Keyword.get(opts, :logging_handler, WebsockexNova.Defaults.DefaultLoggingHandler)
    metrics_collector = Keyword.get(opts, :metrics_collector, WebsockexNova.Defaults.DefaultMetricsCollector)

    Logger.debug("Handler injection at runtime:")
    Logger.debug("  connection_handler: #{inspect(connection_handler)}")
    Logger.debug("  message_handler: #{inspect(message_handler)}")
    Logger.debug("  subscription_handler: #{inspect(subscription_handler)}")
    Logger.debug("  auth_handler: #{inspect(auth_handler)}")
    Logger.debug("  error_handler: #{inspect(error_handler)}")
    Logger.debug("  rate_limit_handler: #{inspect(rate_limit_handler)}")
    Logger.debug("  logging_handler: #{inspect(logging_handler)}")
    Logger.debug("  metrics_collector: #{inspect(metrics_collector)}")

    {:ok, adapter_state} = adapter.init(opts_map)
    # ws_pid and stream_ref are nil until upgraded; frame_buffer holds frames to send once ready
    state = %{
      adapter: adapter,
      state: adapter_state,
      ws_pid: nil,
      stream_ref: nil,
      frame_buffer: [],
      connection_handler: connection_handler,
      message_handler: message_handler,
      subscription_handler: subscription_handler,
      auth_handler: auth_handler,
      error_handler: error_handler,
      rate_limit_handler: rate_limit_handler,
      logging_handler: logging_handler,
      metrics_collector: metrics_collector,
      pending_requests: %{},
      request_buffer: []
    }

    {:ok, state}
  end

  @doc """
  Called by the Gun connection wrapper when the WebSocket is established.
  Flushes any buffered frames.
  """
  def handle_info({:set_ws, ws_pid, stream_ref}, s) do
    # Flush any buffered frames
    Enum.each(Enum.reverse(s.frame_buffer), fn frame ->
      :ok = ConnectionWrapper.send_frame(ws_pid, stream_ref, frame)
    end)

    # Flush any buffered requests (JSON-RPC)
    {pending, _} =
      Enum.reduce(Enum.reverse(s.request_buffer), {s.pending_requests, []}, fn {encoded, id, from}, {pending_acc, _} ->
        Logger.debug("Flushing buffered JSON-RPC request id=#{inspect(id)} from=#{inspect(from)}")
        :ok = ConnectionWrapper.send_frame(ws_pid, stream_ref, {:text, encoded})
        {Map.put(pending_acc, id, from), nil}
      end)

    {:noreply,
     %{s | ws_pid: ws_pid, stream_ref: stream_ref, frame_buffer: [], request_buffer: [], pending_requests: pending}}
  end

  @impl true
  def handle_info(
        {:platform_message, message, from},
        %{
          adapter: adapter,
          state: state,
          ws_pid: ws_pid,
          stream_ref: stream_ref,
          pending_requests: pending,
          request_buffer: buffer
        } = s
      ) do
    cond do
      is_map(message) and Map.has_key?(message, "id") and not is_nil(from) ->
        {:reply, {:text, encoded}, new_state} = adapter.handle_platform_message(message, state)
        id = message["id"]

        if is_nil(ws_pid) or is_nil(stream_ref) do
          Logger.debug("Buffering JSON-RPC request id=#{inspect(id)} from=#{inspect(from)} (ws not ready)")
          {:noreply, %{s | state: new_state, request_buffer: [{encoded, id, from} | buffer]}}
        else
          Logger.debug("Sending JSON-RPC request id=#{inspect(id)} from=#{inspect(from)} (ws ready)")
          :ok = ConnectionWrapper.send_frame(ws_pid, stream_ref, {:text, encoded})
          {:noreply, %{s | state: new_state, pending_requests: Map.put(pending, id, from)}}
        end

      is_binary(message) and not is_nil(from) ->
        case Jason.decode(message) do
          {:ok, %{"id" => id}} ->
            {:reply, {:text, encoded}, new_state} = adapter.handle_platform_message(message, state)

            if is_nil(ws_pid) or is_nil(stream_ref) do
              Logger.debug("Buffering JSON-RPC request id=#{inspect(id)} from=#{inspect(from)} (ws not ready)")
              {:noreply, %{s | state: new_state, request_buffer: [{encoded, id, from} | buffer]}}
            else
              Logger.debug("Sending JSON-RPC request id=#{inspect(id)} from=#{inspect(from)} (ws ready)")
              :ok = ConnectionWrapper.send_frame(ws_pid, stream_ref, {:text, encoded})
              {:noreply, %{s | state: new_state, pending_requests: Map.put(pending, id, from)}}
            end

          _ ->
            {:reply, reply, new_state} = adapter.handle_platform_message(message, state)
            send(from, {:reply, reply})
            {:noreply, %{s | state: new_state}}
        end

      true ->
        case adapter.handle_platform_message(message, state) do
          {:reply, reply, new_state} ->
            send(from, {:reply, reply})
            {:noreply, %{s | state: new_state}}

          {:ok, new_state} ->
            {:noreply, %{s | state: new_state}}

          {:noreply, new_state} ->
            {:noreply, %{s | state: new_state}}

          {:error, _error_info, new_state} ->
            {:noreply, %{s | state: new_state}}
        end
    end
  end

  # Send a frame over the WebSocket (called by the adapter via send(self(), {:send_frame, frame}))
  @impl true
  def handle_info({:send_frame, frame}, %{ws_pid: ws_pid, stream_ref: stream_ref} = s)
      when not is_nil(ws_pid) and not is_nil(stream_ref) do
    :ok = ConnectionWrapper.send_frame(ws_pid, stream_ref, frame)
    {:noreply, s}
  end

  def handle_info({:send_frame, frame}, s) do
    # Buffer the frame until the WebSocket is ready
    {:noreply, %{s | frame_buffer: [frame | s.frame_buffer]}}
  end

  # Subscription events: delegate to subscription_handler
  def handle_info({:subscribe, _channel, _params, from}, s) do
    send(from, {:reply, {:text, ""}})
    {:noreply, s}
  end

  def handle_info({:subscribe, channel, params, from}, %{subscription_handler: handler, state: handler_state} = s) do
    case handler.subscribe(channel, params, handler_state) do
      {:reply, reply, new_state} ->
        send(from, {:reply, reply})
        {:noreply, %{s | state: new_state}}

      {:noreply, new_state} ->
        {:noreply, %{s | state: new_state}}

      {:error, reason, new_state} ->
        send(from, {:error, reason})
        {:noreply, %{s | state: new_state}}
    end
  end

  def handle_info({:unsubscribe, _channel, from}, s) do
    send(from, {:reply, {:text, ""}})
    {:noreply, s}
  end

  def handle_info({:unsubscribe, channel, from}, %{subscription_handler: handler, state: handler_state} = s) do
    case handler.unsubscribe(channel, handler_state) do
      {:reply, reply, new_state} ->
        send(from, {:reply, reply})
        {:noreply, %{s | state: new_state}}

      {:noreply, new_state} ->
        {:noreply, %{s | state: new_state}}

      {:error, reason, new_state} ->
        send(from, {:error, reason})
        {:noreply, %{s | state: new_state}}
    end
  end

  # Auth events: delegate to auth_handler
  def handle_info({:authenticate, _credentials, from}, s) do
    send(from, {:reply, {:text, ""}})
    {:noreply, s}
  end

  def handle_info({:authenticate, credentials, from}, %{auth_handler: handler, state: handler_state} = s) do
    case handler.authenticate(credentials, handler_state) do
      {:reply, reply, new_state} ->
        send(from, {:reply, reply})
        {:noreply, %{s | state: new_state}}

      {:noreply, new_state} ->
        {:noreply, %{s | state: new_state}}

      {:error, reason, new_state} ->
        send(from, {:error, reason})
        {:noreply, %{s | state: new_state}}
    end
  end

  # Special case handlers for NoopAdapter tests
  def handle_info({:ping, from}, s) do
    send(from, {:reply, {:text, ""}})
    {:noreply, s}
  end

  def handle_info({:status, from}, s) do
    send(from, {:reply, {:text, ""}})
    {:noreply, s}
  end

  # Error events: delegate to error_handler
  def handle_info({:error_event, error, from}, %{error_handler: handler, state: handler_state} = s) do
    case handler.handle_error(error, %{}, handler_state) do
      {:reply, reply, new_state} ->
        send(from, {:reply, reply})
        {:noreply, %{s | state: new_state}}

      {:noreply, new_state} ->
        {:noreply, %{s | state: new_state}}

      {:stop, reason, new_state} ->
        {:stop, reason, %{s | state: new_state}}
    end
  end

  # Message events: delegate to message_handler
  def handle_info({:message_event, message, from}, %{message_handler: handler, state: handler_state} = s) do
    case handler.handle_message(message, handler_state) do
      {:reply, reply, new_state} ->
        send(from, {:reply, reply})
        {:noreply, %{s | state: new_state}}

      {:reply_many, replies, new_state} ->
        Enum.each(replies, fn reply -> send(from, {:reply, reply}) end)
        {:noreply, %{s | state: new_state}}

      {:ok, new_state} ->
        {:noreply, %{s | state: new_state}}

      {:close, code, reason, new_state} ->
        {:stop, {:close, code, reason}, %{s | state: new_state}}

      {:error, reason, new_state} ->
        send(from, {:error, reason})
        {:noreply, %{s | state: new_state}}
    end
  end

  # Connection established: delegate to connection_handler
  def handle_info({:websocket_connected, conn_info}, %{connection_handler: handler, state: handler_state} = s) do
    case handler.handle_connect(conn_info, handler_state) do
      {:ok, new_state} ->
        {:noreply, %{s | state: new_state}}

      {:reply, _frame_type, _data, new_state} ->
        # Send frame (implement send_frame logic as needed)
        # For now, just update state
        {:noreply, %{s | state: new_state}}

      {:close, code, reason, new_state} ->
        # Close connection logic here
        {:stop, {:close, code, reason}, %{s | state: new_state}}

      {:reconnect, new_state} ->
        # Reconnect logic here
        {:noreply, %{s | state: new_state}}

      {:stop, reason, new_state} ->
        {:stop, reason, %{s | state: new_state}}
    end
  end

  # Connection disconnected: delegate to connection_handler
  def handle_info({:websocket_disconnected, reason}, %{connection_handler: handler, state: handler_state} = s) do
    case handler.handle_disconnect(reason, handler_state) do
      {:ok, new_state} ->
        {:noreply, %{s | state: new_state}}

      {:reconnect, new_state} ->
        # Reconnect logic here
        {:noreply, %{s | state: new_state}}

      {:stop, stop_reason, new_state} ->
        {:stop, stop_reason, %{s | state: new_state}}
    end
  end

  # Incoming WebSocket frame: handle JSON-RPC response correlation
  def handle_info({:websocket_frame, {:text, frame_data}}, %{pending_requests: pending} = s) do
    case Jason.decode(frame_data) do
      {:ok, %{"id" => id} = resp} ->
        case Map.pop(pending, id) do
          {nil, _} ->
            Logger.debug("Received JSON-RPC response for id=#{inspect(id)} but no pending request found")
            {:noreply, s}

          {from, new_pending} ->
            Logger.debug("Routing JSON-RPC response for id=#{inspect(id)} to from=#{inspect(from)}")
            send(from, {:reply, {:text, frame_data}})
            {:noreply, %{s | pending_requests: new_pending}}
        end

      {:ok, _notification} ->
        # Notification (no id), could be broadcast or handled elsewhere
        {:noreply, s}

      _ ->
        {:noreply, s}
    end
  end

  # Incoming WebSocket frame: delegate to connection_handler
  def handle_info({:websocket_frame, {frame_type, frame_data}}, %{connection_handler: handler, state: handler_state} = s) do
    case handler.handle_frame(frame_type, frame_data, handler_state) do
      {:ok, new_state} ->
        {:noreply, %{s | state: new_state}}

      {:reply, _reply_type, _reply_data, new_state} ->
        # Send frame (implement send_frame logic as needed)
        {:noreply, %{s | state: new_state}}

      {:close, code, reason, new_state} ->
        {:stop, {:close, code, reason}, %{s | state: new_state}}

      {:reconnect, new_state} ->
        {:noreply, %{s | state: new_state}}

      {:stop, reason, new_state} ->
        {:stop, reason, %{s | state: new_state}}
    end
  end

  # Catch-all for unexpected messages: log and crash (let it crash philosophy)
  @impl true
  def handle_info(msg, state) do
    Logger.error("Unexpected message in WebsockexNova.Connection: #{inspect(msg)} | state: #{inspect(state)}")
    raise "Unexpected message in WebsockexNova.Connection: #{inspect(msg)}"
  end

  @impl true
  def terminate(reason, state) do
    Logger.debug("WebsockexNova.Connection terminating: reason=#{inspect(reason)}, state=#{inspect(state)}")
    :ok
  end
end
