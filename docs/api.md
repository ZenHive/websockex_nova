# WebsockexNew API Reference

Complete API documentation for all WebsockexNew modules.

## WebsockexNew.Client

Core WebSocket client interface with 5 essential functions.

### Types

```elixir
@type t :: %__MODULE__{
  gun_pid: pid() | nil,
  stream_ref: reference() | nil,
  state: :connecting | :connected | :disconnected,
  url: String.t() | nil,
  monitor_ref: reference() | nil
}
```

### Functions

#### connect/2

```elixir
@spec connect(String.t() | WebsockexNew.Config.t(), keyword()) :: {:ok, t()} | {:error, term()}
```

Establish WebSocket connection using URL string or Config struct.

**Examples:**
```elixir
# Simple URL connection
{:ok, client} = WebsockexNew.Client.connect("wss://api.example.com/ws")

# With configuration
config = WebsockexNew.Config.new!("wss://api.example.com/ws", timeout: 10_000)
{:ok, client} = WebsockexNew.Client.connect(config)
```

#### send_message/2

```elixir
@spec send_message(t(), binary()) :: :ok | {:error, term()}
```

Send text message to WebSocket endpoint.

**Examples:**
```elixir
:ok = WebsockexNew.Client.send_message(client, "Hello, World!")
:ok = WebsockexNew.Client.send_message(client, Jason.encode!(%{type: "ping"}))
```

#### close/1

```elixir
@spec close(t()) :: :ok
```

Close WebSocket connection gracefully.

**Examples:**
```elixir
:ok = WebsockexNew.Client.close(client)
```

#### subscribe/2

```elixir
@spec subscribe(t(), list()) :: :ok | {:error, term()}
```

Subscribe to channels/topics (sends JSON-RPC subscription message).

**Examples:**
```elixir
:ok = WebsockexNew.Client.subscribe(client, ["ticker.BTC-USD", "trades.ETH-USD"])
```

#### get_state/1

```elixir
@spec get_state(t()) :: :connecting | :connected | :disconnected
```

Get current connection state.

**Examples:**
```elixir
:connected = WebsockexNew.Client.get_state(client)
```

---

## WebsockexNew.Config

Configuration management for WebSocket connections.

### Types

```elixir
@type t :: %__MODULE__{
  url: String.t(),
  headers: [{String.t(), String.t()}],
  timeout: pos_integer(),
  retry_count: non_neg_integer(),
  retry_delay: pos_integer(),
  heartbeat_interval: pos_integer()
}
```

### Functions

#### new/2

```elixir
@spec new(String.t(), keyword()) :: {:ok, t()} | {:error, String.t()}
```

Create and validate configuration.

**Examples:**
```elixir
{:ok, config} = WebsockexNew.Config.new("wss://api.example.com/ws")
{:ok, config} = WebsockexNew.Config.new("wss://api.example.com/ws", 
  timeout: 10_000,
  retry_count: 5,
  headers: [{"Authorization", "Bearer token"}]
)
```

#### new!/2

```elixir
@spec new!(String.t(), keyword()) :: t()
```

Create configuration, raising on validation errors.

**Examples:**
```elixir
config = WebsockexNew.Config.new!("wss://api.example.com/ws", timeout: 10_000)
```

#### validate/1

```elixir
@spec validate(t()) :: {:ok, t()} | {:error, String.t()}
```

Validate configuration struct.

---

## WebsockexNew.MessageHandler

Message processing and routing for WebSocket frames.

### Functions

#### handle_message/2

```elixir
def handle_message(message, handler_fun \\ &default_handler/1)
```

Process Gun messages and WebSocket frames, routing to handler function.

**Message Types:**
- `{:gun_upgrade, conn_pid, stream_ref, ["websocket"], headers}` - WebSocket upgrade successful
- `{:gun_ws, conn_pid, stream_ref, frame}` - WebSocket frame received
- `{:gun_down, conn_pid, protocol, reason, killed_streams}` - Connection lost
- `{:gun_error, conn_pid, stream_ref, reason}` - Connection error

**Examples:**
```elixir
handler = fn 
  {:message, {:text, data}} -> IO.puts("Received: #{data}")
  {:websocket_upgraded, pid, ref} -> IO.puts("Connected")
  {:connection_down, pid, reason} -> IO.puts("Disconnected: #{inspect(reason)}")
end

WebsockexNew.MessageHandler.handle_message(message, handler)
```

#### create_handler/1

```elixir
def create_handler(opts \\ [])
```

Create specialized message handler with callbacks for different event types.

**Options:**
- `:on_message` - Handle WebSocket data frames
- `:on_upgrade` - Handle successful WebSocket upgrade
- `:on_error` - Handle errors
- `:on_down` - Handle connection down events

**Examples:**
```elixir
handler = WebsockexNew.MessageHandler.create_handler(
  on_message: fn {:text, data} -> process_message(data) end,
  on_upgrade: fn {pid, ref} -> IO.puts("Connected!") end,
  on_error: fn error -> IO.puts("Error: #{inspect(error)}") end
)
```

#### handle_control_frame/3

```elixir
def handle_control_frame(frame, conn_pid, stream_ref)
```

Handle WebSocket control frames (ping/pong/close) automatically.

---

## WebsockexNew.ErrorHandler

Error categorization and recovery decision logic.

### Functions

#### categorize_error/1

```elixir
@spec categorize_error(term()) :: {:recoverable | :fatal, term()}
```

Categorize errors as recoverable or fatal, preserving raw error data.

**Recoverable Errors:**
- `:econnrefused`, `:timeout`, `:nxdomain`
- `:ehostunreach`, `:enetunreach`
- `{:tls_alert, _}`, `{:gun_down, _, _, _, _}`

**Fatal Errors:**
- `:invalid_frame`, `:frame_too_large`
- `:unauthorized`, `:invalid_credentials`

**Examples:**
```elixir
{:recoverable, {:error, :timeout}} = WebsockexNew.ErrorHandler.categorize_error({:error, :timeout})
{:fatal, {:error, :unauthorized}} = WebsockexNew.ErrorHandler.categorize_error({:error, :unauthorized})
```

#### recoverable?/1

```elixir
@spec recoverable?(term()) :: boolean()
```

Check if error can be recovered through reconnection.

**Examples:**
```elixir
true = WebsockexNew.ErrorHandler.recoverable?({:error, :timeout})
false = WebsockexNew.ErrorHandler.recoverable?({:error, :unauthorized})
```

#### handle_error/1

```elixir
@spec handle_error(term()) :: :reconnect | :stop
```

Determine appropriate action for error.

**Examples:**
```elixir
:reconnect = WebsockexNew.ErrorHandler.handle_error({:error, :timeout})
:stop = WebsockexNew.ErrorHandler.handle_error({:error, :unauthorized})
```

---

## WebsockexNew.Reconnection

Exponential backoff reconnection logic.

### Functions

#### calculate_delay/2

```elixir
@spec calculate_delay(non_neg_integer(), pos_integer()) :: pos_integer()
```

Calculate exponential backoff delay with 30-second maximum.

**Examples:**
```elixir
1000 = WebsockexNew.Reconnection.calculate_delay(0, 1000)  # First retry
2000 = WebsockexNew.Reconnection.calculate_delay(1, 1000)  # Second retry
4000 = WebsockexNew.Reconnection.calculate_delay(2, 1000)  # Third retry
```

#### reconnect/3

```elixir
@spec reconnect(Config.t(), non_neg_integer(), list()) :: {:ok, Client.t()} | {:error, :max_retries}
```

Attempt reconnection with exponential backoff and subscription restoration.

**Examples:**
```elixir
config = WebsockexNew.Config.new!("wss://api.example.com/ws", retry_count: 3)
subscriptions = ["ticker.BTC-USD"]

case WebsockexNew.Reconnection.reconnect(config, 0, subscriptions) do
  {:ok, client} -> IO.puts("Reconnected successfully")
  {:error, :max_retries} -> IO.puts("Max retries exceeded")
end
```

#### restore_subscriptions/2

```elixir
@spec restore_subscriptions(Client.t(), list()) :: :ok
```

Restore subscriptions after successful reconnection.

---

## WebsockexNew.ConnectionRegistry

ETS-based connection tracking without GenServer.

### Functions

#### init/0

```elixir
@spec init() :: :ok
```

Initialize connection registry ETS table.

#### register/2

```elixir
@spec register(String.t(), pid()) :: :ok
```

Register connection with process monitoring.

**Examples:**
```elixir
WebsockexNew.ConnectionRegistry.register("connection-1", gun_pid)
```

#### deregister/1

```elixir
@spec deregister(String.t()) :: :ok
```

Remove connection from registry.

#### get/1

```elixir
@spec get(String.t()) :: {:ok, pid()} | {:error, :not_found}
```

Retrieve connection PID by ID.

#### cleanup_dead/1

```elixir
@spec cleanup_dead(pid()) :: :ok
```

Remove dead connection entries by PID.

---

## WebsockexNew.Frame

WebSocket frame encoding and decoding utilities.

### Types

```elixir
@type frame_type :: :text | :binary | :ping | :pong | :close
@type frame :: {frame_type(), binary()}
```

### Functions

#### text/1

```elixir
@spec text(String.t()) :: frame()
```

Create text frame.

**Examples:**
```elixir
{:text, "Hello"} = WebsockexNew.Frame.text("Hello")
```

#### binary/1

```elixir
@spec binary(binary()) :: frame()
```

Create binary frame.

#### ping/0 & pong/1

```elixir
@spec ping() :: frame()
@spec pong(binary()) :: frame()
```

Create control frames.

**Examples:**
```elixir
{:ping, <<>>} = WebsockexNew.Frame.ping()
{:pong, "data"} = WebsockexNew.Frame.pong("data")
```

#### decode/1

```elixir
@spec decode(tuple()) :: {:ok, frame()} | {:error, String.t()}
```

Decode Gun WebSocket frames to standard format.

**Examples:**
```elixir
{:ok, {:text, "hello"}} = WebsockexNew.Frame.decode({:ws, :text, "hello"})
{:error, _} = WebsockexNew.Frame.decode({:unknown, "data"})
```

---

## WebsockexNew.Examples.DeribitAdapter

Example platform adapter for Deribit WebSocket API.

### Types

```elixir
@type t :: %__MODULE__{
  client: Client.t(),
  authenticated: boolean(),
  subscriptions: MapSet.t(),
  client_id: String.t() | nil,
  client_secret: String.t() | nil
}
```

### Functions

#### connect/1

```elixir
@spec connect(keyword()) :: {:ok, t()} | {:error, term()}
```

Connect to Deribit with optional authentication credentials.

**Examples:**
```elixir
{:ok, adapter} = WebsockexNew.Examples.DeribitAdapter.connect()
{:ok, adapter} = WebsockexNew.Examples.DeribitAdapter.connect(
  client_id: "your_id",
  client_secret: "your_secret"
)
```

#### authenticate/1

```elixir
@spec authenticate(t()) :: {:ok, t()} | {:error, term()}
```

Authenticate with Deribit using client credentials.

#### subscribe/2 & unsubscribe/2

```elixir
@spec subscribe(t(), list(String.t())) :: {:ok, t()} | {:error, term()}
@spec unsubscribe(t(), list(String.t())) :: {:ok, t()} | {:error, term()}
```

Manage Deribit channel subscriptions.

**Examples:**
```elixir
{:ok, adapter} = WebsockexNew.Examples.DeribitAdapter.subscribe(adapter, ["ticker.BTC-USD"])
{:ok, adapter} = WebsockexNew.Examples.DeribitAdapter.unsubscribe(adapter, ["ticker.BTC-USD"])
```

#### handle_message/1

```elixir
@spec handle_message(term()) :: :ok | {:response, binary()}
```

Handle Deribit-specific messages including heartbeats.

#### create_message_handler/1

```elixir
@spec create_message_handler(keyword()) :: function()
```

Create specialized message handler for Deribit connections.

**Examples:**
```elixir
handler = WebsockexNew.Examples.DeribitAdapter.create_message_handler(
  on_message: fn frame -> process_deribit_message(frame) end,
  on_heartbeat: fn response -> send_heartbeat_response(response) end
)
```