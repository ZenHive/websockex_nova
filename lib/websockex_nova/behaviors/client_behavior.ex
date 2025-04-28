defmodule WebsockexNova.Behaviors.ClientBehavior do
  @moduledoc """
  Behavior defining the contract for WebSocket client operations.

  This behavior ensures a consistent API for WebSocket client operations across
  different implementations and enables proper mocking in tests.
  """

  alias WebsockexNova.ClientConn

  @doc """
  Connects to a WebSocket server using the specified adapter.
  """
  @callback connect(adapter :: module(), options :: map()) ::
              {:ok, ClientConn.t()} | {:error, term()}

  @doc """
  Sends a raw WebSocket frame.
  """
  @callback send_frame(conn :: ClientConn.t(), frame :: term()) ::
              :ok | {:error, term()}

  @doc """
  Sends a text message.
  """
  @callback send_text(conn :: ClientConn.t(), text :: String.t(), options :: map() | nil) ::
              {:ok, term()} | {:error, term()}

  @doc """
  Sends a JSON message.
  """
  @callback send_json(conn :: ClientConn.t(), data :: map(), options :: map() | nil) ::
              {:ok, term()} | {:error, term()}

  @doc """
  Subscribes to a channel or topic.
  """
  @callback subscribe(conn :: ClientConn.t(), channel :: String.t(), options :: map() | nil) ::
              {:ok, term()} | {:error, term()}

  @doc """
  Unsubscribes from a channel or topic.
  """
  @callback unsubscribe(conn :: ClientConn.t(), channel :: String.t(), options :: map() | nil) ::
              {:ok, term()} | {:error, term()}

  @doc """
  Authenticates with the WebSocket server.
  """
  @callback authenticate(conn :: ClientConn.t(), credentials :: map(), options :: map() | nil) ::
              {:ok, ClientConn.t(), term()} | {:error, term()} | {:error, term(), ClientConn.t()}

  @doc """
  Sends a ping message to the WebSocket server.
  """
  @callback ping(conn :: ClientConn.t(), options :: map() | nil) ::
              {:ok, :pong} | {:error, term()}

  @doc """
  Gets the current connection status.
  """
  @callback status(conn :: ClientConn.t(), options :: map() | nil) ::
              {:ok, atom()} | {:error, term()}

  @doc """
  Closes the WebSocket connection.
  """
  @callback close(conn :: ClientConn.t()) :: :ok

  @doc """
  Registers a process to receive notifications from the connection.
  """
  @callback register_callback(conn :: ClientConn.t(), pid :: pid()) ::
              {:ok, ClientConn.t()}

  @doc """
  Unregisters a process from receiving notifications.
  """
  @callback unregister_callback(conn :: ClientConn.t(), pid :: pid()) ::
              {:ok, ClientConn.t()}
end
