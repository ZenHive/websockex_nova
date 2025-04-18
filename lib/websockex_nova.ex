defmodule WebsockexNova do
  @moduledoc """
  WebsockexNova is a robust WebSocket client library for Elixir.

  ## Thin Adapter Architecture

  WebsockexNova uses a "thin adapter" architectural pattern that:

  1. Provides a standardized API over the underlying Gun WebSocket implementation
  2. Minimizes logic in the adapter layers, delegating business logic to specialized modules
  3. Maintains full access to the underlying transport's capabilities
  4. Uses clean delegation patterns to separate concerns

  This architecture allows WebsockexNova to be both flexible and maintainable, with the
  possibility of supporting different transport layers in the future.

  ## Delegation Pattern and Ownership Model

  WebsockexNova employs a multi-level delegation pattern:

  1. **Adapter Layer**: Routes messages from the transport (Gun) to appropriate handlers
  2. **Manager Layer**: Contains business logic for handling connection lifecycle
  3. **Behavior Layer**: Defines interfaces that client applications implement
  4. **Handlers Layer**: Contains specialized handlers for different message types

  The ownership model carefully manages WebSocket connections, ensuring that:

  - Only one process receives messages from a connection
  - Ownership can be transferred between processes with a well-defined protocol
  - Monitoring and cleanup are handled correctly when processes terminate

  ## Common Usage Patterns

  ### Basic Connection

  ```elixir
  # Define a simple client module
  defmodule MyApp.SimpleClient do
    use WebsockexNova.Client

    def handle_connect(_conn, state) do
      {:ok, state}
    end

    def handle_frame({:text, message}, _conn, state) do
      IO.puts("Received message: \#{message}")
      {:ok, state}
    end

    def handle_disconnect(reason, state) do
      {:reconnect, state}
    end
  end

  # Connect and send a message
  {:ok, client} = MyApp.SimpleClient.start_link("wss://echo.websocket.org")
  MyApp.SimpleClient.send_frame(client, {:text, "Hello"})
  ```

  ### With Custom Handlers

  ```elixir
  # Start with custom handlers
  {:ok, client} = WebsockexNova.Connection.start_link(
    "wss://echo.websocket.org",
    connection_handler: MyApp.ConnectionHandler,
    message_handler: MyApp.MessageHandler,
    error_handler: MyApp.ErrorHandler
  )
  ```

  ### Ownership Transfer

  ```elixir
  # Transfer connection ownership to another process
  WebsockexNova.Connection.transfer_ownership(client, target_pid)

  # In the target process
  WebsockexNova.Connection.receive_ownership(wrapper_pid, gun_pid)
  ```
  """
end
