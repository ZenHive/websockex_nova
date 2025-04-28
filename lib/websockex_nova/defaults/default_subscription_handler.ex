defmodule WebsockexNova.Defaults.DefaultSubscriptionHandler do
  @moduledoc """
  Default implementation of the SubscriptionHandler behavior.

  This module provides sensible default implementations for all SubscriptionHandler
  callbacks, enabling applications to subscribe to data streams via WebSocket.

  ## Features

  * Subscription management with unique IDs
  * Automatic subscription status tracking
  * Automatic timeout detection for pending subscriptions
  * Methods to find and filter active subscriptions

  ## Usage

  You can use this module directly or as a starting point for your own implementation:

      defmodule MyApp.CustomSubscriptionHandler do
        use WebsockexNova.Defaults.DefaultSubscriptionHandler

        # Override specific callbacks as needed
        def subscribe(channel, params, conn) do
          # Custom subscription logic
          # ...
        end
      end
  """

  @behaviour WebsockexNova.Behaviors.SubscriptionHandler

  require Logger

  @logger_prefix "[DefaultSubscriptionHandler]"

  @default_subscription_timeout 30

  # Subscription status constants
  @subscription_status_pending :pending
  @subscription_status_confirmed :confirmed
  @subscription_status_failed :failed
  @subscription_status_unsubscribed :unsubscribed
  @subscription_status_expired :expired

  @typedoc "A unique identifier for a subscription"
  @type subscription_id :: String.t()

  @typedoc "A channel or topic to subscribe to"
  @type channel :: String.t()

  @typedoc "Parameters for the subscription"
  @type params :: map()

  @typedoc "Response from a subscription request"
  @type subscription_response :: map()

  @typedoc "State - either a ClientConn struct or any map with subscription-related fields"
  @type state :: WebsockexNova.ClientConn.t() | map()

  @doc """
  Initializes a subscription handler.

  ## Parameters

  * `opts` - Options for initializing the subscription handler (optional)

  ## Returns

  * `{:ok, conn}` - Initial state with subscription handler settings
  """
  @spec subscription_init(map() | Keyword.t()) :: {:ok, WebsockexNova.ClientConn.t()}
  def subscription_init(opts \\ %{}) do
    opts_map = Map.new(opts)
    # Split known fields and custom fields
    known_keys = MapSet.new(Map.keys(%WebsockexNova.ClientConn{}))
    {known, custom} = Enum.split_with(opts_map, fn {k, _v} -> MapSet.member?(known_keys, k) end)
    known_map = Map.new(known)
    custom_map = Map.new(custom)
    conn = struct(WebsockexNova.ClientConn, known_map)

    # Initialize adapter_state with subscriptions
    adapter_state = Map.get(conn, :adapter_state, %{})

    updated_adapter_state =
      adapter_state
      |> Map.put(:subscriptions, Map.get(opts_map, :subscriptions, %{}))
      |> Map.put(:subscription_timeout, Map.get(opts_map, :subscription_timeout, @default_subscription_timeout))

    conn = %{
      conn
      | adapter_state: updated_adapter_state,
        subscription_handler_settings: Map.merge(conn.subscription_handler_settings || %{}, custom_map)
    }

    Logger.debug("#{@logger_prefix} Initialized with options: #{inspect(opts)}")
    {:ok, conn}
  end

  @impl true
  @spec subscribe(channel(), params(), WebsockexNova.ClientConn.t()) ::
          {:ok, subscription_id(), WebsockexNova.ClientConn.t()}
          | {:error, term(), WebsockexNova.ClientConn.t()}
  def subscribe(channel, params, %WebsockexNova.ClientConn{adapter_state: adapter_state} = conn) do
    subscription_id = "sub_#{System.unique_integer([:positive, :monotonic])}"
    Logger.debug("#{@logger_prefix} Subscribing to channel: #{inspect(channel)} with ID: #{subscription_id}")

    subscription = %{
      channel: channel,
      params: params,
      status: @subscription_status_pending,
      timestamp: System.system_time(:second),
      last_updated: System.system_time(:second),
      attempt: 1,
      history: [{@subscription_status_pending, System.system_time(:second)}]
    }

    subscriptions = Map.get(adapter_state, :subscriptions, %{})
    updated_subscriptions = Map.put(subscriptions, subscription_id, subscription)

    updated_adapter_state = Map.put(adapter_state, :subscriptions, updated_subscriptions)
    updated_conn = %{conn | adapter_state: updated_adapter_state}

    clean_conn = check_subscription_timeouts(updated_conn)
    {:ok, subscription_id, clean_conn}
  end

  @impl true
  @spec unsubscribe(subscription_id(), WebsockexNova.ClientConn.t()) ::
          {:ok, WebsockexNova.ClientConn.t()}
          | {:error, term(), WebsockexNova.ClientConn.t()}
  def unsubscribe(subscription_id, %WebsockexNova.ClientConn{adapter_state: adapter_state} = conn) do
    subscriptions = Map.get(adapter_state, :subscriptions, %{})

    if Map.has_key?(subscriptions, subscription_id) do
      Logger.debug("#{@logger_prefix} Unsubscribing from: #{subscription_id}")
      subscription = subscriptions[subscription_id]

      updated_subscription =
        subscription
        |> Map.put(:status, @subscription_status_unsubscribed)
        |> Map.put(:last_updated, System.system_time(:second))
        |> Map.update(:history, [], fn history ->
          [{@subscription_status_unsubscribed, System.system_time(:second)} | history]
        end)

      updated_subscriptions = Map.put(subscriptions, subscription_id, updated_subscription)
      updated_adapter_state = Map.put(adapter_state, :subscriptions, updated_subscriptions)
      updated_conn = %{conn | adapter_state: updated_adapter_state}

      {:ok, updated_conn}
    else
      Logger.warning("#{@logger_prefix} Subscription not found for unsubscribe: #{subscription_id}")
      {:error, :subscription_not_found, conn}
    end
  end

  @impl true
  @spec handle_subscription_response(subscription_response(), WebsockexNova.ClientConn.t()) ::
          {:ok, WebsockexNova.ClientConn.t()}
          | {:error, term(), WebsockexNova.ClientConn.t()}
  def handle_subscription_response(response, %WebsockexNova.ClientConn{} = conn) do
    clean_conn = check_subscription_timeouts(conn)

    cond do
      match?(%{"type" => "subscribed", "id" => _id}, response) ->
        Logger.debug("#{@logger_prefix} Subscription confirmed: #{inspect(response)}")
        handle_subscription_confirmation(response["id"], clean_conn)

      match?(%{"type" => "subscription", "result" => "success", "id" => _id}, response) ->
        Logger.debug("#{@logger_prefix} Subscription confirmed: #{inspect(response)}")
        handle_subscription_confirmation(response["id"], clean_conn)

      match?(%{"type" => "subscription", "result" => "error", "id" => _id, "error" => _error}, response) ->
        Logger.warning("#{@logger_prefix} Subscription error: #{inspect(response)}")
        handle_subscription_error(response["id"], response["error"], clean_conn)

      match?(%{"type" => "error", "subscription_id" => _id, "reason" => _reason}, response) ->
        Logger.warning("#{@logger_prefix} Subscription error: #{inspect(response)}")
        handle_subscription_error(response["subscription_id"], response["reason"], clean_conn)

      true ->
        {:ok, clean_conn}
    end
  end

  @impl true
  @spec active_subscriptions(WebsockexNova.ClientConn.t()) :: %{subscription_id() => term()}
  def active_subscriptions(%WebsockexNova.ClientConn{adapter_state: adapter_state}) do
    subscriptions = Map.get(adapter_state, :subscriptions, %{})

    subscriptions
    |> Enum.filter(fn {_id, sub} -> Map.get(sub, :status) == @subscription_status_confirmed end)
    |> Map.new()
  end

  @impl true
  @spec find_subscription_by_channel(channel(), WebsockexNova.ClientConn.t()) :: subscription_id() | nil
  def find_subscription_by_channel(channel, %WebsockexNova.ClientConn{adapter_state: adapter_state}) do
    subscriptions = Map.get(adapter_state, :subscriptions, %{})

    Enum.find_value(subscriptions, nil, fn {id, sub} ->
      if sub.channel == channel and sub.status == @subscription_status_confirmed, do: id
    end)
  end

  # Public helper functions

  @doc """
  Find all subscriptions with a specific status.
  """
  @spec find_subscriptions_by_status(atom(), state()) :: %{subscription_id() => term()}
  def find_subscriptions_by_status(status, %WebsockexNova.ClientConn{adapter_state: adapter_state}) do
    subscriptions = Map.get(adapter_state, :subscriptions, %{})

    subscriptions
    |> Enum.filter(fn {_id, sub} -> Map.get(sub, :status) == status end)
    |> Map.new()
  end

  def find_subscriptions_by_status(status, state) when is_map(state) do
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
  defp handle_subscription_confirmation(subscription_id, %WebsockexNova.ClientConn{adapter_state: adapter_state} = conn) do
    subscriptions = Map.get(adapter_state, :subscriptions, %{})

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
      updated_adapter_state = Map.put(adapter_state, :subscriptions, updated_subscriptions)
      updated_conn = %{conn | adapter_state: updated_adapter_state}

      Logger.info("#{@logger_prefix} Subscription confirmed: #{subscription_id} for channel: #{subscription.channel}")
      {:ok, updated_conn}
    else
      Logger.warning("#{@logger_prefix} Received confirmation for unknown subscription: #{subscription_id}")
      {:ok, conn}
    end
  end

  @spec handle_subscription_error(subscription_id(), term(), state()) :: {:error, term(), state()}
  defp handle_subscription_error(subscription_id, error, %WebsockexNova.ClientConn{adapter_state: adapter_state} = conn) do
    subscriptions = Map.get(adapter_state, :subscriptions, %{})

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
      updated_adapter_state = Map.put(adapter_state, :subscriptions, updated_subscriptions)
      updated_conn = %{conn | adapter_state: updated_adapter_state}

      Logger.error(
        "#{@logger_prefix} Subscription failed: #{subscription_id} for channel: #{subscription.channel}, error: #{inspect(error)}"
      )

      {:error, error, updated_conn}
    else
      Logger.warning(
        "#{@logger_prefix} Received error for unknown subscription: #{subscription_id}, error: #{inspect(error)}"
      )

      {:error, error, conn}
    end
  end

  @spec check_subscription_timeouts(WebsockexNova.ClientConn.t()) :: WebsockexNova.ClientConn.t()
  defp check_subscription_timeouts(%WebsockexNova.ClientConn{adapter_state: adapter_state} = conn) do
    subscriptions = Map.get(adapter_state, :subscriptions, %{})
    timeout = Map.get(adapter_state, :subscription_timeout, @default_subscription_timeout)
    now = System.system_time(:second)

    updated_subscriptions =
      Enum.reduce(subscriptions, %{}, fn {id, subscription}, acc ->
        cond do
          # Skip if not pending
          subscription.status != @subscription_status_pending ->
            Map.put(acc, id, subscription)

          # Mark as expired if timeout elapsed
          now - subscription.timestamp > timeout ->
            updated =
              subscription
              |> Map.put(:status, @subscription_status_expired)
              |> Map.put(:last_updated, now)
              |> Map.update(:history, [], fn history ->
                [{@subscription_status_expired, now} | history]
              end)

            Logger.warning(
              "#{@logger_prefix} Subscription expired: #{id} for channel: #{subscription.channel}, age: #{now - subscription.timestamp}s"
            )

            Map.put(acc, id, updated)

          # Keep as is
          true ->
            Map.put(acc, id, subscription)
        end
      end)

    updated_adapter_state = Map.put(adapter_state, :subscriptions, updated_subscriptions)
    %{conn | adapter_state: updated_adapter_state}
  end

  # For plain map state (used in tests)
  defp check_subscription_timeouts(%{subscriptions: subscriptions} = state) do
    timeout = Map.get(state, :subscription_timeout, @default_subscription_timeout)
    now = System.system_time(:second)

    updated_subscriptions =
      Enum.reduce(subscriptions, %{}, fn {id, subscription}, acc ->
        cond do
          # Skip if not pending
          subscription.status != @subscription_status_pending ->
            Map.put(acc, id, subscription)

          # Mark as expired if timeout elapsed
          now - subscription.timestamp > timeout ->
            updated =
              subscription
              |> Map.put(:status, @subscription_status_expired)
              |> Map.put(:last_updated, now)
              |> Map.update(:history, [], fn history ->
                [{@subscription_status_expired, now} | history]
              end)

            Logger.warning(
              "#{@logger_prefix} Subscription expired: #{id} for channel: #{subscription.channel}, age: #{now - subscription.timestamp}s"
            )

            Map.put(acc, id, updated)

          # Keep as is
          true ->
            Map.put(acc, id, subscription)
        end
      end)

    %{state | subscriptions: updated_subscriptions}
  end

  defp check_subscription_timeouts(state), do: state
end
