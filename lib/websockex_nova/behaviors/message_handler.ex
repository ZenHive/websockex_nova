defmodule WebsockexNova.Behaviors.MessageHandler do
  @moduledoc """
  Defines the behavior for handling WebSocket messages.

  The MessageHandler behavior is part of WebsockexNova's thin adapter architecture,
  allowing client applications to customize message processing while maintaining a
  clean separation from transport concerns.

  ## Thin Adapter Pattern

  As part of the thin adapter architecture:

  1. This behavior focuses exclusively on message processing logic
  2. The connection layer delegates message handling responsibilities to implementations
  3. Your implementation can use domain-specific message types and validation rules
  4. The adapter handles encoding/decoding between your domain types and the wire format

  ## Delegation Flow

  The message handling delegation flow works as follows:

  1. Raw frames are received by the connection handler
  2. Text/binary frames are passed to your `handle_message/2` callback
  3. Your implementation processes the message according to your application's needs
  4. If you need to send a response, the adapter handles the encoding back to wire format

  ## Implementation Example

  ```elixir
  defmodule MyApp.ChatMessageHandler do
    @behaviour WebsockexNova.Behaviors.MessageHandler

    @impl true
    def handle_message(%{"type" => "chat_message", "text" => text, "user" => user}, state) do
      # Process a chat message
      IO.puts("\#{user}: \#{text}")

      # Send an acknowledgment
      {:reply, {:ack, %{message_id: state.last_message_id}}, state}
    end

    @impl true
    def handle_message(%{"type" => "presence_update", "user" => user, "status" => status}, state) do
      # Process a presence update
      new_state = update_in(state.users[user], fn _ -> status end)
      {:ok, new_state}
    end

    @impl true
    def validate_message(message) when is_map(message) and map_size(message) > 0 do
      # Validate that message has a type field
      case Map.has_key?(message, "type") do
        true -> {:ok, message}
        false -> {:error, :missing_type_field, message}
      end
    end

    @impl true
    def validate_message(message) do
      {:error, :invalid_message_format, message}
    end

    @impl true
    def message_type(%{"type" => type}) when is_binary(type) do
      String.to_atom(type)
    end

    @impl true
    def message_type(_message) do
      :unknown
    end

    @impl true
    def encode_message({:ack, %{message_id: id}}, _state) do
      json = Jason.encode!(%{type: "ack", message_id: id})
      {:ok, :text, json}
    end

    @impl true
    def encode_message({:error, reason}, _state) do
      json = Jason.encode!(%{type: "error", reason: reason})
      {:ok, :text, json}
    end
  end
  ```

  ## Callbacks

  * `message_init/1` - Initialize the handler's state
  * `handle_message/2` - Process an incoming message
  * `validate_message/1` - Validate message format and content
  * `message_type/1` - Extract or determine the message type
  * `encode_message/2` - Encode a message for sending
  """

  @typedoc "Handler state"
  @type state :: map()

  @typedoc "Message content"
  @type message :: map() | binary()

  @typedoc "Message type"
  @type message_type :: atom() | String.t() | {atom(), term()}

  @typedoc "Frame type"
  @type frame_type :: :text | :binary | :ping | :pong | :close

  @typedoc """
  Return values for message handling callbacks

  * `{:ok, new_state}` - Continue with the updated state
  * `{:reply, message_type, new_state}` - Send a message and continue
  * `{:reply_many, [message_type], new_state}` - Send multiple messages
  * `{:close, code, reason, new_state}` - Close the connection
  * `{:error, reason, new_state}` - Error occurred during processing
  """
  @type handler_return ::
          {:ok, state()}
          | {:reply, message_type(), state()}
          | {:reply_many, [message_type()], state()}
          | {:close, integer(), String.t(), state()}
          | {:error, term(), state()}

  @typedoc """
  Return values for message validation

  * `{:ok, message}` - Message is valid, possibly normalized
  * `{:error, reason, message}` - Message is invalid with reason
  """
  @type validate_return ::
          {:ok, message()}
          | {:error, term(), message()}

  @typedoc """
  Return values for message encoding

  * `{:ok, frame_type, data}` - Successfully encoded message
  * `{:error, reason}` - Failed to encode message
  """
  @type encode_return ::
          {:ok, frame_type(), binary()}
          | {:error, term()}

  @doc """
  Initialize the handler's state.

  Called when the message handler is started. The return value becomes the initial state.

  ## Parameters

  * `opts` - The options passed to the handler

  ## Returns

  * `{:ok, state}` - The initialized state
  * `{:error, reason}` - Initialization failed
  """
  @callback message_init(opts :: term()) :: {:ok, state()} | {:error, term()}

  @doc """
  Process an incoming message.

  Called when a message is received from the server.

  ## Parameters

  * `message` - The parsed message (typically a map from decoded JSON)
  * `state` - Current handler state

  ## Returns

  * `{:ok, new_state}` - Continue with the updated state
  * `{:reply, message_type, new_state}` - Send a message and continue
  * `{:reply_many, [message_type], new_state}` - Send multiple messages
  * `{:close, code, reason, new_state}` - Close the connection
  * `{:error, reason, new_state}` - Error occurred during processing
  """
  @callback handle_message(message(), state()) :: handler_return()

  @doc """
  Validate an incoming message.

  Called to validate the format and content of a message.

  ## Parameters

  * `message` - The message to validate

  ## Returns

  * `{:ok, message}` - Message is valid, possibly normalized
  * `{:error, reason, message}` - Message is invalid with reason
  """
  @callback validate_message(message()) :: validate_return()

  @doc """
  Determine the type of a message.

  Called to extract or determine the type/category of a message.

  ## Parameters

  * `message` - The message to analyze

  ## Returns

  * The message type (atom, string, or tuple)
  """
  @callback message_type(message()) :: message_type()

  @doc """
  Encode a message for sending.

  Called to convert a message into a WebSocket frame.

  ## Parameters

  * `message_type` - The type of message to encode
  * `state` - Current handler state

  ## Returns

  * `{:ok, frame_type, data}` - Successfully encoded message
  * `{:error, reason}` - Failed to encode message
  """
  @callback encode_message(message_type(), state()) :: encode_return()
end
