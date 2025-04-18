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

  @behaviour WebsockexNova.Behaviors.MessageHandler

  @impl true
  def handle_message(%{"type" => "error"} = message, state) do
    # Handle error messages
    error_message = Map.get(message, "message", "Unknown error")
    state = Map.put(state, :last_error, message)

    {:error, error_message, state}
  end

  def handle_message(%{"type" => "subscription"} = message, state) do
    # Track subscription status
    channel = Map.get(message, "channel")
    status = message |> Map.get("status", "unknown") |> String.to_atom()

    subscriptions = Map.get(state, :subscriptions, %{})
    subscriptions = Map.put(subscriptions, channel, status)

    state = Map.put(state, :subscriptions, subscriptions)

    {:ok, state}
  end

  def handle_message(message, state) do
    # Handle general messages
    processed_count = Map.get(state, :processed_count, 0)

    state =
      state
      |> Map.put(:processed_count, processed_count + 1)
      |> Map.put(:last_message, message)

    {:ok, state}
  end

  @impl true
  def validate_message(message) when is_map(message) do
    # Already parsed message
    {:ok, message}
  end

  def validate_message(message) when is_binary(message) do
    if String.valid?(message) && String.starts_with?(message, "{") do
      # Attempt to parse as JSON
      case Jason.decode(message) do
        {:ok, decoded} ->
          {:ok, decoded}

        {:error, _} ->
          {:error, :invalid_json, message}
      end
    else
      # Treat as binary data
      {:ok, message}
    end
  end

  def validate_message(message) do
    # Any other format, pass through
    {:ok, message}
  end

  @impl true
  def message_type(%{"type" => type}) when is_binary(type) do
    # Extract from type field
    String.to_atom(type)
  end

  def message_type(%{"method" => method}) when is_binary(method) do
    # Extract from method field if no type
    String.to_atom(method)
  end

  def message_type(%{"action" => action}) when is_binary(action) do
    # Extract from action field if no type or method
    String.to_atom(action)
  end

  def message_type(message) when is_map(message) do
    # Unknown message type
    :unknown
  end

  def message_type(binary_message) when is_binary(binary_message) do
    # Binary message
    :binary
  end

  def message_type(_) do
    # Fallback
    :unknown
  end

  @impl true
  def encode_message(message, _state) when is_binary(message) do
    # Binary data passes through as binary frame
    {:ok, :binary, message}
  end

  def encode_message(message, _state) when is_map(message) do
    # Encode maps as JSON
    case Jason.encode(message) do
      {:ok, json} ->
        {:ok, :text, json}

      {:error, reason} ->
        {:error, {:json_encode_failed, reason}}
    end
  end

  def encode_message(:ping, _state) do
    # Special handling for ping message
    {:ok, :text, Jason.encode!(%{type: "ping"})}
  end

  # Attempt to encode any other term
  def encode_message(message, _state) do
    encoded = Jason.encode!(%{type: to_string(message)})
    {:ok, :text, encoded}
  rescue
    e -> {:error, {:encode_failed, e}}
  end
end
