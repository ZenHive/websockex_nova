defmodule WebsockexNova.Defaults.DefaultSubscriptionHandler do
  @moduledoc """
  Default implementation of the SubscriptionHandler behavior.

  This module provides a standard implementation of subscription management
  with reasonable defaults. It supports:

  * Simple subscription tracking with status management
  * Channel-based subscription lookup
  * Standard handling of subscription responses
  * Automatic confirmation management

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

  # Type aliases for improved readability
  @type subscription_id :: SubscriptionHandler.subscription_id()
  @type channel :: SubscriptionHandler.channel()
  @type params :: SubscriptionHandler.params()
  @type state :: SubscriptionHandler.state()
  @type subscription_response :: SubscriptionHandler.subscription_response()

  @impl true
  def subscription_init(opts \\ %{}) do
    state =
      opts
      |> Map.new()
      |> Map.put_new(:subscriptions, %{})

    {:ok, state}
  end

  @impl true
  @spec subscribe(channel(), params(), state()) ::
          {:ok, subscription_id(), state()}
          | {:error, term(), state()}
  def subscribe(channel, params, state) do
    # Generate a unique subscription ID
    subscription_id = "sub_#{System.unique_integer([:positive, :monotonic])}"

    # Create subscription entry
    subscription = %{
      channel: channel,
      params: params,
      status: :pending,
      timestamp: System.system_time(:second)
    }

    # Update state with new subscription
    subscriptions = Map.get(state, :subscriptions, %{})
    updated_subscriptions = Map.put(subscriptions, subscription_id, subscription)
    updated_state = Map.put(state, :subscriptions, updated_subscriptions)

    {:ok, subscription_id, updated_state}
  end

  @impl true
  @spec unsubscribe(subscription_id(), state()) ::
          {:ok, state()}
          | {:error, term(), state()}
  def unsubscribe(subscription_id, state) do
    subscriptions = Map.get(state, :subscriptions, %{})

    if Map.has_key?(subscriptions, subscription_id) do
      updated_subscriptions = Map.delete(subscriptions, subscription_id)
      updated_state = Map.put(state, :subscriptions, updated_subscriptions)
      {:ok, updated_state}
    else
      {:error, :subscription_not_found, state}
    end
  end

  @impl true
  @spec handle_subscription_response(subscription_response(), state()) ::
          {:ok, state()}
          | {:error, term(), state()}
  def handle_subscription_response(response, state) do
    # Handle common response formats
    cond do
      # Standard subscription confirmation
      match?(%{"type" => "subscribed", "id" => _id}, response) ->
        handle_subscription_confirmation(response["id"], state)

      # Standard subscription confirmation (alt format)
      match?(%{"type" => "subscription", "result" => "success", "id" => _id}, response) ->
        handle_subscription_confirmation(response["id"], state)

      # Standard error response
      match?(%{"type" => "subscription", "result" => "error", "id" => _id, "error" => _error}, response) ->
        handle_subscription_error(response["id"], response["error"], state)

      # Standard error response (alt format)
      match?(%{"type" => "error", "subscription_id" => _id, "reason" => _reason}, response) ->
        handle_subscription_error(response["subscription_id"], response["reason"], state)

      # Unknown/unrelated message
      true ->
        {:ok, state}
    end
  end

  @impl true
  @spec active_subscriptions(state()) :: %{subscription_id() => term()}
  def active_subscriptions(state) do
    subscriptions = Map.get(state, :subscriptions, %{})

    subscriptions
    |> Enum.filter(fn {_id, sub} -> Map.get(sub, :status) == :confirmed end)
    |> Map.new()
  end

  @impl true
  @spec find_subscription_by_channel(channel(), state()) :: subscription_id() | nil
  def find_subscription_by_channel(channel, state) do
    subscriptions = Map.get(state, :subscriptions, %{})

    Enum.find_value(subscriptions, nil, fn {id, sub} ->
      if sub.channel == channel, do: id
    end)
  end

  # Private helper functions

  @spec handle_subscription_confirmation(subscription_id(), state()) :: {:ok, state()}
  defp handle_subscription_confirmation(subscription_id, state) do
    subscriptions = Map.get(state, :subscriptions, %{})

    if Map.has_key?(subscriptions, subscription_id) do
      updated_subscription = Map.put(subscriptions[subscription_id], :status, :confirmed)
      updated_subscriptions = Map.put(subscriptions, subscription_id, updated_subscription)
      updated_state = Map.put(state, :subscriptions, updated_subscriptions)
      {:ok, updated_state}
    else
      # If subscription not found, just return the state unchanged
      {:ok, state}
    end
  end

  @spec handle_subscription_error(subscription_id(), term(), state()) :: {:error, term(), state()}
  defp handle_subscription_error(subscription_id, error, state) do
    subscriptions = Map.get(state, :subscriptions, %{})

    if Map.has_key?(subscriptions, subscription_id) do
      updated_subscription =
        subscriptions[subscription_id]
        |> Map.put(:status, :failed)
        |> Map.put(:error, error)

      updated_subscriptions = Map.put(subscriptions, subscription_id, updated_subscription)
      updated_state = Map.put(state, :subscriptions, updated_subscriptions)
      {:error, error, updated_state}
    else
      # If subscription not found, return the error but state unchanged
      {:error, error, state}
    end
  end
end
