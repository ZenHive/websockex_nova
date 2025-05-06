defmodule WebsockexNova.Defaults.DefaultMessageHandler do
  @moduledoc """
  Default implementation of the MessageHandler behavior.

  This module provides sensible default implementations for all MessageHandler
  callbacks, including:

  * JSON message parsing and validation
  * Message type detection from common fields
  * JSON encoding for outbound messages
  * Basic subscription tracking

  ## Usage

  You can use this module directly or as a starting point for your own implementation:

      defmodule MyApp.CustomMessageHandler do
        use WebsockexNova.Defaults.DefaultMessageHandler

        # Override specific callbacks as needed
        def message_type(message) do
          # Custom message type detection
          Map.get(message, "custom_type", :unknown)
        end
      end

  ## Features

  * Automatically parses JSON text messages
  * Tracks message processing count
  * Handles common subscription responses
  * Provides standardized error handling
  """

  @behaviour WebsockexNova.Behaviours.MessageHandler

  @allowed_types Enum.map(~w(subscription ping pong error info data), &String.to_atom/1)
  @allowed_methods Enum.map(~w(subscribe unsubscribe publish), &String.to_atom/1)
  @allowed_actions Enum.map(~w(join leave update ping), &String.to_atom/1)
  @allowed_statuses Enum.map(~w(subscribed unsubscribed), &String.to_atom/1)

  @impl true
  def message_init(opts \\ %{}) do
    opts_map = Map.new(opts)
    # Split known fields and custom fields
    known_keys = MapSet.new(Map.keys(%WebsockexNova.ClientConn{}))
    {known, custom} = Enum.split_with(opts_map, fn {k, _v} -> MapSet.member?(known_keys, k) end)
    known_map = Map.new(known)
    custom_map = Map.new(custom)
    conn = struct(WebsockexNova.ClientConn, known_map)

    conn = %{
      conn
      | message_handler_settings: Map.merge(conn.message_handler_settings || %{}, custom_map),
        processed_count: Map.get(opts_map, :processed_count, 0),
        subscriptions: Map.get(opts_map, :subscriptions, %{})
    }

    {:ok, conn}
  end

  @impl true
  def handle_message(message, state) when is_map(message) and is_map(state) do
    case message do
      %{"type" => "error"} = error_msg ->
        # Handle error messages
        error_message = Map.get(error_msg, "message", "Unknown error")
        updated_state = Map.put(state, :last_error, error_msg)
        {:error, error_message, updated_state}

      %{"type" => "subscription"} = subscription_msg ->
        # Track subscription status
        handle_subscription_message(subscription_msg, state)

      _ ->
        # Handle general messages
        processed_count = Map.get(state, :processed_count, 0)

        updated_state =
          state
          |> Map.put(:processed_count, processed_count + 1)
          |> Map.put(:last_message, message)

        {:ok, updated_state}
    end
  end

  # Fallback for any non-map messages
  @impl true
  def handle_message(message, state) when is_binary(message) and is_map(state) do
    # Store the raw binary in the state directly rather than trying to convert
    # This helps preserve binary data that isn't meant to be parsed
    processed_count = Map.get(state, :processed_count, 0)

    updated_state =
      state
      |> Map.put(:processed_count, processed_count + 1)
      |> Map.put(:last_binary_message, message)

    {:ok, updated_state}
  end

  # Original fallback for any other non-map messages
  @impl true
  def handle_message(message, state) when is_map(state) do
    # Convert to map for consistent handling
    {:ok, processed_message} = validate_message(message)
    handle_message(processed_message, state)
  end

  @impl true
  def validate_message(message) when is_map(message) do
    # Already a map, just pass through
    {:ok, message}
  end

  @impl true
  def validate_message(message) when is_binary(message) do
    # Try to determine if this is JSON or binary data
    cond do
      # If it's clearly a JSON string (starts with { or [), try to parse it
      String.valid?(message) &&
          (String.starts_with?(message, "{") || String.starts_with?(message, "[")) ->
        case Jason.decode(message) do
          {:ok, decoded} ->
            {:ok, decoded}

          {:error, _} ->
            # Failed to parse as JSON, treat as binary data
            {:ok, %{"content" => message, "type" => "binary_data"}}
        end

      # If it's valid text but not JSON, treat as binary data
      String.valid?(message) ->
        {:ok, %{"content" => message, "type" => "binary_data"}}

      # Otherwise it's non-text binary data, preserve as binary data
      true ->
        {:ok, %{"content" => message, "type" => "binary_data"}}
    end
  end

  @impl true
  def validate_message(message) do
    # Any other format, stringify and wrap in a structured map
    {:ok, %{"content" => inspect(message), "type" => "binary_data"}}
  end

  @impl true
  def message_type(%{"type" => type}) when is_binary(type) do
    safe_to_atom(type, @allowed_types, :unknown)
  end

  @impl true
  def message_type(%{"method" => method}) when is_binary(method) do
    safe_to_atom(method, @allowed_methods, :unknown)
  end

  @impl true
  def message_type(%{"action" => action}) when is_binary(action) do
    safe_to_atom(action, @allowed_actions, :unknown)
  end

  @impl true
  def message_type(message) when is_map(message) do
    # Unknown message type
    :unknown
  end

  @impl true
  def message_type(_) do
    # Fallback for non-map values
    :unknown
  end

  @impl true
  def encode_message(message, state) when is_map(message) and is_map(state) do
    # Encode maps as JSON
    case Jason.encode(message) do
      {:ok, json} ->
        {:ok, :text, json}

      {:error, reason} ->
        {:error, {:json_encode_failed, reason}}
    end
  end

  @impl true
  def encode_message(message, state) when is_binary(message) and is_map(state) do
    # For backward compatibility, handle a raw binary as a message
    # But convert it to a map first for consistency
    encode_message(%{"content" => message, "type" => "raw_data"}, state)
  end

  @impl true
  def encode_message({frame_type, binary_data}, state)
      when is_binary(binary_data) and frame_type in [:text, :binary] and is_map(state) do
    # Direct pass-through for pre-formatted binary data with specified frame type
    {:ok, frame_type, binary_data}
  end

  @impl true
  def encode_message(:ping, state) when is_map(state) do
    # Special handling for ping message
    encode_message(%{type: "ping"}, state)
  end

  @impl true
  def encode_message(message, state) when is_atom(message) and is_map(state) do
    # Handle atom messages by converting to a type field
    encode_message(%{type: to_string(message)}, state)
  end

  # Attempt to encode any other term
  @impl true
  def encode_message(message, state) when is_map(state) do
    # Ensure any other message type is converted to a map
    encode_message(%{content: inspect(message), type: "encoded_term"}, state)
  rescue
    e -> {:error, {:encode_failed, e}}
  end

  # Private helper functions

  defp handle_subscription_message(message, state) do
    # Extract channel and status information
    channel = Map.get(message, "channel")

    status =
      message
      |> Map.get("status", "unknown")
      |> safe_to_atom(@allowed_statuses, :unknown)

    # Update subscriptions in state
    subscriptions = Map.get(state, :subscriptions, %{})
    updated_subscriptions = Map.put(subscriptions, channel, status)
    updated_state = Map.put(state, :subscriptions, updated_subscriptions)

    {:ok, updated_state}
  end

  defp safe_to_atom(string, allowed_atoms, fallback) when is_binary(string) do
    atom =
      try do
        String.to_existing_atom(string)
      rescue
        ArgumentError -> nil
      end

    if atom in allowed_atoms, do: atom, else: fallback
  end
end
