defmodule WebsockexNova.Defaults.DefaultSubscriptionHandler do
  @moduledoc """
  Default implementation of the SubscriptionHandler behavior.

  This module provides a standard implementation of subscription management
  with reasonable defaults. It supports:

  * Simple subscription tracking with status management
  * Channel-based subscription lookup
  * Standard handling of subscription responses
  * Automatic confirmation management
  * Subscription timeout detection and cleanup
  * Detailed status tracking

  ## Usage

  You can use this module directly:

  ```elixir
  alias WebsockexNova.Message.SubscriptionManager
  alias WebsockexNova.Defaults.DefaultSubscriptionHandler

  {:ok, manager} = SubscriptionManager.new(DefaultSubscriptionHandler)
  ```

  Or extend it with your own implementations:

  ```elixir
  defmodule MyApp.CustomSubscriptionHandler do
    @behaviour WebsockexNova.Behaviors.SubscriptionHandler

    # Use the default implementation for most callbacks
    defdelegate subscribe(channel, params, state), to: WebsockexNova.Defaults.DefaultSubscriptionHandler
    defdelegate unsubscribe(subscription_id, state), to: WebsockexNova.Defaults.DefaultSubscriptionHandler
    defdelegate active_subscriptions(state), to: WebsockexNova.Defaults.DefaultSubscriptionHandler
    defdelegate find_subscription_by_channel(channel, state), to: WebsockexNova.Defaults.DefaultSubscriptionHandler

    # Customize just the response handling to match your platform's message format
    def handle_subscription_response(%{"type" => "subscription_update", "status" => "active", "subscription_id" => id}, state) do
      # Custom handling for your platform's subscription confirmation format
      updated_state = update_in(state, [:subscriptions, id], fn sub ->
        if sub, do: Map.put(sub, :status, :confirmed), else: sub
      end)

      {:ok, updated_state}
    end

    def handle_subscription_response(response, state) do
      # Fall back to default for other types of messages
      WebsockexNova.Defaults.DefaultSubscriptionHandler.handle_subscription_response(response, state)
    end
  end
  """

  @behaviour WebsockexNova.Behaviors.SubscriptionHandler

  alias WebsockexNova.Behaviors.SubscriptionHandler

  require Logger

  # Type aliases for improved readability
  @type subscription_id :: SubscriptionHandler.subscription_id()
  @type channel :: SubscriptionHandler.channel()
  @type params :: SubscriptionHandler.params()
  @type state :: SubscriptionHandler.state()
  @type subscription_response :: SubscriptionHandler.subscription_response()

  # Subscription status values
  @subscription_status_pending :pending
  @subscription_status_confirmed :confirmed
  @subscription_status_failed :failed
  @subscription_status_timeout :timeout
  @subscription_status_unsubscribed :unsubscribed

  # Default subscription timeout in seconds
  @default_subscription_timeout 30
  @logger_prefix "[SubscriptionHandler]"

  @impl true
  def subscription_init(opts \\ %{}) do
    state =
      opts
      |> Map.new()
      |> Map.put_new(:subscriptions, %{})
      |> Map.put_new(:subscription_timeout, Map.get(opts, :subscription_timeout, @default_subscription_timeout))

    Logger.debug("#{@logger_prefix} Initialized with options: #{inspect(opts)}")
    {:ok, state}
  end

  @impl true
  @spec subscribe(channel(), params(), state()) ::
          {:ok, subscription_id(), state()}
          | {:error, term(), state()}
  def subscribe(channel, params, state) do
    # Generate a unique subscription ID
    subscription_id = "sub_#{System.unique_integer([:positive, :monotonic])}"

    Logger.debug("#{@logger_prefix} Subscribing to channel: #{inspect(channel)} with ID: #{subscription_id}")

    # Create subscription entry with additional metadata
    subscription = %{
      channel: channel,
      params: params,
      status: @subscription_status_pending,
      timestamp: System.system_time(:second),
      last_updated: System.system_time(:second),
      attempt: 1,
      history: [{@subscription_status_pending, System.system_time(:second)}]
    }

    # Update state with new subscription
    subscriptions = Map.get(state, :subscriptions, %{})
    updated_subscriptions = Map.put(subscriptions, subscription_id, subscription)
    updated_state = Map.put(state, :subscriptions, updated_subscriptions)

    # Check for timed-out subscriptions while we're at it
    clean_state = check_subscription_timeouts(updated_state)

    {:ok, subscription_id, clean_state}
  end

  @impl true
  @spec unsubscribe(subscription_id(), state()) ::
          {:ok, state()}
          | {:error, term(), state()}
  def unsubscribe(subscription_id, state) do
    subscriptions = Map.get(state, :subscriptions, %{})

    if Map.has_key?(subscriptions, subscription_id) do
      Logger.debug("#{@logger_prefix} Unsubscribing from: #{subscription_id}")

      # Instead of deleting, mark as unsubscribed but keep the record
      subscription = subscriptions[subscription_id]

      updated_subscription =
        subscription
        |> Map.put(:status, @subscription_status_unsubscribed)
        |> Map.put(:last_updated, System.system_time(:second))
        |> Map.update(:history, [], fn history ->
          [{@subscription_status_unsubscribed, System.system_time(:second)} | history]
        end)

      updated_subscriptions = Map.put(subscriptions, subscription_id, updated_subscription)
      updated_state = Map.put(state, :subscriptions, updated_subscriptions)

      {:ok, updated_state}
    else
      Logger.warning("#{@logger_prefix} Subscription not found for unsubscribe: #{subscription_id}")
      {:error, :subscription_not_found, state}
    end
  end

  @impl true
  @spec handle_subscription_response(subscription_response(), state()) ::
          {:ok, state()}
          | {:error, term(), state()}
  def handle_subscription_response(response, state) do
    # First, ensure we don't have timed-out subscriptions
    clean_state = check_subscription_timeouts(state)

    # Handle common response formats
    cond do
      # Standard subscription confirmation
      match?(%{"type" => "subscribed", "id" => _id}, response) ->
        Logger.debug("#{@logger_prefix} Subscription confirmed: #{inspect(response)}")
        handle_subscription_confirmation(response["id"], clean_state)

      # Standard subscription confirmation (alt format)
      match?(%{"type" => "subscription", "result" => "success", "id" => _id}, response) ->
        Logger.debug("#{@logger_prefix} Subscription confirmed: #{inspect(response)}")
        handle_subscription_confirmation(response["id"], clean_state)

      # Standard error response
      match?(%{"type" => "subscription", "result" => "error", "id" => _id, "error" => _error}, response) ->
        Logger.warning("#{@logger_prefix} Subscription error: #{inspect(response)}")
        handle_subscription_error(response["id"], response["error"], clean_state)

      # Standard error response (alt format)
      match?(%{"type" => "error", "subscription_id" => _id, "reason" => _reason}, response) ->
        Logger.warning("#{@logger_prefix} Subscription error: #{inspect(response)}")
        handle_subscription_error(response["subscription_id"], response["reason"], clean_state)

      # Unknown/unrelated message
      true ->
        {:ok, clean_state}
    end
  end

  @impl true
  @spec active_subscriptions(state()) :: %{subscription_id() => term()}
  def active_subscriptions(state) do
    subscriptions = Map.get(state, :subscriptions, %{})

    subscriptions
    |> Enum.filter(fn {_id, sub} -> Map.get(sub, :status) == @subscription_status_confirmed end)
    |> Map.new()
  end

  @impl true
  @spec find_subscription_by_channel(channel(), state()) :: subscription_id() | nil
  def find_subscription_by_channel(channel, state) do
    subscriptions = Map.get(state, :subscriptions, %{})

    Enum.find_value(subscriptions, nil, fn {id, sub} ->
      # Only return active subscriptions
      if sub.channel == channel and sub.status == @subscription_status_confirmed, do: id
    end)
  end

  # Public helper functions

  @doc """
  Find all subscriptions with a specific status.
  """
  @spec find_subscriptions_by_status(atom(), state()) :: %{subscription_id() => term()}
  def find_subscriptions_by_status(status, state) do
    subscriptions = Map.get(state, :subscriptions, %{})

    subscriptions
    |> Enum.filter(fn {_id, sub} -> Map.get(sub, :status) == status end)
    |> Map.new()
  end

  @doc """
  Clean up expired subscriptions.
  """
  @spec cleanup_expired_subscriptions(state()) :: state()
  def cleanup_expired_subscriptions(state) do
    check_subscription_timeouts(state)
  end

  # Private helper functions

  @spec handle_subscription_confirmation(subscription_id(), state()) :: {:ok, state()}
  defp handle_subscription_confirmation(subscription_id, state) do
    subscriptions = Map.get(state, :subscriptions, %{})

    if Map.has_key?(subscriptions, subscription_id) do
      subscription = subscriptions[subscription_id]

      updated_subscription =
        subscription
        |> Map.put(:status, @subscription_status_confirmed)
        |> Map.put(:last_updated, System.system_time(:second))
        |> Map.update(:history, [], fn history ->
          [{@subscription_status_confirmed, System.system_time(:second)} | history]
        end)

      updated_subscriptions = Map.put(subscriptions, subscription_id, updated_subscription)
      updated_state = Map.put(state, :subscriptions, updated_subscriptions)

      Logger.info("#{@logger_prefix} Subscription confirmed: #{subscription_id} for channel: #{subscription.channel}")

      {:ok, updated_state}
    else
      # If subscription not found, just return the state unchanged
      Logger.warning("#{@logger_prefix} Received confirmation for unknown subscription: #{subscription_id}")
      {:ok, state}
    end
  end

  @spec handle_subscription_error(subscription_id(), term(), state()) :: {:error, term(), state()}
  defp handle_subscription_error(subscription_id, error, state) do
    subscriptions = Map.get(state, :subscriptions, %{})

    if Map.has_key?(subscriptions, subscription_id) do
      subscription = subscriptions[subscription_id]

      updated_subscription =
        subscription
        |> Map.put(:status, @subscription_status_failed)
        |> Map.put(:error, error)
        |> Map.put(:last_updated, System.system_time(:second))
        |> Map.update(:history, [], fn history ->
          [{@subscription_status_failed, System.system_time(:second)} | history]
        end)

      updated_subscriptions = Map.put(subscriptions, subscription_id, updated_subscription)
      updated_state = Map.put(state, :subscriptions, updated_subscriptions)

      Logger.error(
        "#{@logger_prefix} Subscription failed: #{subscription_id} for channel: #{subscription.channel}, error: #{inspect(error)}"
      )

      {:error, error, updated_state}
    else
      # If subscription not found, return the error but state unchanged
      Logger.warning(
        "#{@logger_prefix} Received error for unknown subscription: #{subscription_id}, error: #{inspect(error)}"
      )

      {:error, error, state}
    end
  end

  @spec check_subscription_timeouts(state()) :: state()
  defp check_subscription_timeouts(state) do
    subscriptions = Map.get(state, :subscriptions, %{})
    timeout = Map.get(state, :subscription_timeout, @default_subscription_timeout)
    now = System.system_time(:second)

    # Find and update timed-out pending subscriptions
    {updated_subscriptions, has_timeouts} =
      Enum.reduce(subscriptions, {%{}, false}, fn {id, sub}, {acc_subs, has_timeouts} ->
        if sub.status == @subscription_status_pending and
             now - sub.timestamp > timeout do
          # Mark as timed out
          updated_sub =
            sub
            |> Map.put(:status, @subscription_status_timeout)
            |> Map.put(:last_updated, now)
            |> Map.update(:history, [], fn history ->
              [{@subscription_status_timeout, now} | history]
            end)

          Logger.warning("#{@logger_prefix} Subscription timed out: #{id} for channel: #{sub.channel}")
          {Map.put(acc_subs, id, updated_sub), true}
        else
          {Map.put(acc_subs, id, sub), has_timeouts}
        end
      end)

    if has_timeouts do
      Map.put(state, :subscriptions, updated_subscriptions)
    else
      state
    end
  end
end
