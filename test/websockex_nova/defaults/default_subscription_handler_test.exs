defmodule WebsockexNova.Defaults.DefaultSubscriptionHandlerTest do
  use ExUnit.Case, async: true

  alias WebsockexNova.Defaults.DefaultSubscriptionHandler

  describe "DefaultSubscriptionHandler" do
    setup do
      state = %{
        subscriptions: %{
          "existing_sub_1" => %{
            channel: "ticker.btcusd",
            params: %{frequency: "100ms"},
            status: :confirmed,
            timestamp: System.system_time(:second) - 100
          },
          "existing_sub_2" => %{
            channel: "trades.ethusd",
            params: nil,
            status: :pending,
            timestamp: System.system_time(:second) - 50
          }
        }
      }

      {:ok, state: state}
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
    end

    test "unsubscribe/2 removes an existing subscription", %{state: state} do
      subscription_id = "existing_sub_1"

      assert {:ok, updated_state} = DefaultSubscriptionHandler.unsubscribe(subscription_id, state)

      refute Map.has_key?(updated_state.subscriptions, subscription_id)
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
    end

    test "handle_subscription_response/2 processes alternative confirmation format", %{state: state} do
      response = %{"type" => "subscription", "result" => "success", "id" => "existing_sub_2"}

      assert {:ok, updated_state} =
               DefaultSubscriptionHandler.handle_subscription_response(response, state)

      assert updated_state.subscriptions["existing_sub_2"].status == :confirmed
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
    end

    test "handle_subscription_response/2 gracefully handles unknown subscription IDs", %{state: state} do
      response = %{"type" => "subscribed", "id" => "unknown_sub"}

      assert {:ok, ^state} = DefaultSubscriptionHandler.handle_subscription_response(response, state)
    end

    test "handle_subscription_response/2 ignores unrelated messages", %{state: state} do
      response = %{"type" => "market_data", "ticker" => "btcusd", "price" => 50_000}

      assert {:ok, ^state} = DefaultSubscriptionHandler.handle_subscription_response(response, state)
    end

    test "active_subscriptions/1 returns only confirmed subscriptions", %{state: state} do
      active = DefaultSubscriptionHandler.active_subscriptions(state)

      assert map_size(active) == 1
      assert Map.has_key?(active, "existing_sub_1")
      refute Map.has_key?(active, "existing_sub_2")
    end

    test "find_subscription_by_channel/2 finds subscription IDs by channel name", %{state: state} do
      assert DefaultSubscriptionHandler.find_subscription_by_channel("ticker.btcusd", state) ==
               "existing_sub_1"

      assert DefaultSubscriptionHandler.find_subscription_by_channel("trades.ethusd", state) ==
               "existing_sub_2"

      assert DefaultSubscriptionHandler.find_subscription_by_channel("non_existent", state) == nil
    end

    test "works with empty state" do
      empty_state = %{}

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

      assert {:ok, ^empty_state} =
               DefaultSubscriptionHandler.handle_subscription_response(%{}, empty_state)
    end
  end
end
