defmodule WebsockexNova.Behaviors.SubscriptionHandlerTest do
  use ExUnit.Case, async: true

  # Define a mock module that implements the SubscriptionHandler behavior
  defmodule MockSubscriptionHandler do
    @moduledoc false
    @behaviour WebsockexNova.Behaviors.SubscriptionHandler

    @impl true
    def subscribe(channel, params, state) do
      send(self(), {:subscribe_called, channel, params})

      subscription_id = "sub_#{:erlang.monotonic_time()}"

      updated_state =
        Map.update(state, :subscriptions, %{subscription_id => channel}, fn subs ->
          Map.put(subs, subscription_id, channel)
        end)

      {:ok, subscription_id, updated_state}
    end

    @impl true
    def unsubscribe(subscription_id, state) do
      send(self(), {:unsubscribe_called, subscription_id})

      case get_in(state, [:subscriptions, subscription_id]) do
        nil ->
          {:error, :subscription_not_found, state}

        _channel ->
          updated_state = update_in(state, [:subscriptions], &Map.delete(&1, subscription_id))
          {:ok, updated_state}
      end
    end

    @impl true
    def handle_subscription_response(%{"type" => "subscription", "result" => "success", "id" => id}, state) do
      send(self(), {:subscription_success, id})
      updated_state = put_in(state, [:confirmed_subscriptions, id], true)
      {:ok, updated_state}
    end

    @impl true
    def handle_subscription_response(
          %{"type" => "subscription", "result" => "error", "id" => id, "error" => error},
          state
        ) do
      send(self(), {:subscription_error, id, error})
      updated_state = put_in(state, [:failed_subscriptions, id], error)
      {:error, error, updated_state}
    end

    @impl true
    def handle_subscription_response(_response, state) do
      {:ok, state}
    end

    @impl true
    def active_subscriptions(state) do
      state[:subscriptions] || %{}
    end

    @impl true
    def find_subscription_by_channel(channel, state) do
      subscriptions = state[:subscriptions] || %{}

      Enum.find_value(subscriptions, nil, fn {id, sub_channel} ->
        if sub_channel == channel, do: id
      end)
    end
  end

  describe "SubscriptionHandler behavior" do
    setup do
      {:ok,
       state: %{
         subscriptions: %{
           "existing_sub_1" => "trades",
           "existing_sub_2" => "ticker"
         },
         confirmed_subscriptions: %{},
         failed_subscriptions: %{}
       }}
    end

    test "subscribe/3 creates a new subscription", %{state: state} do
      channel = "orderbook"
      params = %{depth: 10}

      assert {:ok, subscription_id, updated_state} =
               MockSubscriptionHandler.subscribe(channel, params, state)

      assert is_binary(subscription_id)
      assert updated_state.subscriptions[subscription_id] == channel
      assert_received {:subscribe_called, ^channel, ^params}
    end

    test "unsubscribe/2 removes an existing subscription", %{state: state} do
      subscription_id = "existing_sub_1"

      assert {:ok, updated_state} =
               MockSubscriptionHandler.unsubscribe(subscription_id, state)

      refute Map.has_key?(updated_state.subscriptions, subscription_id)
      assert_received {:unsubscribe_called, ^subscription_id}
    end

    test "unsubscribe/2 handles non-existent subscriptions", %{state: state} do
      subscription_id = "non_existent_sub"

      assert {:error, :subscription_not_found, ^state} =
               MockSubscriptionHandler.unsubscribe(subscription_id, state)

      assert_received {:unsubscribe_called, ^subscription_id}
    end

    test "handle_subscription_response/2 processes successful subscriptions", %{state: state} do
      response = %{"type" => "subscription", "result" => "success", "id" => "existing_sub_1"}

      assert {:ok, updated_state} =
               MockSubscriptionHandler.handle_subscription_response(response, state)

      assert updated_state.confirmed_subscriptions["existing_sub_1"] == true
      assert_received {:subscription_success, "existing_sub_1"}
    end

    test "handle_subscription_response/2 processes failed subscriptions", %{state: state} do
      response = %{
        "type" => "subscription",
        "result" => "error",
        "id" => "existing_sub_2",
        "error" => "access_denied"
      }

      assert {:error, "access_denied", updated_state} =
               MockSubscriptionHandler.handle_subscription_response(response, state)

      assert updated_state.failed_subscriptions["existing_sub_2"] == "access_denied"
      assert_received {:subscription_error, "existing_sub_2", "access_denied"}
    end

    test "handle_subscription_response/2 ignores unrelated messages", %{state: state} do
      response = %{"type" => "other_message"}

      assert {:ok, ^state} =
               MockSubscriptionHandler.handle_subscription_response(response, state)
    end

    test "active_subscriptions/1 returns the current subscriptions", %{state: state} do
      expected = %{
        "existing_sub_1" => "trades",
        "existing_sub_2" => "ticker"
      }

      assert MockSubscriptionHandler.active_subscriptions(state) == expected
    end

    test "find_subscription_by_channel/2 finds subscription IDs by channel", %{state: state} do
      assert MockSubscriptionHandler.find_subscription_by_channel("trades", state) == "existing_sub_1"
      assert MockSubscriptionHandler.find_subscription_by_channel("ticker", state) == "existing_sub_2"
      assert MockSubscriptionHandler.find_subscription_by_channel("non_existent", state) == nil
    end
  end
end
