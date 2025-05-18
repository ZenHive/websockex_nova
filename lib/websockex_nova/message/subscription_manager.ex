defmodule WebsockexNova.Message.SubscriptionManager do
  @moduledoc """
  Manages WebSocket subscriptions with support for persistence and automatic resubscription.

  The SubscriptionManager provides a higher-level interface for working with subscriptions,
  delegating the actual subscription tracking to a `SubscriptionHandler` behavior implementation.
  It adds features like:

  * Centralized subscription management
  * Automatic resubscription after reconnection
  * Subscription state persistence
  * Helper functions for monitoring subscriptions

  ## Usage Example

  ```elixir
  alias WebsockexNova.Message.SubscriptionManager
  alias MyApp.Crypto.DeribitSubscriptionHandler

  # Initialize a subscription manager
  {:ok, manager} = SubscriptionManager.new(DeribitSubscriptionHandler)

  # Subscribe to channels
  {:ok, sub_id1, manager} = SubscriptionManager.subscribe(manager, "market.btcusd.trades", %{frequency: "100ms"})
  {:ok, sub_id2, manager} = SubscriptionManager.subscribe(manager, "market.btcusd.orderbook", %{depth: 10})

  # Handle subscription responses
  response = %{"type" => "subscribed", "id" => sub_id1}
  {:ok, manager} = SubscriptionManager.handle_response(manager, response)

  # When connection is lost, prepare for reconnection
  {:ok, manager} = SubscriptionManager.prepare_for_reconnect(manager)

  # After reconnection, resubscribe to channels
  results = SubscriptionManager.resubscribe_after_reconnect(manager)
  # Process results and get the updated manager
  [{:ok, new_sub_id1, manager} | _] = results

  # Check active subscriptions
  active = SubscriptionManager.active_subscriptions(manager)
  ```

  ## State Persistence

  To persist subscriptions across process restarts:

  ```elixir
  # Export state before process terminates
  state_to_save = SubscriptionManager.export_state(manager)

  # Later, when restarting:
  {:ok, manager} = SubscriptionManager.new(DeribitSubscriptionHandler)
  {:ok, restored_manager} = SubscriptionManager.import_state(manager, state_to_save)
  ```
  """

  alias WebsockexNova.Behaviors.SubscriptionHandler

  @type t :: %__MODULE__{
          handler: module(),
          state: map()
        }

  defstruct [:handler, state: %{}]

  @doc """
  Creates a new subscription manager with the specified handler module.

  ## Parameters

  * `handler_module` - Module that implements the `SubscriptionHandler` behavior
  * `initial_state` - Optional initial state for the handler (default: `%{}`)

  ## Returns

  * `{:ok, manager}` - A new subscription manager
  """
  @spec new(module(), map()) :: {:ok, t()}
  def new(handler_module, initial_state \\ %{}) do
    manager = %__MODULE__{
      handler: handler_module,
      state: initial_state
    }

    {:ok, manager}
  end

  @doc """
  Subscribes to a channel using the configured handler.

  ## Parameters

  * `manager` - The subscription manager
  * `channel` - The channel to subscribe to
  * `params` - Optional parameters for the subscription

  ## Returns

  * `{:ok, subscription_id, updated_manager}` - Successful subscription with ID
  * `{:error, reason, updated_manager}` - Failed to subscribe
  """
  @spec subscribe(t(), SubscriptionHandler.channel(), SubscriptionHandler.params()) ::
          {:ok, SubscriptionHandler.subscription_id(), t()}
          | {:error, term(), t()}
  def subscribe(%__MODULE__{} = manager, channel, params) do
    case manager.handler.subscribe(channel, params, manager.state) do
      {:ok, subscription_id, updated_state} ->
        updated_manager = %{manager | state: updated_state}
        {:ok, subscription_id, updated_manager}

      {:error, reason, updated_state} ->
        updated_manager = %{manager | state: updated_state}
        {:error, reason, updated_manager}
    end
  end

  @doc """
  Unsubscribes from a channel using the configured handler.

  ## Parameters

  * `manager` - The subscription manager
  * `subscription_id` - The ID of the subscription to remove

  ## Returns

  * `{:ok, updated_manager}` - Successfully unsubscribed
  * `{:error, reason, updated_manager}` - Failed to unsubscribe
  """
  @spec unsubscribe(t(), SubscriptionHandler.subscription_id()) ::
          {:ok, t()}
          | {:error, term(), t()}
  def unsubscribe(%__MODULE__{} = manager, subscription_id) do
    case manager.handler.unsubscribe(subscription_id, manager.state) do
      {:ok, updated_state} ->
        updated_manager = %{manager | state: updated_state}
        {:ok, updated_manager}

      {:error, reason, updated_state} ->
        updated_manager = %{manager | state: updated_state}
        {:error, reason, updated_manager}
    end
  end

  @doc """
  Processes a subscription-related response message.

  ## Parameters

  * `manager` - The subscription manager
  * `response` - The response message from the server

  ## Returns

  * `{:ok, updated_manager}` - Response processed successfully
  * `{:error, reason, updated_manager}` - Error in response
  """
  @spec handle_response(t(), SubscriptionHandler.subscription_response()) ::
          {:ok, t()}
          | {:error, term(), t()}
  def handle_response(%__MODULE__{} = manager, response) do
    case manager.handler.handle_subscription_response(response, manager.state) do
      {:ok, updated_state} ->
        updated_manager = %{manager | state: updated_state}
        {:ok, updated_manager}

      {:error, reason, updated_state} ->
        updated_manager = %{manager | state: updated_state}
        {:error, reason, updated_manager}
    end
  end

  @doc """
  Retrieves the active (confirmed) subscriptions.

  ## Parameters

  * `manager` - The subscription manager

  ## Returns

  * A map of subscription IDs to subscription details
  """
  @spec active_subscriptions(t()) :: %{SubscriptionHandler.subscription_id() => term()}
  def active_subscriptions(%__MODULE__{} = manager) do
    manager.handler.active_subscriptions(manager.state)
  end

  @doc """
  Finds a subscription ID by channel name.

  ## Parameters

  * `manager` - The subscription manager
  * `channel` - The channel name to look up

  ## Returns

  * The subscription ID if found, nil otherwise
  """
  @spec find_subscription_by_channel(t(), SubscriptionHandler.channel()) ::
          SubscriptionHandler.subscription_id() | nil
  def find_subscription_by_channel(%__MODULE__{} = manager, channel) do
    manager.handler.find_subscription_by_channel(channel, manager.state)
  end

  @doc """
  Prepares for reconnection by storing active subscriptions in state.

  This should be called before a reconnection attempt to ensure subscriptions can be
  restored after reconnection.

  ## Parameters

  * `manager` - The subscription manager

  ## Returns

  * `{:ok, updated_manager}` - Successfully prepared for reconnect
  """
  @spec prepare_for_reconnect(t()) :: {:ok, t()}
  def prepare_for_reconnect(%__MODULE__{} = manager) do
    # Get currently active subscriptions and store directly in state
    active = active_subscriptions(manager)

    # Store active subscriptions directly in state for recovery
    updated_state =
      Map.put(
        manager.state,
        :pending_reconnect_subscriptions,
        Enum.map(active, fn {_id, sub} -> {sub.channel, sub.params} end)
      )

    {:ok, %{manager | state: updated_state}}
  end

  @doc """
  Resubscribes to all stored subscriptions after a successful reconnect.

  This should be called after a successful reconnection to restore previously
  active subscriptions.

  ## Parameters

  * `manager` - The subscription manager with stored subscriptions

  ## Returns

  * A list of subscription results, each being `{:ok, subscription_id, updated_manager}`
    or `{:error, reason, updated_manager}`
  """
  @spec resubscribe_after_reconnect(t()) ::
          list(
            {:ok, SubscriptionHandler.subscription_id(), t()}
            | {:error, term(), t()}
          )
  def resubscribe_after_reconnect(%__MODULE__{} = manager) do
    # Get pending subscriptions from state
    pending = Map.get(manager.state, :pending_reconnect_subscriptions, [])

    # Clean up state by removing pending subscriptions
    cleaned_state = Map.delete(manager.state, :pending_reconnect_subscriptions)
    cleaned_manager = %{manager | state: cleaned_state}

    # Simple fold to process subscriptions and collect results
    pending
    |> Enum.reduce({[], cleaned_manager}, fn {channel, params}, {results, current_manager} ->
      case subscribe(current_manager, channel, params) do
        {:ok, id, updated_manager} ->
          {[{:ok, id, updated_manager} | results], updated_manager}

        {:error, reason, updated_manager} ->
          {[{:error, reason, updated_manager} | results], updated_manager}
      end
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  @doc """
  Exports the subscription state for persistence.

  This is useful for saving the state before a process terminates, so it can be
  restored later.

  ## Parameters

  * `manager` - The subscription manager

  ## Returns

  * A map containing the serializable state
  """
  @spec export_state(t()) :: map()
  def export_state(%__MODULE__{} = manager) do
    # Export only the parts needed for persistence
    %{
      subscriptions: get_in(manager.state, [:subscriptions]) || %{},
      pending_reconnect_subscriptions: Map.get(manager.state, :pending_reconnect_subscriptions, [])
    }
  end

  @doc """
  Imports previously exported subscription state.

  This is useful for restoring state after process restart.

  ## Parameters

  * `manager` - The subscription manager
  * `exported_state` - The state previously exported with `export_state/1`

  ## Returns

  * `{:ok, updated_manager}` - Successfully imported state
  """
  @spec import_state(t(), map()) :: {:ok, t()}
  def import_state(%__MODULE__{} = manager, exported_state) do
    # Store both subscriptions and pending reconnect subscriptions in state
    updated_state =
      manager.state
      |> Map.put(:subscriptions, exported_state.subscriptions)
      |> Map.put(
        :pending_reconnect_subscriptions,
        Map.get(exported_state, :pending_reconnect_subscriptions, [])
      )

    {:ok, %{manager | state: updated_state}}
  end
end
