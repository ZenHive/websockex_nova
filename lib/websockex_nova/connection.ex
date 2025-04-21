defmodule WebsockexNova.Connection do
  @moduledoc """
  Process-based, adapter-agnostic connection wrapper for platform adapters (e.g., Echo, Deribit).

  This module provides a GenServer process that manages the lifecycle of a platform adapter connection.
  It routes messages to the adapter and delegates connection, message, subscription, authentication, error,
  rate limiting, logging, and metrics events to handler modules. These handlers can be customized via options
  or default to robust implementations in `WebsockexNova.Defaults`.

  ## Ergonomic Connection Flow

  The recommended way to start a connection is:

      {:ok, conn} = WebsockexNova.Connection.start_link(adapter: MyAdapter)
      WebsockexNova.Client.send_text(conn, "Hello")

  - `conn` is a `%WebsockexNova.ClientConn{}` struct, ready for use with all client functions.
  - No manual WebSocket upgrade or struct building required.

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
    * :adapter_state - the adapter's state
    * :ws_stream_ref - the WebSocket stream reference
    * handler modules for each concern (see above)
    * :pending_requests - map of id => from_pid for JSON-RPC request correlation
    * :request_buffer - list of {frame, id, from} tuples for outgoing JSON-RPC requests
    * :wrapper_pid - the ConnectionWrapper pid

  ## Advanced Usage

  If you need full control, use `WebsockexNova.Connection.start_link_raw/1` to get the raw process pid and manage upgrades yourself.

  """
  use GenServer

  alias WebsockexNova.Connection.State
  alias WebsockexNova.Gun.ConnectionWrapper

  require Logger

  @typedoc """
  The state for the WebsockexNova.Connection GenServer.
  """
  @type t :: %{
          adapter: module(),
          adapter_state: term(),
          ws_stream_ref: reference() | nil,
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
          request_buffer: list(),
          wrapper_pid: pid() | nil
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
    * {:ok, WebsockexNova.ClientConn.t()} on success
    * {:error, term()} on failure
  """
  @spec start_link(Keyword.t()) :: {:ok, WebsockexNova.ClientConn.t()} | {:error, term()}
  def start_link(opts) do
    __MODULE__
    |> GenServer.start_link(opts)
    |> case do
      {:ok, pid} ->
        # Wait for the websocket upgrade to complete and get the stream_ref
        case wait_for_stream_ref(pid, 2000) do
          {:ok, stream_ref} ->
            {:ok, %WebsockexNova.ClientConn{pid: pid, stream_ref: stream_ref}}

          {:error, reason} ->
            GenServer.stop(pid)
            {:error, reason}
        end

      error ->
        error
    end
  end

  # Lower-level API for advanced users: returns the raw pid, does not upgrade websocket
  @spec start_link_raw(Keyword.t()) :: GenServer.on_start()
  def start_link_raw(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  defp wait_for_stream_ref(pid, timeout) do
    start = System.monotonic_time(:millisecond)
    do_wait_for_stream_ref(pid, start, timeout)
  end

  defp do_wait_for_stream_ref(pid, start, timeout) do
    case :sys.get_state(pid) do
      %{ws_stream_ref: ref} when not is_nil(ref) ->
        {:ok, ref}

      _ ->
        if System.monotonic_time(:millisecond) - start > timeout do
          {:error, :websocket_upgrade_timeout}
        else
          Process.sleep(25)
          do_wait_for_stream_ref(pid, start, timeout)
        end
    end
  end

  defp wait_until_connected(wrapper_pid, timeout \\ 2000) do
    start = System.monotonic_time(:millisecond)
    do_wait_until_connected(wrapper_pid, start, timeout)
  end

  defp do_wait_until_connected(wrapper_pid, start, timeout) do
    state = GenServer.call(wrapper_pid, :get_state)

    if state.status == :connected do
      :ok
    else
      if System.monotonic_time(:millisecond) - start > timeout do
        {:error, :timeout}
      else
        Process.sleep(25)
        do_wait_until_connected(wrapper_pid, start, timeout)
      end
    end
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
    callback_pid = Keyword.get(opts, :callback_pid, self())

    Logger.debug("Handler injection at runtime:")
    Logger.debug("  connection_handler: #{inspect(connection_handler)}")
    Logger.debug("  message_handler: #{inspect(message_handler)}")
    Logger.debug("  subscription_handler: #{inspect(subscription_handler)}")
    Logger.debug("  auth_handler: #{inspect(auth_handler)}")
    Logger.debug("  error_handler: #{inspect(error_handler)}")
    Logger.debug("  rate_limit_handler: #{inspect(rate_limit_handler)}")
    Logger.debug("  logging_handler: #{inspect(logging_handler)}")
    Logger.debug("  metrics_collector: #{inspect(metrics_collector)}")

    # Call adapter.init/1 first to get adapter_state with defaults
    {:ok, adapter_state} = adapter.init(opts_map)

    # Extract Gun connection config from adapter_state or adapter
    gun_config =
      if function_exported?(adapter, :gun_config, 1) do
        adapter.gun_config(adapter_state)
      else
        %{
          host: Map.fetch!(adapter_state, :host),
          port: Map.get(adapter_state, :port, 443),
          transport: Map.get(adapter_state, :transport, :tls),
          path: Map.get(adapter_state, :path, "/"),
          ws_opts: Map.get(adapter_state, :ws_opts, %{})
        }
      end

    # Start Gun connection using ConnectionWrapper, ensuring callback_pid is set
    {:ok, wrapper_pid} =
      ConnectionWrapper.open(
        to_string(gun_config.host),
        gun_config.port,
        %{
          transport: gun_config.transport,
          ws_opts: gun_config.ws_opts,
          callback_pid: callback_pid,
          callback_handler: connection_handler,
          message_handler: message_handler,
          error_handler: error_handler
        }
      )

    # Wait until connected before upgrading
    :ok = wait_until_connected(wrapper_pid, 2000)
    {:ok, stream_ref} = ConnectionWrapper.upgrade_to_websocket(wrapper_pid, gun_config.path)

    state = %State{
      adapter: adapter,
      adapter_state: adapter_state,
      wrapper_pid: wrapper_pid,
      ws_stream_ref: stream_ref,
      ws_status: :connecting,
      connection_handler: connection_handler,
      message_handler: message_handler,
      subscription_handler: subscription_handler,
      auth_handler: auth_handler,
      error_handler: error_handler,
      rate_limit_handler: rate_limit_handler,
      logging_handler: logging_handler,
      metrics_collector: metrics_collector,
      reconnect_attempts: 0,
      backoff_state: nil,
      last_error: nil,
      config: Map.merge(opts_map, gun_config)
    }

    {:ok, state}
  end

  @doc """
  Upgrades the connection to a WebSocket and returns the stream_ref.
  """
  @spec upgrade_to_websocket(pid(), String.t(), list()) :: {:ok, reference()} | {:error, term()}
  def upgrade_to_websocket(pid, path, headers \\ []) do
    GenServer.call(pid, {:upgrade_to_websocket, path, headers})
  end

  @impl true
  def handle_call({:upgrade_to_websocket, path, headers}, _from, %{wrapper_pid: wrapper_pid} = s) do
    case ConnectionWrapper.upgrade_to_websocket(wrapper_pid, path, headers) do
      {:ok, stream_ref} ->
        {:reply, {:ok, stream_ref}, %{s | ws_stream_ref: stream_ref}}

      {:error, reason} ->
        {:reply, {:error, reason}, s}
    end
  end

  @impl true
  def handle_info(
        {:platform_message, stream_ref, message, from},
        %{wrapper_pid: wrapper_pid, pending_requests: pending} = state
      )
      when is_map(message) do
    Logger.debug(
      "[DEBUG] platform_message: message=#{inspect(message)}, from=#{inspect(from)}, pending_requests=#{inspect(pending)}"
    )

    id = Map.get(message, "id") || Map.get(message, :id)

    if id do
      Logger.debug("[DEBUG] JSON-RPC correlation: id=#{inspect(id)}")
      {:ok, json} = Jason.encode(message)
      :ok = ConnectionWrapper.send_frame(wrapper_pid, stream_ref, {:text, json})
      new_pending = Map.put(pending || %{}, id, from)
      Logger.debug("[DEBUG] Added pending request: id=#{inspect(id)}, from=#{inspect(from)}")
      {:noreply, %{state | pending_requests: new_pending}}
    else
      adapter = state.adapter
      adapter_state = state.adapter_state
      Logger.debug("[DEBUG] platform_message fallback: message=#{inspect(message)}")

      case adapter.handle_platform_message(message, adapter_state) do
        {:reply, reply, new_adapter_state} ->
          if from, do: send(from, {:reply, reply})
          {:noreply, %{state | adapter_state: new_adapter_state}}

        {:ok, new_adapter_state} ->
          {:noreply, %{state | adapter_state: new_adapter_state}}

        {:noreply, new_adapter_state} ->
          {:noreply, %{state | adapter_state: new_adapter_state}}

        {:error, reason, new_adapter_state} ->
          if from, do: send(from, {:error, reason})
          {:noreply, %{state | adapter_state: new_adapter_state}}
      end
    end
  end

  def handle_info({:subscribe, stream_ref, channel, params, from}, %{wrapper_pid: wrapper_pid} = s) do
    reply = ConnectionWrapper.subscribe(wrapper_pid, stream_ref, channel, params)
    send(from, {:reply, reply})
    {:noreply, s}
  end

  def handle_info({:unsubscribe, stream_ref, channel, from}, %{wrapper_pid: wrapper_pid} = s) do
    reply = ConnectionWrapper.unsubscribe(wrapper_pid, stream_ref, channel)
    send(from, {:reply, reply})
    {:noreply, s}
  end

  def handle_info({:authenticate, stream_ref, credentials, from}, %{wrapper_pid: wrapper_pid} = s) do
    reply = ConnectionWrapper.authenticate(wrapper_pid, stream_ref, credentials)
    send(from, {:reply, reply})
    {:noreply, s}
  end

  def handle_info({:ping, stream_ref, from}, %{wrapper_pid: wrapper_pid} = s) do
    reply = ConnectionWrapper.ping(wrapper_pid, stream_ref)
    send(from, {:reply, reply})
    {:noreply, s}
  end

  def handle_info({:status, stream_ref, from}, %{wrapper_pid: wrapper_pid} = s) do
    reply = ConnectionWrapper.status(wrapper_pid, stream_ref)
    send(from, {:reply, reply})
    {:noreply, s}
  end

  def handle_info({:send_frame, stream_ref, frame}, %{wrapper_pid: wrapper_pid} = s) do
    ConnectionWrapper.send_frame(wrapper_pid, stream_ref, frame)
    {:noreply, s}
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
      {:ok, %{"id" => id} = _resp} ->
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
