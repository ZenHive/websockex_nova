defmodule WebsockexNova.Behaviors.SubscriptionHandler do
  @moduledoc """
  Behaviour for managing WebSocket channel subscriptions and topics.

  The SubscriptionHandler provides a consistent interface for managing subscriptions
  across different WebSocket services. It handles subscription lifecycle, tracking,
  and response processing, allowing platform-specific implementations while
  maintaining a standard API.

  ## Architecture

  SubscriptionHandler is responsible for:
  - Tracking active subscriptions by channel/topic and ID
  - Managing subscription lifecycle (subscribe, unsubscribe)
  - Processing subscription-related responses from the server
  - Building subscription and unsubscription messages
  - Handling subscription errors and recovery

  The handler maintains its state as a map, typically containing subscription
  mappings and metadata.

  ## Callback Flow

  1. `subscription_init/1` - Initialize subscription tracking state
  2. `subscribe/3` - Track new subscription request
  3. `handle_subscription/4` - Format and send subscription message
  4. `handle_subscription_response/2` - Process server's subscription response
  5. `unsubscribe/2` - Track unsubscription request
  6. `handle_unsubscription/3` - Format and send unsubscription message
  7. `handle_unsubscription_response/2` - Process server's unsubscription response
  8. `handle_subscription_message/3` - Process incoming subscription data

  ## Implementation Example

      defmodule MyApp.CustomSubscriptionHandler do
        @behaviour WebsockexNova.Behaviors.SubscriptionHandler
        alias WebsockexNova.Message.SubscriptionManager
        require Logger

        @impl true
        def subscription_init(opts) do
          state = %{
            subscriptions: %{},           # channel -> subscription_id mapping
            subscription_manager: SubscriptionManager.new(),
            pending_subscriptions: %{},   # track pending requests
            subscription_timeout: opts[:subscription_timeout] || 5_000
          }
          {:ok, state}
        end

        @impl true
        def subscribe(channel, params, state) do
          # Generate unique subscription ID
          subscription_id = generate_subscription_id(channel, params)
          
          # Track the subscription
          updated_subs = Map.put(state.subscriptions, channel, subscription_id)
          updated_pending = Map.put(state.pending_subscriptions, subscription_id, %{
            channel: channel,
            params: params,
            timestamp: System.system_time(:millisecond)
          })
          
          updated_state = state
          |> Map.put(:subscriptions, updated_subs)
          |> Map.put(:pending_subscriptions, updated_pending)
          
          {:ok, subscription_id, updated_state}
        end

        @impl true
        def handle_subscription(channel, params, conn, state) do
          # Format subscription message for this service
          subscribe_msg = %{
            type: "subscribe",
            channel: channel,
            params: params || %{},
            id: Map.get(state.subscriptions, channel)
          }
          
          case WebsockexNova.Client.send_json(conn, subscribe_msg) do
            {:ok, _} ->
              # Update subscription manager
              manager = state.subscription_manager
              updated_manager = SubscriptionManager.add_subscription(manager, channel, params)
              updated_state = Map.put(state, :subscription_manager, updated_manager)
              {:ok, %{}, updated_state}
            
            error ->
              # Clean up failed subscription
              updated_state = cleanup_failed_subscription(state, channel)
              {:error, error, updated_state}
          end
        end

        @impl true
        def handle_subscription_response(response, state) do
          # Process server's subscription confirmation
          case response do
            %{"type" => "subscribed", "channel" => channel, "id" => sub_id} ->
              # Move from pending to active
              updated_pending = Map.delete(state.pending_subscriptions, sub_id)
              updated_state = Map.put(state, :pending_subscriptions, updated_pending)
              {:ok, updated_state}
            
            %{"type" => "subscription_error", "channel" => channel, "error" => error_msg} ->
              # Handle subscription failure
              updated_state = cleanup_failed_subscription(state, channel)
              Logger.error("Subscription failed for \\\#{channel}: \\\#{inspect(error_msg)}")
              {:ok, updated_state}
            
            _ ->
              # Unknown response format
              {:ok, state}
          end
        end

        @impl true
        def unsubscribe(subscription_id, state) do
          # Find channel for this subscription ID
          channel = find_channel_by_subscription_id(state.subscriptions, subscription_id)
          
          if channel do
            updated_subs = Map.delete(state.subscriptions, channel)
            updated_state = Map.put(state, :subscriptions, updated_subs)
            {:ok, updated_state}
          else
            {:error, :subscription_not_found, state}
          end
        end

        @impl true
        def handle_unsubscription(subscription_id, conn, state) do
          # Format unsubscription message
          unsubscribe_msg = %{
            type: "unsubscribe",
            id: subscription_id
          }
          
          case WebsockexNova.Client.send_json(conn, unsubscribe_msg) do
            {:ok, _} ->
              # Update subscription manager
              channel = find_channel_by_subscription_id(state.subscriptions, subscription_id)
              if channel do
                manager = state.subscription_manager
                updated_manager = SubscriptionManager.remove_subscription(manager, channel)
                updated_state = Map.put(state, :subscription_manager, updated_manager)
                {:ok, updated_state}
              else
                {:ok, state}
              end
            
            error ->
              {:error, error, state}
          end
        end

        @impl true
        def handle_unsubscription_response(response, state) do
          # Process server's unsubscription confirmation
          case response do
            %{"type" => "unsubscribed", "id" => sub_id} ->
              # Confirmation received, already cleaned up
              {:ok, state}
            
            _ ->
              {:ok, state}
          end
        end

        @impl true
        def handle_subscription_message(channel, message, state) do
          # Process incoming data for a subscribed channel
          # Could include filtering, transformation, or routing
          processed_message = process_channel_message(channel, message)
          {:ok, processed_message, state}
        end

        # Private helpers

        defp generate_subscription_id(channel, params) do
          # Generate deterministic ID based on channel and params
          \"\\\#{channel}_\\\#{:erlang.phash2({channel, params})}\"
        end

        defp find_channel_by_subscription_id(subscriptions, sub_id) do
          Enum.find_value(subscriptions, fn {channel, id} ->
            if id == sub_id, do: channel
          end)
        end

        defp cleanup_failed_subscription(state, channel) do
          sub_id = Map.get(state.subscriptions, channel)
          
          state
          |> Map.update(:subscriptions, %{}, &Map.delete(&1, channel))
          |> Map.update(:pending_subscriptions, %{}, &Map.delete(&1, sub_id))
        end

        defp process_channel_message(channel, message) do
          # Add channel metadata or transform message
          Map.put(message, :_channel, channel)
        end
      end

  ## Channel and Parameter Structures

  - **Channel**: Typically a string identifying the data stream
    - Examples: `"ticker.BTC-USD"`, `"orderbook.ETH-USD"`, `"trades.*"`
    - Can be hierarchical: `"market.spot.ticker"`
    - May support wildcards: `"trades.*"` or `"market.*.ticker"`

  - **Params**: Additional subscription options as a map
    - Examples: `%{depth: 10}`, `%{interval: "1m"}`, `%{symbols: ["BTC", "ETH"]}`
    - Service-specific: each platform defines its own parameter structure

  ## Subscription Response Types

  Common response patterns:
  - Confirmation: `%{"type" => "subscribed", "channel" => "...", "id" => "..."}`
  - Error: `%{"type" => "error", "message" => "...", "channel" => "..."}`
  - Data: `%{"channel" => "...", "data" => %{...}, "timestamp" => ...}`
  - Unsubscribe confirmation: `%{"type" => "unsubscribed", "id" => "..."}`

  ## Integration with WebsockexNova.Client

  The SubscriptionHandler works with Client functions:
  - `WebsockexNova.Client.subscribe/3` calls the handler's callbacks
  - `WebsockexNova.Client.unsubscribe/2` manages unsubscription
  - Messages are routed through `handle_subscription_message/3`

  ## Tips

  1. Use a subscription manager (like `SubscriptionManager`) for complex tracking
  2. Implement timeout handling for pending subscriptions
  3. Consider subscription deduplication for identical requests
  4. Handle reconnection by resubscribing to all active channels
  5. Log subscription events for debugging
  6. Validate channel names and parameters before subscribing

  See `WebsockexNova.Defaults.DefaultSubscriptionHandler` for a reference implementation.
  """

  @typedoc "Handler state"
  @type state :: map()

  @typedoc "Subscription ID"
  @type subscription_id :: term()

  @typedoc "Channel name or topic"
  @type channel :: String.t() | atom()

  @typedoc "Subscription parameters"
  @type params :: map()

  @typedoc "Subscription response"
  @type subscription_response :: map()

  @doc """
  Initialize the handler's state.
  """
  @callback subscription_init(opts :: term()) :: {:ok, state} | {:error, term()}

  @doc """
  Track a new subscription to a channel or topic.
  Returns:
    - `{:ok, subscription_id, state}`
    - `{:error, reason, state}`
  """
  @callback subscribe(channel, params, state) ::
              {:ok, subscription_id, state}
              | {:error, term(), state}

  @doc """
  Remove an existing subscription.
  Returns:
    - `{:ok, state}`
    - `{:error, reason, state}`
  """
  @callback unsubscribe(subscription_id, state) ::
              {:ok, state}
              | {:error, term(), state}

  @doc """
  Process a subscription-related response.
  Returns:
    - `{:ok, state}`
    - `{:error, reason, state}`
  """
  @callback handle_subscription_response(subscription_response, state) ::
              {:ok, state}
              | {:error, term(), state}

  @doc """
  Get all active subscriptions.
  Returns:
    - A map of subscription IDs to subscription details
  """
  @callback active_subscriptions(state) :: %{subscription_id => term()}

  @doc """
  Find a subscription ID by channel name.
  Returns:
    - The subscription ID if found, nil otherwise
  """
  @callback find_subscription_by_channel(channel, state) :: subscription_id | nil
end
