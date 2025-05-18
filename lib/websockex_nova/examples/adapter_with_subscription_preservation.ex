defmodule WebsockexNova.Examples.AdapterWithSubscriptionPreservation do
  @moduledoc """
  Example adapter demonstrating subscription preservation across reconnections.

  This adapter uses the SubscriptionManager to track and restore subscriptions
  automatically when the connection is re-established after a disconnection.
  """

  use WebsockexNova.Adapter

  alias WebsockexNova.Behaviors.ConnectionHandler
  alias WebsockexNova.Behaviors.MessageHandler
  alias WebsockexNova.Behaviors.SubscriptionHandler
  alias WebsockexNova.ClientConn
  alias WebsockexNova.Message.SubscriptionManager

  require Logger

  @impl true
  def init(opts) do
    # Initialize with SubscriptionManager
    {:ok, manager} = SubscriptionManager.new(__MODULE__)

    {:ok,
     %{
       subscription_manager: manager,
       credentials: opts[:credentials],
       options: opts
     }}
  end

  @impl ConnectionHandler
  def connection_info(opts) do
    {:ok,
     %{
       host: opts[:host] || "localhost",
       port: opts[:port] || 8080,
       path: opts[:path] || "/ws",
       transport: :tcp,
       headers: [],
       connection_handler: __MODULE__,
       message_handler: __MODULE__,
       subscription_handler: __MODULE__,
       error_handler: __MODULE__,
       auth_handler: __MODULE__
     }}
  end

  @impl ConnectionHandler
  def handle_connect(conn_info, state) do
    # Check if this is a reconnection
    if Map.get(conn_info, :reconnected, false) do
      Logger.info("[AdapterWithSubscriptionPreservation] Reconnection detected, restoring subscriptions")

      # Get subscription manager from state
      manager = get_in(state, [:adapter_state, :subscription_manager])

      if manager do
        # Resubscribe to all channels
        results = SubscriptionManager.resubscribe_after_reconnect(manager)

        # Process results and send subscription frames
        {frames, final_manager} =
          Enum.reduce(results, {[], manager}, fn
            {:ok, sub_id, updated_manager}, {frames_acc, _} ->
              # Get subscription details
              channel = get_in(updated_manager.state, [:subscriptions, sub_id, :channel])
              params = get_in(updated_manager.state, [:subscriptions, sub_id, :params])

              # Create subscription frame
              frame = %{
                id: sub_id,
                method: "subscribe",
                params: Map.merge(%{channel: channel}, params || %{})
              }

              {[frame | frames_acc], updated_manager}

            {:error, reason, updated_manager}, {frames_acc, _} ->
              Logger.warning("Failed to restore subscription: #{inspect(reason)}")
              {frames_acc, updated_manager}
          end)

        # Update state with new manager
        updated_state = put_in(state, [:adapter_state, :subscription_manager], final_manager)

        # Send all frames in reverse order (to maintain original order)
        frames
        |> Enum.reverse()
        |> Enum.reduce({:ok, updated_state}, fn frame, {:ok, acc_state} ->
          # Use the message handler to prepare and send frames
          case prepare_frame(frame, %{}, acc_state) do
            {:ok, ws_frame, new_state} ->
              {:reply, elem(ws_frame, 0), elem(ws_frame, 1), new_state}

            error ->
              error
          end
        end)
      else
        Logger.debug("No subscription manager found, skipping subscription restoration")
        {:ok, state}
      end
    else
      # Normal connection
      {:ok, state}
    end
  end

  @impl ConnectionHandler
  def handle_disconnect(reason, state) do
    # Prepare subscriptions for reconnect
    manager = get_in(state, [:adapter_state, :subscription_manager])

    if manager do
      {:ok, updated_manager} = SubscriptionManager.prepare_for_reconnect(manager)
      updated_state = put_in(state, [:adapter_state, :subscription_manager], updated_manager)

      # Allow reconnection
      {:reconnect, updated_state}
    else
      {:reconnect, state}
    end
  end

  @impl MessageHandler
  def prepare_frame(message, _options, state) do
    case message do
      %{method: "subscribe", params: %{channel: channel} = params} ->
        # Use subscription manager
        manager = get_in(state, [:adapter_state, :subscription_manager])

        if manager do
          {:ok, sub_id, updated_manager} = SubscriptionManager.subscribe(manager, channel, params)

          updated_state = put_in(state, [:adapter_state, :subscription_manager], updated_manager)

          frame =
            {:text,
             Jason.encode!(%{
               id: sub_id,
               method: "subscribe",
               params: params
             })}

          {:ok, frame, updated_state}
        else
          # Fallback if no manager
          frame = {:text, Jason.encode!(message)}
          {:ok, frame, state}
        end

      %{method: "unsubscribe", params: %{subscription_id: sub_id}} ->
        # Use subscription manager
        manager = get_in(state, [:adapter_state, :subscription_manager])

        if manager do
          case SubscriptionManager.unsubscribe(manager, sub_id) do
            {:ok, updated_manager} ->
              updated_state = put_in(state, [:adapter_state, :subscription_manager], updated_manager)

              frame =
                {:text,
                 Jason.encode!(%{
                   id: sub_id,
                   method: "unsubscribe"
                 })}

              {:ok, frame, updated_state}

            {:error, reason, updated_manager} ->
              updated_state = put_in(state, [:adapter_state, :subscription_manager], updated_manager)
              {:error, reason, updated_state}
          end
        else
          frame = {:text, Jason.encode!(message)}
          {:ok, frame, state}
        end

      _ ->
        # Other messages
        frame = {:text, Jason.encode!(message)}
        {:ok, frame, state}
    end
  end

  @impl MessageHandler
  def handle_frame({:text, data}, conn, state) do
    case Jason.decode(data) do
      {:ok, %{"type" => "subscribed", "id" => sub_id}} ->
        # Confirm subscription in manager
        manager = get_in(state, [:adapter_state, :subscription_manager])

        if manager do
          {:ok, updated_manager} = SubscriptionManager.handle_response(manager, %{"type" => "subscribed", "id" => sub_id})
          updated_state = put_in(state, [:adapter_state, :subscription_manager], updated_manager)
          {:ok, conn, updated_state}
        else
          {:ok, conn, state}
        end

      _ ->
        {:ok, conn, state}
    end
  end

  def handle_frame(_frame, conn, state) do
    {:ok, conn, state}
  end

  # SubscriptionHandler callbacks for SubscriptionManager
  @impl SubscriptionHandler
  def subscription_init(_opts), do: {:ok, %{subscriptions: %{}}}

  @impl SubscriptionHandler
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

  @impl SubscriptionHandler
  def unsubscribe(sub_id, state) do
    updated_subscriptions = Map.delete(state.subscriptions, sub_id)
    {:ok, %{state | subscriptions: updated_subscriptions}}
  end

  @impl SubscriptionHandler
  def handle_subscription_response(%{"type" => "subscribed", "id" => sub_id}, state) do
    updated_state = put_in(state, [:subscriptions, sub_id, :status], :confirmed)
    {:ok, updated_state}
  end

  def handle_subscription_response(_, state), do: {:ok, state}

  @impl SubscriptionHandler
  def active_subscriptions(state) do
    state.subscriptions
    |> Enum.filter(fn {_, sub} -> sub.status == :confirmed end)
    |> Map.new()
  end

  @impl SubscriptionHandler
  def find_subscription_by_channel(channel, state) do
    Enum.find_value(state.subscriptions, nil, fn {id, sub} ->
      if sub.channel == channel, do: id
    end)
  end
end
