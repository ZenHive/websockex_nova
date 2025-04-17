defmodule WebsockexNova.Behaviors.MessageHandler do
  @moduledoc """
  Defines the behavior for handling WebSocket messages.

  The MessageHandler behavior defines how a WebSocket client should process
  incoming messages, validate them, determine their types, and encode outgoing
  messages. Implementing modules can customize message parsing, validation,
  and encoding based on platform-specific requirements.

  ## Callbacks

  * `handle_message/2` - Process an incoming message
  * `validate_message/1` - Validate message format and content
  * `message_type/1` - Extract or determine the message type
  * `encode_message/2` - Encode a message for sending
  """

  @typedoc """
  Message content - typically a decoded JSON map
  """
  @type message :: map() | binary()

  @typedoc """
  Handler state - can be any term
  """
  @type state :: term()

  @typedoc """
  Message type - can be any term that identifies message categories
  """
  @type message_type :: atom() | String.t() | {atom(), term()}

  @typedoc """
  Frame types that can be sent
  """
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
