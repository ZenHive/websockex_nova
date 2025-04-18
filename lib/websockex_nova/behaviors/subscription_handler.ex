defmodule WebsockexNova.Behaviors.SubscriptionHandler do
  @moduledoc """
  Defines the behavior for managing WebSocket channel subscriptions.

  The SubscriptionHandler behavior is part of WebsockexNova's thin adapter architecture,
  allowing client applications to manage subscriptions to channels or topics while
  maintaining a clean separation from transport concerns.

  ## Thin Adapter Pattern

  As part of the thin adapter architecture:

  1. This behavior focuses exclusively on subscription management
  2. The connection layer delegates subscription handling responsibilities to implementations
  3. Your implementation can track subscriptions, handle responses, and manage state
  4. The adapter handles the actual message sending and receiving

  ## Delegation Flow

  The subscription handling delegation flow works as follows:

  1. Application code requests a subscription to a channel or topic
  2. Your `subscribe/3` callback is invoked to track the subscription
  3. The connection layer sends the actual subscription message
  4. Responses are routed to your `handle_subscription_response/2` callback
  5. Subscription state is managed internally by your implementation

  ## Implementation Example

  ```elixir
  defmodule MyApp.CryptoSubscriptionHandler do
    @behaviour WebsockexNova.Behaviors.SubscriptionHandler

    @impl true
    def subscribe(channel, params, state) do
      subscription_id = "sub_" <> UUID.uuid4()

      # Track the subscription in state
      subscriptions = Map.get(state, :subscriptions, %{})
      updated_subscriptions = Map.put(subscriptions, subscription_id, %{
        channel: channel,
        params: params,
        status: :pending,
        timestamp: System.system_time(:second)
      })

      updated_state = Map.put(state, :subscriptions, updated_subscriptions)

      # Return the subscription ID and updated state
      {:ok, subscription_id, updated_state}
    end

    @impl true
    def unsubscribe(subscription_id, state) do
      case get_in(state, [:subscriptions, subscription_id]) do
        nil ->
          {:error, :subscription_not_found, state}

        _subscription ->
          # Remove the subscription from state
          updated_state = update_in(state, [:subscriptions], &Map.delete(&1, subscription_id))
          {:ok, updated_state}
      end
    end

    @impl true
    def handle_subscription_response(%{"type" => "subscribed", "channel" => channel, "id" => id}, state) do
      # Mark the subscription as confirmed
      updated_state = update_in(state, [:subscriptions, id], fn subscription ->
        if subscription do
          Map.put(subscription, :status, :confirmed)
        else
          subscription
        end
      end)

      {:ok, updated_state}
    end

    @impl true
    def handle_subscription_response(%{"type" => "error", "channel" => channel, "id" => id, "reason" => reason}, state) do
      # Mark the subscription as failed
      updated_state = update_in(state, [:subscriptions, id], fn subscription ->
        if subscription do
          subscription
          |> Map.put(:status, :failed)
          |> Map.put(:error, reason)
        else
          subscription
        end
      end)

      {:error, reason, updated_state}
    end

    @impl true
    def handle_subscription_response(_response, state) do
      # Ignore other messages
      {:ok, state}
    end

    @impl true
    def active_subscriptions(state) do
      state
      |> Map.get(:subscriptions, %{})
      |> Enum.filter(fn {_id, sub} -> sub.status == :confirmed end)
      |> Map.new()
    end

    @impl true
    def find_subscription_by_channel(channel, state) do
      state
      |> Map.get(:subscriptions, %{})
      |> Enum.find_value(nil, fn {id, sub} ->
        if sub.channel == channel, do: id, else: nil
      end)
    end
  end
  ```

  ## Callbacks

  * `subscribe/3` - Track a new subscription
  * `unsubscribe/2` - Remove an existing subscription
  * `handle_subscription_response/2` - Process subscription-related messages
  * `active_subscriptions/1` - Get current active subscriptions
  * `find_subscription_by_channel/2` - Look up subscription by channel name
  """

  @typedoc """
  Channel or topic identifier
  """
  @type channel :: String.t() | atom() | {atom(), term()}

  @typedoc """
  Subscription parameters (e.g., frequency, depth, filters)
  """
  @type params :: map() | Keyword.t() | nil

  @typedoc """
  Unique identifier for a subscription
  """
  @type subscription_id :: String.t()

  @typedoc """
  Subscription response message
  """
  @type subscription_response :: map() | term()

  @typedoc """
  Handler state - can be any term
  """
  @type state :: term()

  @typedoc """
  Return values for subscribe callback

  * `{:ok, subscription_id, new_state}` - Subscription tracked successfully
  * `{:error, reason, state}` - Failed to track subscription
  """
  @type subscribe_return ::
          {:ok, subscription_id(), state()}
          | {:error, term(), state()}

  @typedoc """
  Return values for unsubscribe callback

  * `{:ok, new_state}` - Subscription removed successfully
  * `{:error, reason, state}` - Failed to remove subscription
  """
  @type unsubscribe_return ::
          {:ok, state()}
          | {:error, term(), state()}

  @typedoc """
  Return values for handling subscription responses

  * `{:ok, new_state}` - Response processed successfully
  * `{:error, reason, new_state}` - Error processing response
  """
  @type handle_response_return ::
          {:ok, state()}
          | {:error, term(), state()}

  @doc """
  Track a new subscription to a channel or topic.

  Called when initiating a subscription to a channel or topic.

  ## Parameters

  * `channel` - The channel or topic to subscribe to
  * `params` - Optional parameters for the subscription
  * `state` - Current handler state

  ## Returns

  * `{:ok, subscription_id, new_state}` - Subscription tracked successfully
  * `{:error, reason, state}` - Failed to track subscription
  """
  @callback subscribe(channel(), params(), state()) :: subscribe_return()

  @doc """
  Remove an existing subscription.

  Called when unsubscribing from a channel or topic.

  ## Parameters

  * `subscription_id` - The ID of the subscription to remove
  * `state` - Current handler state

  ## Returns

  * `{:ok, new_state}` - Subscription removed successfully
  * `{:error, reason, state}` - Failed to remove subscription
  """
  @callback unsubscribe(subscription_id(), state()) :: unsubscribe_return()

  @doc """
  Process a subscription-related response.

  Called when a subscription-related message is received.

  ## Parameters

  * `response` - The subscription response message
  * `state` - Current handler state

  ## Returns

  * `{:ok, new_state}` - Response processed successfully
  * `{:error, reason, new_state}` - Error processing response
  """
  @callback handle_subscription_response(subscription_response(), state()) :: handle_response_return()

  @doc """
  Get all active subscriptions.

  Called to retrieve the current active subscriptions.

  ## Parameters

  * `state` - Current handler state

  ## Returns

  * A map of subscription IDs to subscription details
  """
  @callback active_subscriptions(state()) :: %{subscription_id() => term()}

  @doc """
  Find a subscription ID by channel name.

  Called to look up a subscription ID based on the channel name.

  ## Parameters

  * `channel` - The channel to look up
  * `state` - Current handler state

  ## Returns

  * The subscription ID if found, nil otherwise
  """
  @callback find_subscription_by_channel(channel(), state()) :: subscription_id() | nil
end
