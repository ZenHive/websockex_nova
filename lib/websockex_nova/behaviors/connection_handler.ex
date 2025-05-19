defmodule WebsockexNova.Behaviors.ConnectionHandler do
  @moduledoc """
  Behaviour for handling WebSocket connection lifecycle events.

  The ConnectionHandler defines callbacks for managing the complete lifecycle of a WebSocket
  connection, from initial connection parameters through disconnection. It serves as the
  foundation for platform-specific connection management.

  ## Architecture

  ConnectionHandler is responsible for:
  - Providing connection parameters (host, port, path, transport options)
  - Handling connection establishment events
  - Managing disconnection events
  - Preparing outgoing frames
  - Building and sending ping frames
  - Processing incoming pong responses

  The handler maintains its state as a map throughout the connection lifecycle.

  ## Callback Flow

  1. `init/1` - Called once when the handler is initialized
  2. `connection_info/1` - Provides connection parameters for establishing connection
  3. `handle_connect/2` - Called when WebSocket connection is established
  4. `prepare_frame/3` - Called before sending any frame (for encryption, encoding, etc.)
  5. `ping/2` - Called to build ping frames (if custom format needed)
  6. `handle_pong/2` - Called when pong frames are received
  7. `handle_disconnect/2` - Called on disconnection

  ## Reconnection Policy

  Important: ConnectionHandler does NOT handle reconnection logic.
  - Never return `{:reconnect, state}` from any callback
  - Reconnection decisions are made exclusively by the ErrorHandler
  - On disconnect, return `{:ok, state}` or `{:stop, reason, state}`

  ## Implementation Example

      defmodule MyApp.CustomConnectionHandler do
        @behaviour WebsockexNova.Behaviors.ConnectionHandler

        @impl true
        def init(opts) do
          state = %{
            options: opts,
            connected_at: nil,
            ping_interval: opts[:ping_interval] || 30_000
          }
          {:ok, state}
        end

        @impl true
        def connection_info(opts) do
          # Merge runtime options with defaults
          conn_info = %{
            host: opts[:host] || "api.example.com",
            port: opts[:port] || 443,
            path: opts[:path] || "/ws/v1",
            transport: :tls,
            transport_opts: %{
              verify: :verify_peer,
              cacerts: :certifi.cacerts(),
              server_name_indication: to_charlist(opts[:host] || "api.example.com")
            },
            timeout: opts[:timeout] || 10_000
          }
          {:ok, conn_info}
        end

        @impl true
        def handle_connect(conn_info, state) do
          # Connection established, update state
          updated_state = Map.merge(state, %{
            connected_at: DateTime.utc_now(),
            conn_info: conn_info
          })
          {:ok, updated_state}
        end

        @impl true
        def prepare_frame(frame_data, frame_type, state) do
          # Optionally transform frame data before sending
          # e.g., add encryption, compression, or custom encoding
          case frame_type do
            :text ->
              # Maybe add message ID or timestamp
              prepared = Jason.encode!(%{
                id: UUID.uuid4(),
                timestamp: System.system_time(:millisecond),
                data: frame_data
              })
              {:ok, prepared, state}
            
            :binary ->
              # Binary frames might need different preparation
              {:ok, frame_data, state}
            
            _ ->
              # Control frames usually pass through unchanged
              {:ok, frame_data, state}
          end
        end

        @impl true
        def ping(state) do
          # Build custom ping frame if needed
          ping_data = %{
            timestamp: System.system_time(:millisecond),
            sequence: Map.get(state, :ping_sequence, 0)
          }
          
          updated_state = Map.update(state, :ping_sequence, 1, &(&1 + 1))
          {:ok, Jason.encode!(ping_data), updated_state}
        end

        @impl true
        def handle_pong(frame_data, state) do
          # Process pong response, maybe calculate latency
          with {:ok, pong_data} <- Jason.decode(frame_data) do
            latency = System.system_time(:millisecond) - pong_data["timestamp"]
            updated_state = Map.put(state, :last_latency, latency)
            {:ok, updated_state}
          else
            _ ->
              # Malformed pong, but don't crash
              {:ok, state}
          end
        end

        @impl true
        def handle_disconnect(reason, state) do
          # Clean up resources, log disconnection
          # Remember: Don't return {:reconnect, state} here!
          case reason do
            :normal ->
              {:ok, Map.put(state, :disconnected_at, DateTime.utc_now())}
            
            {:error, :timeout} ->
              # Log timeout but let ErrorHandler decide on reconnection
              {:ok, Map.put(state, :last_error, :timeout)}
            
            other ->
              # Unexpected disconnection
              {:ok, Map.put(state, :last_error, other)}
          end
        end
      end

  ## Connection Info Structure

  The `connection_info/1` callback should return a map with these keys:
  - `:host` - WebSocket server hostname (required)
  - `:port` - Port number (required)
  - `:path` - WebSocket path (required)
  - `:transport` - Either `:tcp` or `:tls` (required)
  - `:transport_opts` - Transport-specific options map (optional)
  - `:timeout` - Connection timeout in milliseconds (optional)
  - `:protocols` - List of WebSocket subprotocols (optional)
  - `:headers` - Additional HTTP headers for upgrade (optional)

  ## Tips

  1. Keep connection state separate from application state
  2. Use prepare_frame/3 for consistent message formatting
  3. Implement proper error handling in all callbacks
  4. Consider implementing heartbeat/ping logic for connection health
  5. Log important connection events for debugging
  6. Don't implement reconnection logic in this behavior

  See `WebsockexNova.Defaults.DefaultConnectionHandler` for a reference implementation.
  """

  @typedoc "Handler state"
  @type state :: map()

  @typedoc "Connection info map"
  @type conn_info :: map()

  @typedoc "Disconnect reason"
  @type disconnect_reason :: term()

  @typedoc "Frame type"
  @type frame_type :: :text | :binary | :ping | :pong | :close

  @doc """
  Initialize the handler's state.
  """
  @callback init(opts :: term()) :: {:ok, state} | {:error, term()}

  @doc """
  Handle connection establishment.
  Returns:
    - `{:ok, state}`
    - `{:reply, frame_type, data, state}`
    - `{:close, code, reason, state}`
    - `{:stop, reason, state}`
  """
  @callback handle_connect(conn_info, state) ::
              {:ok, state}
              | {:reply, frame_type, binary(), state}
              | {:close, integer(), String.t(), state}
              | {:stop, term(), state}

  @doc """
  Handle disconnect event.
  Returns:
    - `{:ok, state}`
    - `{:stop, reason, state}`
  """
  @callback handle_disconnect(disconnect_reason, state) ::
              {:ok, state}
              | {:stop, term(), state}

  @doc """
  Handle a received WebSocket frame.
  Returns:
    - `{:ok, state}`
    - `{:reply, frame_type, binary(), state}`
    - `{:close, code, reason, state}`
    | {:stop, reason, state}
  """
  @callback handle_frame(frame_type, binary(), state) ::
              {:ok, state}
              | {:reply, frame_type, binary(), state}
              | {:close, integer(), String.t(), state}
              | {:stop, term(), state}

  @doc """
  Optional: handle connection timeout.
  Returns:
    - `{:ok, state}`
    - `{:stop, reason, state}`
  """
  @callback handle_timeout(state) ::
              {:ok, state}
              | {:stop, term(), state}

  @doc """
  Ping the connection or stream.
  Returns:
    - `{:ok, state}`
    - `{:error, reason, state}`
  """
  @callback ping(stream_ref :: term(), state) ::
              {:ok, state}
              | {:error, term(), state}

  @doc """
  Query the status of the connection or stream.
  Returns:
    - `{:ok, status, state}`
    - `{:error, reason, state}`
  """
  @callback status(stream_ref :: term(), state) ::
              {:ok, term(), state}
              | {:error, term(), state}

  @doc """
  Returns connection information for establishing a WebSocket connection.
  Returns:
    - `{:ok, conn_info}`
    - `{:error, reason}`
  """
  @callback connection_info(opts :: map() | keyword()) :: {:ok, conn_info} | {:error, term()}
end
