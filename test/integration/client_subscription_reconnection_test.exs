defmodule WebsockexNova.Integration.ClientSubscriptionReconnectionTest do
  use ExUnit.Case

  alias WebsockexNova.Client

  describe "subscription preservation across reconnections" do
    @moduletag :integration

    defmodule TestReconnectAdapter do
      @moduledoc false
      @behaviour WebsockexNova.Adapter

      use WebsockexNova.Adapter

      alias WebsockexNova.Behaviors.SubscriptionHandler
      alias WebsockexNova.Message.SubscriptionManager

      # Connection Handler
      def connection_info(opts) do
        {:ok,
         %{
           host: opts[:host] || "localhost",
           port: opts[:port] || 8080,
           path: opts[:path] || "/ws",
           transport: :tcp,
           transport_opts: Map.get(opts, :transport_opts, %{}),
           headers: [],
           connection_handler: __MODULE__,
           message_handler: __MODULE__,
           subscription_handler: __MODULE__,
           error_handler: __MODULE__,
           auth_handler: __MODULE__,
           adapter_state: %{
             subscription_manager: nil,
             test_pid: opts[:test_pid]
           }
         }}
      end

      def process_connect(conn, state) do
        # Initialize subscription manager
        {:ok, manager} = SubscriptionManager.new(__MODULE__)
        state = put_in(state, [:adapter_state, :subscription_manager], manager)
        {:ok, conn, state}
      end

      # Message Handler
      def prepare_frame(message, options, state) do
        case message do
          %{method: "subscribe", params: %{channel: channel, opts: opts}} ->
            # Use subscription manager to handle subscription
            manager = get_in(state, [:adapter_state, :subscription_manager])
            {:ok, sub_id, updated_manager} = SubscriptionManager.subscribe(manager, channel, opts)

            updated_state = put_in(state, [:adapter_state, :subscription_manager], updated_manager)

            frame =
              {:text,
               Jason.encode!(%{
                 id: sub_id,
                 method: "subscribe",
                 params: %{channel: channel}
               })}

            {:ok, frame, updated_state}

          _ ->
            {:ok, {:text, Jason.encode!(message)}, state}
        end
      end

      def handle_frame(frame, conn, state) do
        case frame do
          {:text, data} ->
            case Jason.decode(data) do
              {:ok, %{"type" => "subscribed", "id" => sub_id}} ->
                # Confirm subscription in manager
                manager = get_in(state, [:adapter_state, :subscription_manager])

                {:ok, updated_manager} =
                  SubscriptionManager.handle_response(manager, %{"type" => "subscribed", "id" => sub_id})

                updated_state = put_in(state, [:adapter_state, :subscription_manager], updated_manager)

                # Notify test process
                if test_pid = get_in(state, [:adapter_state, :test_pid]) do
                  send(test_pid, {:subscription_confirmed, sub_id})
                end

                {:ok, conn, updated_state}

              _ ->
                {:ok, conn, state}
            end

          _ ->
            {:ok, conn, state}
        end
      end

      # Error Handler
      def handle_disconnect(reason, conn, state) do
        # Prepare subscriptions for reconnect
        manager = get_in(state, [:adapter_state, :subscription_manager])

        if manager do
          {:ok, updated_manager} = SubscriptionManager.prepare_for_reconnect(manager)
          state = put_in(state, [:adapter_state, :subscription_manager], updated_manager)
        end

        {:reconnect, conn, state}
      end

      # Auth Handler - no-op for this test
      def get_auth_config(_, _), do: {:ok, %{enabled: false}}
      def is_authenticated?(_, _), do: {:ok, true}

      # Connection Handler
      def ping(conn, state) do
        frame = {:ping, ""}
        {:ok, frame, conn, state}
      end

      def handle_connect(conn, state) do
        # On reconnection, restore subscriptions
        manager = get_in(state, [:adapter_state, :subscription_manager])

        if manager do
          # Get pending reconnect subscriptions
          pending = Map.get(manager.state, :pending_reconnect_subscriptions, [])

          if length(pending) > 0 do
            # Notify test process about reconnection
            if test_pid = get_in(state, [:adapter_state, :test_pid]) do
              send(test_pid, {:reconnecting_with_subscriptions, length(pending)})
            end

            # Resubscribe to all channels
            results = SubscriptionManager.resubscribe_after_reconnect(manager)

            # Process results and update state
            final_state =
              Enum.reduce(results, state, fn
                {:ok, sub_id, updated_manager}, acc_state ->
                  # Send the resubscribe frame
                  channel = get_in(updated_manager.state, [:subscriptions, sub_id, :channel])

                  frame_data =
                    Jason.encode!(%{
                      id: sub_id,
                      method: "subscribe",
                      params: %{channel: channel}
                    })

                  # We'll need to actually send this, which requires connection
                  # For now, just update the state
                  put_in(acc_state, [:adapter_state, :subscription_manager], updated_manager)

                {:error, _, updated_manager}, acc_state ->
                  put_in(acc_state, [:adapter_state, :subscription_manager], updated_manager)
              end)

            {:ok, conn, final_state}
          else
            {:ok, conn, state}
          end
        else
          {:ok, conn, state}
        end
      end

      # Subscription Handler implementation for SubscriptionManager
      def subscription_init(_opts), do: {:ok, %{subscriptions: %{}}}

      def subscribe(channel, params, state) do
        sub_id = "sub_#{System.unique_integer([:positive, :monotonic])}"
        subscriptions = Map.get(state, :subscriptions, %{})

        subscription = %{
          channel: channel,
          params: params,
          status: :pending
        }

        updated_state = Map.put(state, :subscriptions, Map.put(subscriptions, sub_id, subscription))
        {:ok, sub_id, updated_state}
      end

      def unsubscribe(sub_id, state) do
        updated_subscriptions = Map.delete(state.subscriptions, sub_id)
        {:ok, %{state | subscriptions: updated_subscriptions}}
      end

      def handle_subscription_response(%{"type" => "subscribed", "id" => sub_id}, state) do
        updated_state = put_in(state, [:subscriptions, sub_id, :status], :confirmed)
        {:ok, updated_state}
      end

      def handle_subscription_response(_, state), do: {:ok, state}

      def active_subscriptions(state) do
        state.subscriptions
        |> Enum.filter(fn {_, sub} -> sub.status == :confirmed end)
        |> Map.new()
      end

      def find_subscription_by_channel(channel, state) do
        Enum.find_value(state.subscriptions, nil, fn {id, sub} ->
          if sub.channel == channel, do: id
        end)
      end
    end

    # Requires mock server that supports disconnect/reconnect
    @tag :skip
    test "preserves subscriptions when connection is restored" do
      self_pid = self()

      opts = %{
        host: "localhost",
        port: 8080,
        test_pid: self_pid
      }

      # Connect and subscribe
      {:ok, conn} = Client.connect(TestReconnectAdapter, opts)

      # Subscribe to multiple channels
      Client.send_message(conn, %{method: "subscribe", params: %{channel: "ticker.btc", opts: %{}}})
      assert_receive {:subscription_confirmed, _sub_id1}, 1000

      Client.send_message(conn, %{method: "subscribe", params: %{channel: "trades.btc", opts: %{}}})
      assert_receive {:subscription_confirmed, _sub_id2}, 1000

      # Force disconnection
      # This would typically be done by shutting down the mock server
      # For now, we'll just simulate the process

      # On real reconnection, we should receive notification
      assert_receive {:reconnecting_with_subscriptions, 2}, 5000

      # Verify subscriptions are restored
      assert_receive {:subscription_confirmed, _new_sub_id1}, 1000
      assert_receive {:subscription_confirmed, _new_sub_id2}, 1000
    end
  end
end
