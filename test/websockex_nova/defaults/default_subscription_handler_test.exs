defmodule WebsockexNova.Defaults.DefaultSubscriptionHandlerTest do
  use ExUnit.Case, async: true

  alias WebsockexNova.Defaults.DefaultSubscriptionHandler

  describe "DefaultSubscriptionHandler" do
    setup do
      now = System.system_time(:second)

      state = %WebsockexNova.ClientConn{
        subscription_timeout: 600,
        subscriptions: %{
          "existing_sub_1" => %{
            channel: "ticker.btcusd",
            params: %{frequency: "100ms"},
            status: :confirmed,
            timestamp: now - 100,
            last_updated: now - 100,
            history: [{:confirmed, now - 100}],
            attempt: 1
          },
          "existing_sub_2" => %{
            channel: "trades.ethusd",
            params: nil,
            status: :pending,
            timestamp: now - 50,
            last_updated: now - 50,
            history: [{:pending, now - 50}],
            attempt: 1
          }
        }
      }

      {:ok, state: state, empty_state: %WebsockexNova.ClientConn{}}
    end

    test "subscription_init/1 initializes state with defaults" do
      assert {:ok, state} = DefaultSubscriptionHandler.subscription_init()
      assert state.subscriptions == %{}
      assert state.subscription_timeout == 30

      assert {:ok, custom_state} = DefaultSubscriptionHandler.subscription_init(%{subscription_timeout: 120})
      assert custom_state.subscription_timeout == 120
    end

    test "subscribe/3 creates a new subscription", %{state: state} do
      channel = "orderbook.btcusd"
      params = %{depth: 10}

      assert {:ok, subscription_id, updated_state} =
               DefaultSubscriptionHandler.subscribe(channel, params, state)

      assert is_binary(subscription_id)
      assert String.starts_with?(subscription_id, "sub_")
      assert updated_state.subscriptions[subscription_id].channel == channel
      assert updated_state.subscriptions[subscription_id].params == params
      assert updated_state.subscriptions[subscription_id].status == :pending
      assert is_integer(updated_state.subscriptions[subscription_id].timestamp)
      assert is_integer(updated_state.subscriptions[subscription_id].last_updated)
      assert length(updated_state.subscriptions[subscription_id].history) == 1
      assert updated_state.subscriptions[subscription_id].attempt == 1
    end

    test "unsubscribe/2 marks an existing subscription as unsubscribed", %{state: state} do
      subscription_id = "existing_sub_1"

      assert {:ok, updated_state} = DefaultSubscriptionHandler.unsubscribe(subscription_id, state)

      # Subscription is still in the map but marked as unsubscribed
      assert Map.has_key?(updated_state.subscriptions, subscription_id)
      assert updated_state.subscriptions[subscription_id].status == :unsubscribed
      assert length(updated_state.subscriptions[subscription_id].history) == 2
      assert Map.has_key?(updated_state.subscriptions, "existing_sub_2")
    end

    test "unsubscribe/2 handles non-existent subscriptions", %{state: state} do
      subscription_id = "non_existent_sub"

      assert {:error, :subscription_not_found, ^state} =
               DefaultSubscriptionHandler.unsubscribe(subscription_id, state)
    end

    test "handle_subscription_response/2 processes standard confirmation format", %{state: state} do
      response = %{"type" => "subscribed", "id" => "existing_sub_2"}

      assert {:ok, updated_state} =
               DefaultSubscriptionHandler.handle_subscription_response(response, state)

      assert updated_state.subscriptions["existing_sub_2"].status == :confirmed
      assert length(updated_state.subscriptions["existing_sub_2"].history) == 2

      assert updated_state.subscriptions["existing_sub_2"].last_updated >
               updated_state.subscriptions["existing_sub_2"].timestamp
    end

    test "handle_subscription_response/2 processes alternative confirmation format", %{state: state} do
      response = %{"type" => "subscription", "result" => "success", "id" => "existing_sub_2"}

      assert {:ok, updated_state} =
               DefaultSubscriptionHandler.handle_subscription_response(response, state)

      assert updated_state.subscriptions["existing_sub_2"].status == :confirmed
      assert length(updated_state.subscriptions["existing_sub_2"].history) == 2
    end

    test "handle_subscription_response/2 processes standard error format", %{state: state} do
      response = %{
        "type" => "subscription",
        "result" => "error",
        "id" => "existing_sub_2",
        "error" => "invalid_parameters"
      }

      assert {:error, "invalid_parameters", updated_state} =
               DefaultSubscriptionHandler.handle_subscription_response(response, state)

      assert updated_state.subscriptions["existing_sub_2"].status == :failed
      assert updated_state.subscriptions["existing_sub_2"].error == "invalid_parameters"
      assert length(updated_state.subscriptions["existing_sub_2"].history) == 2
    end

    test "handle_subscription_response/2 processes alternative error format", %{state: state} do
      response = %{
        "type" => "error",
        "subscription_id" => "existing_sub_2",
        "reason" => "access_denied"
      }

      assert {:error, "access_denied", updated_state} =
               DefaultSubscriptionHandler.handle_subscription_response(response, state)

      assert updated_state.subscriptions["existing_sub_2"].status == :failed
      assert updated_state.subscriptions["existing_sub_2"].error == "access_denied"
      assert length(updated_state.subscriptions["existing_sub_2"].history) == 2
    end

    test "handle_subscription_response/2 gracefully handles unknown subscription IDs", %{state: state} do
      response = %{"type" => "subscribed", "id" => "unknown_sub"}

      # State may be different now since we check for timeouts, but the result should still be :ok
      assert {:ok, _updated_state} = DefaultSubscriptionHandler.handle_subscription_response(response, state)
    end

    test "handle_subscription_response/2 ignores unrelated messages", %{state: state} do
      response = %{"type" => "market_data", "ticker" => "btcusd", "price" => 50_000}

      # State may be different now since we check for timeouts, but the result should still be :ok
      assert {:ok, _updated_state} = DefaultSubscriptionHandler.handle_subscription_response(response, state)
    end

    test "active_subscriptions/1 returns only confirmed subscriptions", %{state: state} do
      active = DefaultSubscriptionHandler.active_subscriptions(state)

      assert map_size(active) == 1
      assert Map.has_key?(active, "existing_sub_1")
      refute Map.has_key?(active, "existing_sub_2")
    end

    test "find_subscription_by_channel/2 finds subscription IDs for confirmed channels", %{state: state} do
      # Only confirmed subscriptions are returned
      assert DefaultSubscriptionHandler.find_subscription_by_channel("ticker.btcusd", state) ==
               "existing_sub_1"

      # Pending subscriptions are not returned by default
      assert DefaultSubscriptionHandler.find_subscription_by_channel("trades.ethusd", state) == nil

      assert DefaultSubscriptionHandler.find_subscription_by_channel("non_existent", state) == nil
    end

    test "find_subscriptions_by_status/2 finds all subscriptions with a specific status", %{state: state} do
      confirmed = DefaultSubscriptionHandler.find_subscriptions_by_status(:confirmed, state)
      pending = DefaultSubscriptionHandler.find_subscriptions_by_status(:pending, state)
      failed = DefaultSubscriptionHandler.find_subscriptions_by_status(:failed, state)

      assert map_size(confirmed) == 1
      assert map_size(pending) == 1
      assert map_size(failed) == 0
      assert Map.has_key?(confirmed, "existing_sub_1")
      assert Map.has_key?(pending, "existing_sub_2")
    end

    test "check_subscription_timeouts handles timeouts", %{state: _state} do
      # Create a state with a short timeout and an old subscription
      now = System.system_time(:second)

      timeout_state = %WebsockexNova.ClientConn{
        subscription_timeout: 5,
        subscriptions: %{
          "timeout_sub" => %{
            channel: "old.channel",
            params: nil,
            status: :pending,
            # 10 seconds old
            timestamp: now - 10,
            last_updated: now - 10,
            history: [{:pending, now - 10}],
            attempt: 1
          }
        }
      }

      # Use cleanup_expired_subscriptions which calls check_subscription_timeouts
      updated_state = DefaultSubscriptionHandler.cleanup_expired_subscriptions(timeout_state)

      # Subscription should be marked as timed out
      assert updated_state.subscriptions["timeout_sub"].status == :timeout
      assert length(updated_state.subscriptions["timeout_sub"].history) == 2

      assert updated_state.subscriptions["timeout_sub"].last_updated >
               updated_state.subscriptions["timeout_sub"].timestamp
    end

    test "works with empty state" do
      empty_state = %WebsockexNova.ClientConn{}

      # Subscribe should work with empty state
      assert {:ok, subscription_id, updated_state} =
               DefaultSubscriptionHandler.subscribe("channel", nil, empty_state)

      assert Map.has_key?(updated_state, :subscriptions)
      assert Map.has_key?(updated_state.subscriptions, subscription_id)

      # Other functions should also handle empty state gracefully
      assert DefaultSubscriptionHandler.active_subscriptions(empty_state) == %{}
      assert DefaultSubscriptionHandler.find_subscription_by_channel("any", empty_state) == nil

      assert {:error, :subscription_not_found, ^empty_state} =
               DefaultSubscriptionHandler.unsubscribe("any", empty_state)

      assert {:ok, _updated_state} =
               DefaultSubscriptionHandler.handle_subscription_response(%{}, empty_state)
    end
  end
end
