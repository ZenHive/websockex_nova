defmodule WebsockexNova.Behaviors.SubscriptionHandler do
  @moduledoc """
  Behaviour for subscription handlers.
  All state is a map. All arguments and return values are explicit and documented.
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
