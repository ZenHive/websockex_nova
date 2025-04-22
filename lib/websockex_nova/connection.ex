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
    * :reconnect_attempts - number of reconnection attempts
    * :backoff_state - current backoff state
    * :last_error - last error encountered
    * :pending_timeouts - map of id => timer_ref for request timeouts (added for robust cleanup)

  ## Lifecycle and Event Flow

  1. On process start, the connection is established via ConnectionWrapper and upgraded to WebSocket.
  2. Outgoing requests are buffered until the WebSocket is ready, then flushed.
  3. All Gun/WebSocket events are handled and delegated to the appropriate handler modules.
  4. JSON-RPC requests are correlated with responses by id, and timeouts are tracked for cleanup.
  5. On disconnect or error, the process cleans up state, emits telemetry, and schedules reconnection using backoff.
  6. All major lifecycle events emit telemetry and logging for observability.
  7. Unrecoverable errors crash the process (let it crash philosophy).

  ## Handler Invocation

  All handler modules (ConnectionHandler, MessageHandler, etc.) are invoked at the appropriate lifecycle points. If a handler returns {:reconnect, new_state}, reconnection is scheduled. If {:stop, reason, new_state}, the process terminates.

  ## Advanced Usage

  If you need full control, use `WebsockexNova.Connection.start_link_raw/1` to get the raw process pid and manage upgrades yourself.

  """
  use GenServer

  alias WebsockexNova.Connection.State
  alias WebsockexNova.Gun.ConnectionManager
  alias WebsockexNova.Gun.ConnectionWrapper
  alias WebsockexNova.Helpers.StateHelpers
  alias WebsockexNova.Telemetry.TelemetryEvents

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
          wrapper_pid: pid() | nil,
          reconnect_attempts: non_neg_integer(),
          backoff_state: term(),
          last_error: term(),
          # id => timer_ref for request timeouts
          pending_timeouts: map()
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

  @doc """
  Starts a connection process in test mode (no real connection is made).

  This is intended for integration tests that need to control connection state manually.

  ## Options
    * :adapter (required) - the adapter module
    * All handler options as in `start_link/1`

  ## Returns
    * {:ok, WebsockexNova.ClientConn.t()} on success
    * {:error, term()} on failure
  """
  @spec start_link_test(Keyword.t()) :: {:ok, WebsockexNova.ClientConn.t()} | {:error, term()}
  def start_link_test(opts) do
    opts = Keyword.put(opts, :test_mode, true)

    __MODULE__
    |> GenServer.start_link(opts)
    |> case do
      {:ok, pid} ->
        {:ok, %WebsockexNova.ClientConn{pid: pid, stream_ref: nil}}

      error ->
        error
    end
  end

  defp wait_until_connected(wrapper_pid, timeout) do
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

    notification_pid = Keyword.get(opts, :callback_pid)
    callback_pid = self()

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

    if Keyword.get(opts, :test_mode, false) do
      # Test mode: do not connect, just build state with nil wrapper_pid and ws_stream_ref
      config = Map.put(opts_map, :notification_pid, notification_pid)
      timeout_ms = Keyword.get(opts, :request_timeout, 10_000)

      state = %State{
        adapter: adapter,
        adapter_state: adapter_state,
        wrapper_pid: nil,
        ws_stream_ref: nil,
        status: :disconnected,
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
        config: Map.put(config, :request_timeout, timeout_ms),
        pending_timeouts: %{}
      }

      {:ok, state}
    else
      # Normal connection flow
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

      # Start Gun connection using ConnectionWrapper, ensuring callback_pid is set to self()
      {:ok, wrapper_pid} =
        ConnectionWrapper.open(
          to_string(gun_config.host),
          gun_config.port,
          %{
            transport: gun_config.transport,
            ws_opts: gun_config.ws_opts,
            # always self()
            callback_pid: callback_pid,
            callback_handler: connection_handler,
            message_handler: message_handler,
            error_handler: error_handler
          }
        )

      # Wait until connected before upgrading
      :ok = wait_until_connected(wrapper_pid, 2000)
      {:ok, stream_ref} = ConnectionWrapper.upgrade_to_websocket(wrapper_pid, gun_config.path)

      # Store notification_pid in config for later use
      config = opts_map |> Map.merge(gun_config) |> Map.put(:notification_pid, notification_pid)

      timeout_ms = Keyword.get(opts, :request_timeout, 10_000)

      state = %State{
        adapter: adapter,
        adapter_state: adapter_state,
        wrapper_pid: wrapper_pid,
        ws_stream_ref: stream_ref,
        status: :connecting,
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
        config: Map.put(config, :request_timeout, timeout_ms),
        pending_timeouts: %{}
      }

      {:ok, state}
    end
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

  # Buffer outgoing requests if not ready
  def handle_call({:send_request, frame, id, from}, _from, state) do
    state = Map.put_new(state, :pending_timeouts, %{})

    if is_nil(state.ws_stream_ref) do
      # Buffer the request if the WebSocket is not ready
      new_state = StateHelpers.buffer_request(state, frame, id, from)
      {:reply, :buffered, new_state}
    else
      # Send the request immediately if the WebSocket is ready
      ConnectionWrapper.send_frame(state.wrapper_pid, state.ws_stream_ref, frame)
      # Track the pending request for JSON-RPC correlation and timeout
      new_pending = if id, do: Map.put(state.pending_requests, id, from), else: state.pending_requests
      timer_ref = if id, do: Process.send_after(self(), {:request_timeout, id}, 10_000)
      new_timeouts = if id, do: Map.put(state.pending_timeouts, id, timer_ref), else: state.pending_timeouts
      {:reply, :sent, %{state | pending_requests: new_pending, pending_timeouts: new_timeouts}}
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
      Logger.debug("[DEBUG] JSON-RPC correlation: id=#{inspect(id)} (from=#{inspect(from)})")
      {:ok, json} = Jason.encode(message)
      :ok = ConnectionWrapper.send_frame(wrapper_pid, stream_ref, {:text, json})
      new_pending = Map.put(pending || %{}, id, from)

      Logger.debug(
        "[DEBUG] Added pending request: id=#{inspect(id)}, from=#{inspect(from)}, new_pending_requests=#{inspect(new_pending)}"
      )

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

  def handle_info({:subscribe, channel, params, from}, state) do
    result = WebsockexNova.HandlerInvoker.invoke(:subscription_handler, :subscribe, [channel, params, state], state)

    case result do
      {:reply, reply, new_state} ->
        send(from, {:reply, reply})
        {:noreply, new_state}

      {:noreply, new_state} ->
        {:noreply, new_state}

      {:error, reason, new_state} ->
        send(from, {:error, reason})
        {:noreply, new_state}

      _ ->
        send(from, {:reply, {:text, ""}})
        {:noreply, state}
    end
  end

  def handle_info({:unsubscribe, channel, from}, state) do
    result = WebsockexNova.HandlerInvoker.invoke(:subscription_handler, :unsubscribe, [channel, state], state)

    case result do
      {:reply, reply, new_state} ->
        send(from, {:reply, reply})
        {:noreply, new_state}

      {:noreply, new_state} ->
        {:noreply, new_state}

      {:error, reason, new_state} ->
        send(from, {:error, reason})
        {:noreply, new_state}

      _ ->
        send(from, {:reply, {:text, ""}})
        {:noreply, state}
    end
  end

  def handle_info({:authenticate, credentials, from}, state) do
    result = WebsockexNova.HandlerInvoker.invoke(:auth_handler, :authenticate, [credentials, state], state)

    case result do
      {:reply, reply, new_state} ->
        send(from, {:reply, reply})
        {:noreply, new_state}

      {:noreply, new_state} ->
        {:noreply, new_state}

      {:error, reason, new_state} ->
        send(from, {:error, reason})
        {:noreply, new_state}

      _ ->
        send(from, {:reply, {:text, ""}})
        {:noreply, state}
    end
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
  def handle_info({:subscribe, channel, params, from}, state) do
    result = WebsockexNova.HandlerInvoker.invoke(:subscription_handler, :subscribe, [channel, params, state], state)

    case result do
      {:reply, reply, new_state} ->
        send(from, {:reply, reply})
        {:noreply, new_state}

      {:noreply, new_state} ->
        {:noreply, new_state}

      {:error, reason, new_state} ->
        send(from, {:error, reason})
        {:noreply, new_state}

      _ ->
        send(from, {:reply, {:text, ""}})
        {:noreply, state}
    end
  end

  def handle_info({:unsubscribe, channel, from}, state) do
    result = WebsockexNova.HandlerInvoker.invoke(:subscription_handler, :unsubscribe, [channel, state], state)

    case result do
      {:reply, reply, new_state} ->
        send(from, {:reply, reply})
        {:noreply, new_state}

      {:noreply, new_state} ->
        {:noreply, new_state}

      {:error, reason, new_state} ->
        send(from, {:error, reason})
        {:noreply, new_state}

      _ ->
        send(from, {:reply, {:text, ""}})
        {:noreply, state}
    end
  end

  # Auth events: delegate to auth_handler
  def handle_info({:authenticate, credentials, from}, state) do
    result = WebsockexNova.HandlerInvoker.invoke(:auth_handler, :authenticate, [credentials, state], state)

    case result do
      {:reply, reply, new_state} ->
        send(from, {:reply, reply})
        {:noreply, new_state}

      {:noreply, new_state} ->
        {:noreply, new_state}

      {:error, reason, new_state} ->
        send(from, {:error, reason})
        {:noreply, new_state}

      _ ->
        send(from, {:reply, {:text, ""}})
        {:noreply, state}
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
  def handle_info({:error_event, error, from}, state) do
    result = WebsockexNova.HandlerInvoker.invoke(:error_handler, :handle_error, [error, %{}, state], state)

    case result do
      {:reply, reply, new_state} ->
        send(from, {:reply, reply})
        {:noreply, new_state}

      {:noreply, new_state} ->
        {:noreply, new_state}

      {:stop, reason, new_state} ->
        {:stop, reason, new_state}

      _ ->
        {:noreply, state}
    end
  end

  # Message events: delegate to message_handler
  def handle_info({:message_event, message, from}, state) do
    result = WebsockexNova.HandlerInvoker.invoke(:message_handler, :handle_message, [message, state], state)

    case result do
      {:reply, reply, new_state} ->
        send(from, {:reply, reply})
        {:noreply, new_state}

      {:reply_many, replies, new_state} ->
        Enum.each(replies, fn reply -> send(from, {:reply, reply}) end)
        {:noreply, new_state}

      {:ok, new_state} ->
        {:noreply, new_state}

      {:close, code, reason, new_state} ->
        {:stop, {:close, code, reason}, new_state}

      {:error, reason, new_state} ->
        send(from, {:error, reason})
        {:noreply, new_state}

      _ ->
        {:noreply, state}
    end
  end

  # Connection established: delegate to connection_handler
  def handle_info({:websocket_connected, conn_info}, state) do
    result = WebsockexNova.HandlerInvoker.invoke(:connection_handler, :handle_connect, [conn_info, state], state)

    case result do
      {:ok, new_state} ->
        {:noreply, new_state}

      {:reply, _frame_type, _data, new_state} ->
        {:noreply, new_state}

      {:close, code, reason, new_state} ->
        {:stop, {:close, code, reason}, new_state}

      {:reconnect, new_state} ->
        {:noreply, new_state}

      {:stop, reason, new_state} ->
        {:stop, reason, new_state}

      _ ->
        {:noreply, state}
    end
  end

  # Connection disconnected: delegate to connection_handler
  def handle_info({:websocket_disconnected, reason}, state) do
    result = WebsockexNova.HandlerInvoker.invoke(:connection_handler, :handle_disconnect, [reason, state], state)

    case result do
      {:ok, new_state} ->
        {:noreply, new_state}

      {:reconnect, new_state} ->
        {:noreply, new_state}

      {:stop, stop_reason, new_state} ->
        {:stop, stop_reason, new_state}

      _ ->
        {:noreply, state}
    end
  end

  # Refactored handle_info for JSON-RPC response correlation (with stream_ref)
  def handle_info({:websocket_frame, _stream_ref, {:text, frame_data}}, %{pending_requests: pending, config: config} = s) do
    notification_pid = Map.get(config, :notification_pid)

    Logger.debug(
      "[DEBUG] websocket_frame (with stream_ref): frame_data=#{inspect(frame_data)}, pending_requests=#{inspect(pending)}"
    )

    case Jason.decode(frame_data) do
      {:ok, %{"id" => id}} ->
        Logger.debug("[DEBUG] Decoded response with id=#{inspect(id)}. Attempting to pop from pending_requests.")

        case Map.pop(pending, id) do
          {nil, new_pending} ->
            Logger.debug(
              "[DEBUG] Received JSON-RPC response for id=#{inspect(id)} but no pending request found. new_pending_requests=#{inspect(new_pending)}"
            )

            dispatch_notification(notification_pid, frame_data)
            {:noreply, %{s | pending_requests: new_pending}}

          {from, new_pending} ->
            Logger.debug(
              "[DEBUG] Routing JSON-RPC response for id=#{inspect(id)} to from=#{inspect(from)}. new_pending_requests=#{inspect(new_pending)}"
            )

            Logger.debug("[REPLY DEBUG] Sending {:reply, {:text, frame_data}} to #{inspect(from)}")
            # Use the helper for consistent state update and timer cleanup
            new_state = handle_json_rpc_response(id, {:text, frame_data}, %{s | pending_requests: pending})
            {:noreply, new_state}
        end

      {:ok, notification} ->
        Logger.debug(
          "[DEBUG] Received notification (no id): #{inspect(notification)}. Sending to notification_pid=#{inspect(notification_pid)}"
        )

        dispatch_notification(notification_pid, frame_data)
        {:noreply, s}

      _ ->
        Logger.debug("[DEBUG] Received unhandled websocket_frame: #{inspect(frame_data)}")
        dispatch_notification(notification_pid, frame_data)
        {:noreply, s}
    end
  end

  # Refactored Gun WebSocket frame handler
  def handle_info({:gun_ws, _gun_pid, _stream_ref, frame}, state) do
    handle_gun_ws_frame(frame, state)
  end

  # Refactored Gun connection down handler
  def handle_info({:gun_down, gun_pid, protocol, reason, _killed_streams, _unprocessed_streams}, state) do
    handle_gun_down(state, reason, protocol, gun_pid)
  end

  # Refactored Gun error handler
  def handle_info({:gun_error, _gun_pid, _stream_ref, reason}, state) do
    handle_gun_error(state, reason)
  end

  # Gun connection up
  def handle_info({:gun_up, gun_pid, protocol}, state) do
    Logger.info("Gun connection up: #{inspect(protocol)}")
    :telemetry.execute(TelemetryEvents.connection_open(), %{protocol: protocol}, %{gun_pid: gun_pid})
    {:noreply, state}
  end

  # Gun WebSocket upgrade
  def handle_info({:gun_upgrade, gun_pid, stream_ref, ["websocket"], headers}, state) do
    Logger.info("WebSocket upgrade successful: #{inspect(headers)}")

    :telemetry.execute(TelemetryEvents.connection_websocket_upgrade(), %{headers: headers}, %{
      gun_pid: gun_pid,
      stream_ref: stream_ref
    })

    # Flush request buffer
    make_timer = fn id -> Process.send_after(self(), {:request_timeout, id}, 10_000) end
    {new_state, _sent} = StateHelpers.flush_buffer(state, make_timer)
    new_state = %{new_state | ws_stream_ref: stream_ref}

    {:noreply, new_state}
  end

  # On WebSocket upgrade failure, fail all buffered requests and transition to safe state
  def handle_info({:gun_upgrade, _gun_pid, _stream_ref, headers}, state)
      when not is_list(headers) or headers != ["websocket"] do
    Logger.error("WebSocket upgrade failed. Failing all buffered requests.")
    Enum.each(state.request_buffer, fn {_frame, _id, from} -> send(from, {:error, :websocket_upgrade_failed}) end)
    :telemetry.execute(TelemetryEvents.error_occurred(), %{reason: :websocket_upgrade_failed}, %{})
    {:stop, :websocket_upgrade_failed, %{state | request_buffer: []}}
  end

  # Reconnect event
  def handle_info(:reconnect, state) do
    Logger.info("Attempting reconnection...")
    # Use ConnectionManager to initiate connection
    case ConnectionManager.start_connection(state) do
      {:ok, new_state} ->
        {:noreply, new_state}

      {:error, reason, error_state} ->
        Logger.error("Reconnection failed: #{inspect(reason)}")
        {:noreply, error_state}
    end
  end

  # Handle request timeout for pending JSON-RPC requests
  def handle_info({:request_timeout, id}, state) do
    {from, new_state} = StateHelpers.pop_pending_request(state, id)
    if from, do: send(from, {:error, :timeout})
    {:noreply, new_state}
  end

  # Catch-all for unexpected messages: log and crash (let it crash philosophy)
  @impl true
  def handle_info(msg, state) do
    Logger.error("Unexpected message in WebsockexNova.Connection: #{inspect(msg)} | state: #{inspect(state)}")
    raise "Unexpected message in WebsockexNova.Connection: #{inspect(msg)}"
  end

  # On terminate, cancel all timers and fail all pending requests
  @impl true
  def terminate(reason, state) do
    Logger.debug("WebsockexNova.Connection terminating: reason=#{inspect(reason)}, state=#{inspect(state)}")
    Enum.each(Map.values(state.pending_timeouts || %{}), &Process.cancel_timer/1)
    Enum.each(Map.values(state.pending_requests || %{}), fn from -> send(from, {:error, :terminated}) end)
    Enum.each(state.request_buffer || [], fn {_frame, _id, from} -> send(from, {:error, :terminated}) end)
    :ok
  end

  # --- Helper Functions ---
  defp handle_json_rpc_response(id, from, %{pending_requests: pending, pending_timeouts: timeouts} = state) do
    {from_pid, new_pending} = Map.pop(pending, id)
    timer_ref = Map.get(timeouts, id)
    if timer_ref, do: Process.cancel_timer(timer_ref)
    new_timeouts = Map.delete(timeouts, id)
    if from_pid, do: send(from_pid, {:reply, from})
    %{state | pending_requests: new_pending, pending_timeouts: new_timeouts}
  end

  defp dispatch_notification(notification_pid, frame_data) when not is_nil(notification_pid) do
    send(notification_pid, {:notification, {:websockex_nova, {:websocket_frame, {:text, frame_data}}}})
  end

  defp dispatch_notification(_, _), do: :ok

  defp handle_gun_ws_frame({:text, data}, state) do
    pending = Map.get(state, :pending_requests, %{})
    timeouts = Map.get(state, :pending_timeouts, %{})

    case Jason.decode(data) do
      {:ok, %{"id" => id}} ->
        {from, new_pending} = Map.pop(pending, id)
        timer_ref = Map.get(timeouts, id)
        if timer_ref, do: Process.cancel_timer(timer_ref)
        new_timeouts = Map.delete(timeouts, id)
        if from, do: send(from, {:reply, {:text, data}})
        {:noreply, %{state | pending_requests: new_pending, pending_timeouts: new_timeouts}}

      _ ->
        {:noreply, state}
    end
  end

  defp handle_gun_ws_frame(_, state), do: {:noreply, state}

  defp handle_gun_down(state, reason, protocol, gun_pid) do
    Logger.warning("Gun connection down: #{inspect(reason)}")
    :telemetry.execute(TelemetryEvents.connection_close(), %{protocol: protocol, reason: reason}, %{gun_pid: gun_pid})
    Enum.each(Map.values(state.pending_timeouts), &Process.cancel_timer/1)
    Enum.each(Map.values(state.pending_requests), fn from -> send(from, {:error, :disconnected}) end)
    state = %{state | pending_requests: %{}, request_buffer: [], last_error: reason, pending_timeouts: %{}}
    reconnect_callback = fn delay, _attempt -> Process.send_after(self(), :reconnect, delay) end
    new_state = ConnectionManager.schedule_reconnection(state, reconnect_callback)
    {:noreply, new_state}
  end

  defp handle_gun_error(state, reason) do
    Logger.error("Gun error: #{inspect(reason)}. Failing all pending and buffered requests.")
    Enum.each(Map.values(state.pending_timeouts), &Process.cancel_timer/1)
    Enum.each(Map.values(state.pending_requests), fn from -> send(from, {:error, reason}) end)
    Enum.each(state.request_buffer, fn {_frame, _id, from} -> send(from, {:error, reason}) end)
    :telemetry.execute(TelemetryEvents.error_occurred(), %{reason: reason}, %{})
    {:stop, reason, %{state | pending_requests: %{}, request_buffer: [], pending_timeouts: %{}}}
  end
end
