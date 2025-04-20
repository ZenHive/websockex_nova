defmodule Examples.CustomHandlers do
  @moduledoc """
  A comprehensive example demonstrating how to implement and use custom handlers with WebsockexNova.

  This example shows:
  1. Custom connection handler
  2. Custom message handler
  3. Custom error handler
  4. Client application using these handlers
  """

  defmodule CustomConnectionHandler do
    @moduledoc """
    Custom connection handler that demonstrates connection lifecycle management.

    Features:
    - Automatically reconnects up to a configured number of attempts
    - Logs connect/disconnect events
    - Maintains connection statistics
    """
    @behaviour WebsockexNova.Behaviors.ConnectionHandler

    require Logger

    @impl true
    def init(opts) do
      # Set up initial connection state with defaults
      initial_state = %{
        reconnect_attempts: 0,
        max_reconnect_attempts: Keyword.get(opts, :max_reconnect_attempts, 5),
        connect_count: 0,
        disconnect_count: 0,
        last_connect_time: nil,
        last_disconnect_time: nil,
        connection_history: []
      }

      {:ok, initial_state}
    end

    @impl true
    def handle_connect(conn_info, state) do
      # Log connection event
      Logger.info("Connected to #{conn_info.host}:#{conn_info.port} via #{conn_info.transport}")

      # Update connection statistics
      now = DateTime.utc_now()

      updated_state =
        state
        |> Map.put(:reconnect_attempts, 0)
        |> Map.update!(:connect_count, &(&1 + 1))
        |> Map.put(:last_connect_time, now)
        |> Map.update!(:connection_history, &[{:connect, now, conn_info} | &1])

      # Send optional ping frame after connection
      {:reply, :ping, "", updated_state}
    end

    @impl true
    def handle_disconnect({:remote, code, reason}, state) do
      # Log disconnection event
      Logger.warning("Remote disconnect (code #{code}): #{reason}")

      # Update statistics
      now = DateTime.utc_now()

      updated_state =
        state
        |> Map.update!(:disconnect_count, &(&1 + 1))
        |> Map.put(:last_disconnect_time, now)
        |> Map.update!(:connection_history, &[{:disconnect, now, {:remote, code, reason}} | &1])

      # Attempt reconnection if under max attempts
      if state.reconnect_attempts < state.max_reconnect_attempts do
        # Exponential backoff for reconnect
        Process.sleep(calculate_backoff(state.reconnect_attempts))

        Logger.info("Attempting reconnection (#{state.reconnect_attempts + 1}/#{state.max_reconnect_attempts})")
        {:reconnect, Map.update!(updated_state, :reconnect_attempts, &(&1 + 1))}
      else
        Logger.error("Maximum reconnection attempts reached (#{state.max_reconnect_attempts})")
        {:stop, :max_reconnect_attempts_reached, updated_state}
      end
    end

    def handle_disconnect({:local, code, reason}, state) do
      # For locally initiated disconnects, don't reconnect
      Logger.info("Local disconnect (code #{code}): #{reason}")

      now = DateTime.utc_now()

      updated_state =
        state
        |> Map.update!(:disconnect_count, &(&1 + 1))
        |> Map.put(:last_disconnect_time, now)
        |> Map.update!(:connection_history, &[{:disconnect, now, {:local, code, reason}} | &1])

      {:ok, updated_state}
    end

    def handle_disconnect({:error, reason}, state) do
      # For error disconnects, reconnect with backoff
      Logger.error("Connection error: #{inspect(reason)}")

      now = DateTime.utc_now()

      updated_state =
        state
        |> Map.update!(:disconnect_count, &(&1 + 1))
        |> Map.put(:last_disconnect_time, now)
        |> Map.update!(:connection_history, &[{:disconnect, now, {:error, reason}} | &1])

      if state.reconnect_attempts < state.max_reconnect_attempts do
        Process.sleep(calculate_backoff(state.reconnect_attempts))

        Logger.info("Attempting reconnection (#{state.reconnect_attempts + 1}/#{state.max_reconnect_attempts})")
        {:reconnect, Map.update!(updated_state, :reconnect_attempts, &(&1 + 1))}
      else
        Logger.error("Maximum reconnection attempts reached (#{state.max_reconnect_attempts})")
        {:stop, :max_reconnect_attempts_reached, updated_state}
      end
    end

    @impl true
    def handle_frame(:ping, _data, state) do
      # Respond to ping with pong
      {:reply, :pong, "", state}
    end

    def handle_frame(:pong, _data, state) do
      # Handle pong response
      {:ok, Map.put(state, :last_pong_time, DateTime.utc_now())}
    end

    def handle_frame(_type, _data, state) do
      # Default frame handler - delegate to message handler
      {:ok, state}
    end

    @impl true
    def handle_timeout(state) do
      # Handle connection timeout
      Logger.warning("Connection timeout occurred")

      if state.reconnect_attempts < state.max_reconnect_attempts do
        {:reconnect, Map.update!(state, :reconnect_attempts, &(&1 + 1))}
      else
        {:stop, :max_reconnect_attempts_reached, state}
      end
    end

    # Calculate exponential backoff for reconnection attempts
    defp calculate_backoff(attempt) do
      # Base delay of 1000ms with exponential increase and 30s max
      base_delay = 1000
      max_delay = 30_000
      delay = base_delay * :math.pow(2, attempt)
      min(trunc(delay), max_delay)
    end
  end

  defmodule CustomMessageHandler do
    @moduledoc """
    Custom message handler that demonstrates processing of different message types.

    Features:
    - JSON decoding of text frames
    - Message validation
    - Message statistics
    """
    @behaviour WebsockexNova.Behaviors.MessageHandler

    require Logger

    # Initialize state with defaults (not part of behavior)
    def init(opts) do
      {:ok,
       %{
         message_count: 0,
         json_message_count: 0,
         binary_message_count: 0,
         error_count: 0,
         callback_module: Keyword.get(opts, :callback_module),
         last_message: nil
       }}
    end

    # Implement required callbacks based on the behavior
    @impl true
    def handle_message(message, state) do
      frame_type = message_type(message)

      case validate_message(message) do
        {:ok, data} ->
          do_handle_message(frame_type, data, state)

        {:error, reason} ->
          Logger.error("Invalid message: #{inspect(reason)}")
          {:error, reason, state}
      end
    end

    @impl true
    def message_type(message) do
      cond do
        is_binary(message) -> :text
        is_map(message) -> :json
        is_list(message) -> :binary
        true -> :unknown
      end
    end

    @impl true
    def validate_message(message) when is_binary(message) do
      case Jason.decode(message) do
        {:ok, json} -> {:ok, json}
        # Still valid as text
        {:error, _} -> {:ok, message}
      end
    end

    def validate_message(message) when is_map(message) do
      {:ok, message}
    end

    def validate_message(message) when is_list(message) do
      if Enum.all?(message, fn b -> is_integer(b) and b >= 0 and b <= 255 end) do
        {:ok, message}
      else
        {:error, :invalid_binary}
      end
    end

    def validate_message(_) do
      {:error, :unsupported_message_type}
    end

    @impl true
    def encode_message(:text, data) when is_binary(data) do
      {:text, data}
    end

    def encode_message(:json, data) when is_map(data) do
      {:text, Jason.encode!(data)}
    end

    def encode_message(:binary, data) when is_list(data) do
      {:binary, :erlang.list_to_binary(data)}
    end

    def encode_message(_, data) do
      {:error, :cannot_encode, data}
    end

    # Internal helper functions
    defp do_handle_message(:text, data, state) when is_binary(data) do
      # Process text message
      Logger.info("Received text message: #{data}")

      # Update message statistics
      state =
        state
        |> Map.update(:message_count, 1, &(&1 + 1))
        |> Map.update(:text_message_count, 1, &(&1 + 1))
        |> Map.put(:last_message, {:text, data, DateTime.utc_now()})

      # If a callback module is provided, forward the message
      if Map.get(state, :callback_module) && function_exported?(state.callback_module, :handle_text, 2) do
        apply(state.callback_module, :handle_text, [data, self()])
      end

      {:ok, state}
    end

    defp do_handle_message(:json, data, state) when is_map(data) do
      # Handle decoded JSON
      Logger.debug("Received JSON message: #{inspect(data)}")

      # Update message statistics
      state =
        state
        |> Map.update(:message_count, 1, &(&1 + 1))
        |> Map.update(:json_message_count, 1, &(&1 + 1))
        |> Map.put(:last_message, {:json, data, DateTime.utc_now()})

      # If a callback module is provided, forward the message
      if Map.get(state, :callback_module) && function_exported?(state.callback_module, :handle_json, 2) do
        apply(state.callback_module, :handle_json, [data, self()])
      end

      {:ok, state}
    end

    defp do_handle_message(:binary, data, state) do
      # Process binary message
      Logger.debug("Received binary message (#{length(data)} bytes)")

      # Update message statistics
      state =
        state
        |> Map.update(:message_count, 1, &(&1 + 1))
        |> Map.update(:binary_message_count, 1, &(&1 + 1))
        |> Map.put(:last_message, {:binary, data, DateTime.utc_now()})

      # If a callback module is provided, forward the message
      if Map.get(state, :callback_module) && function_exported?(state.callback_module, :handle_binary, 2) do
        apply(state.callback_module, :handle_binary, [data, self()])
      end

      {:ok, state}
    end

    defp do_handle_message(frame_type, data, state) do
      # Handle other message types
      Logger.debug("Received #{frame_type} message: #{inspect(data)}")

      # Update message count
      state = Map.update(state, :message_count, 1, &(&1 + 1))

      # Forward if callback exists
      if Map.get(state, :callback_module) && function_exported?(state.callback_module, :handle_frame, 3) do
        apply(state.callback_module, :handle_frame, [frame_type, data, self()])
      end

      {:ok, state}
    end
  end

  defmodule CustomErrorHandler do
    @moduledoc """
    Custom error handler that demonstrates sophisticated error handling strategies.

    Features:
    - Error categorization
    - Selective retry logic
    - Error reporting
    """
    @behaviour WebsockexNova.Behaviors.ErrorHandler

    require Logger

    # Initialize state with defaults (not part of behavior)
    def init(opts) do
      {:ok,
       %{
         error_count: 0,
         error_history: [],
         recovery_count: 0,
         # Optional error reporting function
         report_fn: Keyword.get(opts, :report_fn)
       }}
    end

    # Implement required callbacks based on the behavior
    @impl true
    def handle_error(error_type, error, state) do
      # Update error counter and history
      state =
        state
        |> Map.update(:error_count, 1, &(&1 + 1))
        |> Map.update(
          :error_history,
          [{error_type, error, DateTime.utc_now()}],
          &[{error_type, error, DateTime.utc_now()} | &1]
        )

      # Log the error
      log_error(error_type, error, state)

      # Check if we should retry
      if should_reconnect?(error_type, error, state) do
        {:retry, state}
      else
        {:error, state}
      end
    end

    @impl true
    def classify_error(:connection, error) when is_map(error) do
      cond do
        Map.get(error, :reason) in [:timeout, :closed, :econnrefused, :nxdomain] -> :network
        Map.get(error, :code) in [401, 403] -> :authentication
        true -> :unknown
      end
    end

    def classify_error(:message, _error) do
      :message_processing
    end

    def classify_error(:subscription, _error) do
      :subscription
    end

    def classify_error(_type, _error) do
      :unknown
    end

    @impl true
    def log_error(:connection, error, _state) do
      Logger.error("Connection error: #{inspect(error)}")
    end

    def log_error(:message, error, _state) do
      Logger.error("Message error: #{inspect(error)}")
    end

    def log_error(:subscription, error, _state) do
      Logger.error("Subscription error: #{inspect(error)}")
    end

    def log_error(error_type, error, _state) do
      Logger.error("#{error_type} error: #{inspect(error)}")
    end

    @impl true
    def should_reconnect?(:connection, error, state) do
      classification = classify_error(:connection, error)

      case classification do
        :network ->
          # For network errors, retry if under max attempts
          max_attempts = Map.get(state, :max_reconnect_attempts, 5)
          current_attempts = Map.get(state, :reconnect_attempts, 0)
          current_attempts < max_attempts

        :authentication ->
          # Don't retry auth errors
          false

        _ ->
          # Default to retry for other errors
          true
      end
    end

    def should_reconnect?(:message, _error, _state) do
      # Don't reconnect for message errors
      false
    end

    def should_reconnect?(:subscription, _error, _state) do
      # Try to reconnect for subscription errors
      true
    end

    def should_reconnect?(_error_type, _error, _state) do
      # Default to false for unknown error types
      false
    end
  end

  defmodule Client do
    @moduledoc """
    Example client application that uses the custom handlers.
    """
    use GenServer

    alias WebsockexNova.Client, as: WSClient
    alias WebsockexNova.Connection

    require Logger

    def start_link(opts \\ []) do
      GenServer.start_link(__MODULE__, opts, name: opts[:name] || __MODULE__)
    end

    def init(opts) do
      # Configure custom handlers
      connection_opts = [
        adapter: WebsockexNova.Platform.Echo.Adapter,
        connection_handler: CustomConnectionHandler,
        message_handler: CustomMessageHandler,
        error_handler: CustomErrorHandler,
        # Pass the current module to receive callbacks
        callback_module: __MODULE__
      ]

      # Start connection
      case Connection.start_link(connection_opts) do
        {:ok, conn} ->
          # Schedule periodic ping
          schedule_ping()

          {:ok,
           %{
             conn: conn,
             messages: [],
             ping_interval: Keyword.get(opts, :ping_interval, 30_000)
           }}

        {:error, reason} ->
          Logger.error("Failed to start connection: #{inspect(reason)}")
          {:stop, reason}
      end
    end

    # Client API

    def send_message(client \\ __MODULE__, message) do
      GenServer.call(client, {:send, message})
    end

    def get_messages(client \\ __MODULE__) do
      GenServer.call(client, :get_messages)
    end

    def ping(client \\ __MODULE__) do
      GenServer.call(client, :ping)
    end

    # Callback handlers

    # Forward messages from message handler
    def handle_json(json, _pid) do
      Logger.info("Received JSON: #{inspect(json)}")
      GenServer.cast(__MODULE__, {:received_json, json})
    end

    def handle_text(text, _pid) do
      Logger.info("Received text: #{text}")
      GenServer.cast(__MODULE__, {:received_text, text})
    end

    # GenServer callbacks

    def handle_call({:send, message}, _from, %{conn: conn} = state) when is_binary(message) do
      case WSClient.send_text(conn, message) do
        {:text, response} ->
          {:reply, {:ok, response}, state}

        error ->
          {:reply, {:error, error}, state}
      end
    end

    def handle_call({:send, message}, _from, %{conn: conn} = state) when is_map(message) do
      case WSClient.send_json(conn, message) do
        {:text, response} ->
          {:reply, {:ok, response}, state}

        error ->
          {:reply, {:error, error}, state}
      end
    end

    def handle_call(:get_messages, _from, %{messages: messages} = state) do
      {:reply, messages, state}
    end

    def handle_call(:ping, _from, %{conn: conn} = state) do
      result = WSClient.ping(conn)
      {:reply, result, state}
    end

    def handle_cast({:received_json, json}, state) do
      updated_state = Map.update!(state, :messages, &[{:json, json, DateTime.utc_now()} | &1])
      {:noreply, updated_state}
    end

    def handle_cast({:received_text, text}, state) do
      updated_state = Map.update!(state, :messages, &[{:text, text, DateTime.utc_now()} | &1])
      {:noreply, updated_state}
    end

    def handle_info(:ping, %{conn: conn} = state) do
      Logger.debug("Sending periodic ping")
      WSClient.ping(conn)
      schedule_ping()
      {:noreply, state}
    end

    # Schedule the next ping
    defp schedule_ping do
      Process.send_after(self(), :ping, 30_000)
    end
  end
end
