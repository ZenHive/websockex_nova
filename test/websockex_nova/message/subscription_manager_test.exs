defmodule WebsockexNova.Message.SubscriptionManagerTest do
  use ExUnit.Case, async: true

  alias WebsockexNova.Behaviors.SubscriptionHandler
  alias WebsockexNova.Message.SubscriptionManager

  # Define a test subscription handler for our tests
  defmodule TestSubscriptionHandler do
    @moduledoc false
    @behaviour SubscriptionHandler

    @impl true
    def subscribe(channel, params, state) do
      subscription_id = "sub_#{System.unique_integer([:positive, :monotonic])}"
      subscriptions = Map.get(state, :subscriptions, %{})

      updated_subscriptions =
        Map.put(subscriptions, subscription_id, %{
          channel: channel,
          params: params,
          status: :pending,
          timestamp: System.system_time(:second)
        })

      updated_state = Map.put(state, :subscriptions, updated_subscriptions)
      {:ok, subscription_id, updated_state}
    end

    @impl true
    def unsubscribe(subscription_id, state) do
      case get_in(state, [:subscriptions, subscription_id]) do
        nil ->
          {:error, :subscription_not_found, state}

        _subscription ->
          updated_state = update_in(state, [:subscriptions], &Map.delete(&1, subscription_id))
          {:ok, updated_state}
      end
    end

    @impl true
    def handle_subscription_response(%{"type" => "subscribed", "id" => id}, state) do
      updated_state =
        update_in(state, [:subscriptions, id], fn sub ->
          if sub, do: Map.put(sub, :status, :confirmed), else: sub
        end)

      {:ok, updated_state}
    end

    @impl true
    def handle_subscription_response(%{"type" => "error", "id" => id, "reason" => reason}, state) do
      updated_state =
        update_in(state, [:subscriptions, id], fn sub ->
          if sub do
            sub
            |> Map.put(:status, :failed)
            |> Map.put(:error, reason)
          else
            sub
          end
        end)

      {:error, reason, updated_state}
    end

    @impl true
    def handle_subscription_response(_response, state) do
      {:ok, state}
    end

    @impl true
    def active_subscriptions(state) do
      subscriptions = Map.get(state, :subscriptions, %{})

      subscriptions
      |> Enum.filter(fn {_id, sub} -> Map.get(sub, :status) == :confirmed end)
      |> Map.new()
    end

    @impl true
    def find_subscription_by_channel(channel, state) do
      subscriptions = Map.get(state, :subscriptions, %{})

      Enum.find_value(subscriptions, nil, fn {id, sub} ->
        if sub.channel == channel, do: id
      end)
    end
  end

  describe "subscription manager initialization" do
    test "creates a new manager with defaults" do
      {:ok, manager} = SubscriptionManager.new(TestSubscriptionHandler)
      assert manager.handler == TestSubscriptionHandler
      assert manager.state == %{}
      assert manager.pending_subscriptions == []
    end

    test "creates a new manager with custom initial state" do
      initial_state = %{custom: true, existing_data: "test"}
      {:ok, manager} = SubscriptionManager.new(TestSubscriptionHandler, initial_state)
      assert manager.handler == TestSubscriptionHandler
      assert manager.state == initial_state
      assert manager.pending_subscriptions == []
    end
  end

  describe "subscription operations" do
    setup do
      {:ok, manager} = SubscriptionManager.new(TestSubscriptionHandler)
      {:ok, manager: manager}
    end

    test "subscribes to a channel", %{manager: manager} do
      channel = "market.btcusd.trades"
      params = %{frequency: "100ms"}

      {:ok, subscription_id, updated_manager} = SubscriptionManager.subscribe(manager, channel, params)

      assert is_binary(subscription_id)
      assert updated_manager.state.subscriptions[subscription_id].channel == channel
      assert updated_manager.state.subscriptions[subscription_id].params == params
      assert updated_manager.state.subscriptions[subscription_id].status == :pending
    end

    test "unsubscribes from a channel", %{manager: manager} do
      # First subscribe
      channel = "market.btcusd.trades"
      {:ok, subscription_id, manager} = SubscriptionManager.subscribe(manager, channel, nil)

      # Then unsubscribe
      {:ok, updated_manager} = SubscriptionManager.unsubscribe(manager, subscription_id)

      refute Map.has_key?(updated_manager.state[:subscriptions] || %{}, subscription_id)
    end

    test "handles errors when unsubscribing from non-existent channel", %{manager: manager} do
      result = SubscriptionManager.unsubscribe(manager, "non_existent_id")
      assert {:error, :subscription_not_found, _} = result
    end
  end

  describe "subscription response handling" do
    setup do
      {:ok, manager} = SubscriptionManager.new(TestSubscriptionHandler)
      # Add a couple of subscriptions
      {:ok, sub1, manager} = SubscriptionManager.subscribe(manager, "channel1", nil)
      {:ok, sub2, manager} = SubscriptionManager.subscribe(manager, "channel2", nil)

      {:ok, manager: manager, sub1: sub1, sub2: sub2}
    end

    test "handles successful subscription response", %{manager: manager, sub1: sub1} do
      response = %{"type" => "subscribed", "id" => sub1}

      {:ok, updated_manager} = SubscriptionManager.handle_response(manager, response)

      assert updated_manager.state.subscriptions[sub1].status == :confirmed
    end

    test "handles error subscription response", %{manager: manager, sub2: sub2} do
      response = %{"type" => "error", "id" => sub2, "reason" => "access_denied"}

      {:error, "access_denied", updated_manager} = SubscriptionManager.handle_response(manager, response)

      assert updated_manager.state.subscriptions[sub2].status == :failed
      assert updated_manager.state.subscriptions[sub2].error == "access_denied"
    end

    test "ignores unrelated messages", %{manager: manager} do
      response = %{"type" => "other_message"}

      {:ok, ^manager} = SubscriptionManager.handle_response(manager, response)
    end
  end

  describe "subscription tracking" do
    setup do
      {:ok, manager} = SubscriptionManager.new(TestSubscriptionHandler)
      # Add a couple of subscriptions and confirm one
      {:ok, sub1, manager} = SubscriptionManager.subscribe(manager, "channel1", nil)
      {:ok, sub2, manager} = SubscriptionManager.subscribe(manager, "channel2", nil)

      response = %{"type" => "subscribed", "id" => sub1}
      {:ok, manager} = SubscriptionManager.handle_response(manager, response)

      {:ok, manager: manager, sub1: sub1, sub2: sub2}
    end

    test "retrieves active subscriptions", %{manager: manager, sub1: sub1} do
      active = SubscriptionManager.active_subscriptions(manager)

      assert Map.has_key?(active, sub1)
      assert length(Map.keys(active)) == 1
    end

    test "finds subscription by channel", %{manager: manager} do
      found = SubscriptionManager.find_subscription_by_channel(manager, "channel1")
      not_found = SubscriptionManager.find_subscription_by_channel(manager, "non_existent")

      assert is_binary(found)
      assert is_nil(not_found)
    end
  end

  describe "reconnection handling" do
    setup do
      {:ok, manager} = SubscriptionManager.new(TestSubscriptionHandler)

      # Add confirmed and pending subscriptions
      {:ok, sub1, manager} = SubscriptionManager.subscribe(manager, "channel1", %{param: "value1"})
      {:ok, sub2, manager} = SubscriptionManager.subscribe(manager, "channel2", %{param: "value2"})

      # Confirm first subscription
      response = %{"type" => "subscribed", "id" => sub1}
      {:ok, manager} = SubscriptionManager.handle_response(manager, response)

      {:ok, manager: manager, sub1: sub1, sub2: sub2}
    end

    test "prepares resubscription list for confirmed subscriptions", %{manager: manager, sub1: _sub1} do
      {:ok, updated_manager} = SubscriptionManager.prepare_for_reconnect(manager)

      # The confirmed subscription should be in the pending_subscriptions list
      assert length(updated_manager.pending_subscriptions) == 1

      [{channel, params}] = updated_manager.pending_subscriptions
      assert channel == "channel1"
      assert params.param == "value1"
    end

    test "resubscribes to all pending subscriptions after reconnect", %{manager: manager} do
      # First prepare for reconnect
      {:ok, manager} = SubscriptionManager.prepare_for_reconnect(manager)

      # Then simulate reconnection and resubscribe
      resubscribe_results = SubscriptionManager.resubscribe_after_reconnect(manager)

      # We should have resubscribed to the one confirmed subscription
      assert length(resubscribe_results) == 1

      # Each result should be a tuple with {:ok, subscription_id, manager}
      [{:ok, new_sub_id, updated_manager}] = resubscribe_results

      # The pending_subscriptions list should now be empty
      assert updated_manager.pending_subscriptions == []

      # And we should have the new subscription in our state
      assert updated_manager.state.subscriptions[new_sub_id].channel == "channel1"
      assert updated_manager.state.subscriptions[new_sub_id].params.param == "value1"
    end
  end

  describe "subscription state persistence" do
    test "can export subscription state" do
      {:ok, manager} = SubscriptionManager.new(TestSubscriptionHandler)
      {:ok, _sub1, manager} = SubscriptionManager.subscribe(manager, "channel1", %{priority: "high"})
      {:ok, _sub2, manager} = SubscriptionManager.subscribe(manager, "channel2", %{priority: "medium"})

      exported_state = SubscriptionManager.export_state(manager)

      assert is_map(exported_state)
      assert Map.has_key?(exported_state, :subscriptions)
      assert map_size(exported_state.subscriptions) == 2
    end

    test "can import subscription state" do
      # Create a manager and export its state
      {:ok, original_manager} = SubscriptionManager.new(TestSubscriptionHandler)
      {:ok, sub1, original_manager} = SubscriptionManager.subscribe(original_manager, "channel1", %{priority: "high"})

      exported_state = SubscriptionManager.export_state(original_manager)

      # Create a new manager and import the state
      {:ok, new_manager} = SubscriptionManager.new(TestSubscriptionHandler)
      {:ok, restored_manager} = SubscriptionManager.import_state(new_manager, exported_state)

      # Verify the subscriptions were imported
      assert Map.has_key?(restored_manager.state.subscriptions, sub1)
      assert restored_manager.state.subscriptions[sub1].channel == "channel1"
      assert restored_manager.state.subscriptions[sub1].params.priority == "high"
    end
  end
end
