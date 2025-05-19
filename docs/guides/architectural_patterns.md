# Architectural Patterns

This guide explores proven architectural patterns for building scalable, maintainable WebSocket applications with WebsockexNova.

## Table of Contents
1. [System Architecture Patterns](#system-architecture-patterns)
2. [Connection Management Patterns](#connection-management-patterns)
3. [Message Flow Patterns](#message-flow-patterns)
4. [State Management Patterns](#state-management-patterns)
5. [Error Handling Patterns](#error-handling-patterns)
6. [Scaling Patterns](#scaling-patterns)
7. [Security Patterns](#security-patterns)
8. [Integration Patterns](#integration-patterns)

## System Architecture Patterns

### Layered Architecture

Organize your WebSocket system in layers:

```elixir
defmodule MyApp.Architecture do
  @moduledoc """
  Four-layer architecture for WebSocket applications
  """
  
  # Layer 1: Connection Layer
  defmodule ConnectionLayer do
    defmodule Gateway do
      use WebsockexNova.ClientMacro, adapter: MyApp.Adapter
      
      # Handle raw connection management
      def establish_connection(config) do
        connect(config)
      end
    end
  end
  
  # Layer 2: Protocol Layer
  defmodule ProtocolLayer do
    defmodule MessageProtocol do
      def encode(message) do
        Jason.encode!(message)
      end
      
      def decode(text) do
        Jason.decode(text)
      end
    end
    
    defmodule FrameProtocol do
      def wrap_message(encoded, type \\ :text) do
        {type, encoded}
      end
    end
  end
  
  # Layer 3: Business Logic Layer
  defmodule BusinessLayer do
    defmodule OrderService do
      def place_order(conn, order_params) do
        with {:ok, validated} <- validate_order(order_params),
             {:ok, enriched} <- enrich_order(validated),
             {:ok, response} <- send_order(conn, enriched) do
          process_response(response)
        end
      end
    end
    
    defmodule MarketDataService do
      def subscribe_to_market(conn, symbols) do
        Enum.map(symbols, fn symbol ->
          MyApp.Client.subscribe(conn, "market.#{symbol}")
        end)
      end
    end
  end
  
  # Layer 4: Application Layer
  defmodule ApplicationLayer do
    defmodule TradingApp do
      def start do
        {:ok, conn} = ConnectionLayer.Gateway.establish_connection(%{})
        {:ok, conn} = authenticate(conn)
        
        # Subscribe to market data
        BusinessLayer.MarketDataService.subscribe_to_market(conn, ["BTC", "ETH"])
        
        # Start trading logic
        BusinessLayer.OrderService.start_trading(conn)
      end
    end
  end
end
```

### Microservice Architecture

Build WebSocket microservices:

```elixir
defmodule MyApp.MicroserviceArchitecture do
  # Gateway Service
  defmodule GatewayService do
    use WebsockexNova.ClientMacro, adapter: MyApp.GatewayAdapter
    
    def route_message(conn, message) do
      case message["service"] do
        "auth" -> forward_to_auth_service(message)
        "trading" -> forward_to_trading_service(message)
        "market" -> forward_to_market_service(message)
        _ -> {:error, :unknown_service}
      end
    end
  end
  
  # Auth Service
  defmodule AuthService do
    use GenServer
    
    def authenticate(credentials) do
      GenServer.call(__MODULE__, {:authenticate, credentials})
    end
    
    def handle_call({:authenticate, credentials}, _from, state) do
      result = verify_credentials(credentials)
      {:reply, result, state}
    end
  end
  
  # Trading Service
  defmodule TradingService do
    use WebsockexNova.ClientMacro, adapter: MyApp.TradingAdapter
    
    def handle_order(conn, order) do
      with {:ok, validated} <- validate_order(order),
           {:ok, executed} <- execute_order(conn, validated) do
        publish_event({:order_executed, executed})
      end
    end
  end
  
  # Event Bus
  defmodule EventBus do
    use GenServer
    
    def publish(event) do
      GenServer.cast(__MODULE__, {:publish, event})
    end
    
    def subscribe(topic, pid) do
      GenServer.call(__MODULE__, {:subscribe, topic, pid})
    end
  end
end
```

### Event-Driven Architecture

Implement event-driven patterns:

```elixir
defmodule MyApp.EventDrivenArchitecture do
  # Event Definitions
  defmodule Events do
    defstruct [:type, :payload, :timestamp, :correlation_id]
    
    def new(type, payload) do
      %__MODULE__{
        type: type,
        payload: payload,
        timestamp: DateTime.utc_now(),
        correlation_id: generate_correlation_id()
      }
    end
  end
  
  # Event Store
  defmodule EventStore do
    use GenServer
    
    def append(event) do
      GenServer.call(__MODULE__, {:append, event})
    end
    
    def get_events(filter) do
      GenServer.call(__MODULE__, {:get_events, filter})
    end
    
    @impl true
    def handle_call({:append, event}, _from, state) do
      new_state = [event | state.events]
      notify_subscribers(event)
      {:reply, :ok, %{state | events: new_state}}
    end
  end
  
  # Event Handlers
  defmodule OrderEventHandler do
    use WebsockexNova.Behaviors.MessageHandler
    
    @impl true
    def handle_text_frame(text, state) do
      case Jason.decode(text) do
        {:ok, %{"type" => "order"} = msg} ->
          event = Events.new(:order_received, msg)
          EventStore.append(event)
          process_order_event(event, state)
        
        _ ->
          {:ok, state}
      end
    end
    
    defp process_order_event(event, state) do
      # Trigger workflows based on event
      case event.payload["action"] do
        "create" -> OrderWorkflow.start_create(event)
        "cancel" -> OrderWorkflow.start_cancel(event)
        "modify" -> OrderWorkflow.start_modify(event)
      end
      
      {:ok, state}
    end
  end
  
  # Event Sourcing
  defmodule OrderAggregate do
    defstruct [:id, :status, :items, :total]
    
    def apply_event(%__MODULE__{} = order, event) do
      case event.type do
        :order_created ->
          %{order | 
            id: event.payload.id,
            status: :pending,
            items: event.payload.items
          }
        
        :order_confirmed ->
          %{order | status: :confirmed}
        
        :order_cancelled ->
          %{order | status: :cancelled}
        
        _ ->
          order
      end
    end
    
    def rebuild_from_events(events) do
      Enum.reduce(events, %__MODULE__{}, &apply_event(&2, &1))
    end
  end
end
```

## Connection Management Patterns

### Connection Pool Pattern

Manage a pool of WebSocket connections:

```elixir
defmodule MyApp.ConnectionPool do
  use GenServer
  
  defstruct [
    :adapter,
    :size,
    :connections,
    :available,
    :config
  ]
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def checkout do
    GenServer.call(__MODULE__, :checkout, 5000)
  end
  
  def checkin(conn) do
    GenServer.cast(__MODULE__, {:checkin, conn})
  end
  
  @impl true
  def init(opts) do
    state = %__MODULE__{
      adapter: opts[:adapter],
      size: opts[:size] || 10,
      connections: [],
      available: :queue.new(),
      config: opts[:config] || %{}
    }
    
    {:ok, state, {:continue, :create_connections}}
  end
  
  @impl true
  def handle_continue(:create_connections, state) do
    connections = for i <- 1..state.size do
      {:ok, conn} = WebsockexNova.Client.connect(state.adapter, state.config)
      conn
    end
    
    available = Enum.reduce(connections, state.available, &:queue.in/2)
    
    {:noreply, %{state | connections: connections, available: available}}
  end
  
  @impl true
  def handle_call(:checkout, from, state) do
    case :queue.out(state.available) do
      {{:value, conn}, new_available} ->
        {:reply, {:ok, conn}, %{state | available: new_available}}
      
      {:empty, _} ->
        # Could implement waiting queue here
        {:reply, {:error, :no_connections_available}, state}
    end
  end
end
```

### Load Balancer Pattern

Balance connections across multiple endpoints:

```elixir
defmodule MyApp.LoadBalancer do
  use GenServer
  
  defmodule Strategy do
    @callback select_endpoint(endpoints :: list(), state :: map()) :: 
      {:ok, endpoint :: map(), new_state :: map()}
  end
  
  defmodule RoundRobinStrategy do
    @behaviour Strategy
    
    @impl true
    def select_endpoint(endpoints, state) do
      index = Map.get(state, :index, 0)
      endpoint = Enum.at(endpoints, rem(index, length(endpoints)))
      
      new_state = Map.put(state, :index, index + 1)
      {:ok, endpoint, new_state}
    end
  end
  
  defmodule LeastConnectionsStrategy do
    @behaviour Strategy
    
    @impl true
    def select_endpoint(endpoints, state) do
      counts = Map.get(state, :connection_counts, %{})
      
      {endpoint, _count} = endpoints
        |> Enum.map(fn ep -> {ep, Map.get(counts, ep.id, 0)} end)
        |> Enum.min_by(fn {_ep, count} -> count end)
      
      new_counts = Map.update(counts, endpoint.id, 1, &(&1 + 1))
      new_state = Map.put(state, :connection_counts, new_counts)
      
      {:ok, endpoint, new_state}
    end
  end
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def connect do
    GenServer.call(__MODULE__, :connect)
  end
  
  @impl true
  def handle_call(:connect, _from, state) do
    {:ok, endpoint, new_state} = state.strategy.select_endpoint(
      state.endpoints, 
      state.strategy_state
    )
    
    case WebsockexNova.Client.connect(state.adapter, endpoint) do
      {:ok, conn} ->
        {:reply, {:ok, conn}, %{state | strategy_state: new_state}}
      
      error ->
        {:reply, error, state}
    end
  end
end
```

### Circuit Breaker Pattern

Implement circuit breaker for connection failures:

```elixir
defmodule MyApp.CircuitBreaker do
  use GenServer
  
  defstruct [
    :state,  # :closed, :open, :half_open
    :failure_count,
    :success_count,
    :failure_threshold,
    :success_threshold,
    :timeout,
    :last_failure_time
  ]
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def call(fun) do
    GenServer.call(__MODULE__, {:call, fun})
  end
  
  @impl true
  def init(opts) do
    state = %__MODULE__{
      state: :closed,
      failure_count: 0,
      success_count: 0,
      failure_threshold: opts[:failure_threshold] || 5,
      success_threshold: opts[:success_threshold] || 3,
      timeout: opts[:timeout] || 60_000
    }
    
    {:ok, state}
  end
  
  @impl true
  def handle_call({:call, fun}, _from, state) do
    case state.state do
      :open ->
        if should_attempt_reset?(state) do
          attempt_call(fun, %{state | state: :half_open})
        else
          {:reply, {:error, :circuit_open}, state}
        end
      
      :closed ->
        attempt_call(fun, state)
      
      :half_open ->
        attempt_call(fun, state)
    end
  end
  
  defp attempt_call(fun, state) do
    try do
      result = fun.()
      new_state = handle_success(state)
      {:reply, result, new_state}
    rescue
      e ->
        new_state = handle_failure(state)
        {:reply, {:error, e}, new_state}
    end
  end
  
  defp handle_success(state) do
    case state.state do
      :half_open ->
        if state.success_count + 1 >= state.success_threshold do
          %{state | state: :closed, failure_count: 0, success_count: 0}
        else
          %{state | success_count: state.success_count + 1}
        end
      
      _ ->
        %{state | failure_count: 0}
    end
  end
  
  defp handle_failure(state) do
    failure_count = state.failure_count + 1
    
    if failure_count >= state.failure_threshold do
      %{state | 
        state: :open,
        failure_count: failure_count,
        last_failure_time: System.monotonic_time(:millisecond)
      }
    else
      %{state | failure_count: failure_count}
    end
  end
end
```

## Message Flow Patterns

### Pipeline Pattern

Process messages through a pipeline:

```elixir
defmodule MyApp.MessagePipeline do
  defmodule Stage do
    @callback process(message :: term(), context :: map()) :: 
      {:ok, message :: term(), context :: map()} | 
      {:error, reason :: term()}
  end
  
  defmodule ValidationStage do
    @behaviour Stage
    
    @impl true
    def process(message, context) do
      case validate_message(message) do
        :ok -> {:ok, message, context}
        error -> {:error, error}
      end
    end
  end
  
  defmodule TransformationStage do
    @behaviour Stage
    
    @impl true
    def process(message, context) do
      transformed = transform_message(message, context.transform_rules)
      {:ok, transformed, context}
    end
  end
  
  defmodule RoutingStage do
    @behaviour Stage
    
    @impl true
    def process(message, context) do
      destination = determine_destination(message)
      new_context = Map.put(context, :destination, destination)
      {:ok, message, new_context}
    end
  end
  
  def create_pipeline(stages) do
    fn initial_message, initial_context ->
      Enum.reduce_while(stages, {:ok, initial_message, initial_context}, fn
        stage, {:ok, message, context} ->
          case stage.process(message, context) do
            {:ok, _, _} = result -> {:cont, result}
            {:error, _} = error -> {:halt, error}
          end
      end)
    end
  end
  
  # Usage
  def process_incoming_message(raw_message) do
    pipeline = create_pipeline([
      ValidationStage,
      TransformationStage,
      RoutingStage
    ])
    
    context = %{transform_rules: get_transform_rules()}
    
    case pipeline.(raw_message, context) do
      {:ok, processed_message, final_context} ->
        deliver_message(processed_message, final_context.destination)
      
      {:error, reason} ->
        handle_pipeline_error(reason)
    end
  end
end
```

### Publish-Subscribe Pattern

Implement pub-sub messaging:

```elixir
defmodule MyApp.PubSub do
  use GenServer
  
  defmodule Topic do
    defstruct [:name, :subscribers, :patterns]
    
    def new(name) do
      %__MODULE__{
        name: name,
        subscribers: MapSet.new(),
        patterns: []
      }
    end
    
    def add_subscriber(topic, pid) do
      %{topic | subscribers: MapSet.put(topic.subscribers, pid)}
    end
    
    def remove_subscriber(topic, pid) do
      %{topic | subscribers: MapSet.delete(topic.subscribers, pid)}
    end
  end
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def subscribe(topic, pid \\ self()) do
    GenServer.call(__MODULE__, {:subscribe, topic, pid})
  end
  
  def unsubscribe(topic, pid \\ self()) do
    GenServer.call(__MODULE__, {:unsubscribe, topic, pid})
  end
  
  def publish(topic, message) do
    GenServer.cast(__MODULE__, {:publish, topic, message})
  end
  
  @impl true
  def init(_opts) do
    {:ok, %{topics: %{}, patterns: []}}
  end
  
  @impl true
  def handle_call({:subscribe, topic_name, pid}, _from, state) do
    Process.monitor(pid)
    
    topics = Map.update(
      state.topics,
      topic_name,
      Topic.new(topic_name) |> Topic.add_subscriber(pid),
      &Topic.add_subscriber(&1, pid)
    )
    
    {:reply, :ok, %{state | topics: topics}}
  end
  
  @impl true
  def handle_cast({:publish, topic_name, message}, state) do
    case Map.get(state.topics, topic_name) do
      nil -> 
        {:noreply, state}
      
      topic ->
        Enum.each(topic.subscribers, fn pid ->
          send(pid, {:pubsub_message, topic_name, message})
        end)
        
        {:noreply, state}
    end
  end
  
  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    topics = state.topics
      |> Enum.map(fn {name, topic} ->
        {name, Topic.remove_subscriber(topic, pid)}
      end)
      |> Enum.into(%{})
    
    {:noreply, %{state | topics: topics}}
  end
end
```

### Message Queue Pattern

Implement message queuing with priorities:

```elixir
defmodule MyApp.MessageQueue do
  use GenServer
  
  defmodule PriorityQueue do
    defstruct high: :queue.new(), normal: :queue.new(), low: :queue.new()
    
    def new, do: %__MODULE__{}
    
    def push(%__MODULE__{} = pq, item, :high) do
      %{pq | high: :queue.in(item, pq.high)}
    end
    
    def push(%__MODULE__{} = pq, item, :normal) do
      %{pq | normal: :queue.in(item, pq.normal)}
    end
    
    def push(%__MODULE__{} = pq, item, :low) do
      %{pq | low: :queue.in(item, pq.low)}
    end
    
    def pop(%__MODULE__{} = pq) do
      cond do
        not :queue.is_empty(pq.high) ->
          {{:value, item}, rest} = :queue.out(pq.high)
          {item, %{pq | high: rest}}
        
        not :queue.is_empty(pq.normal) ->
          {{:value, item}, rest} = :queue.out(pq.normal)
          {item, %{pq | normal: rest}}
        
        not :queue.is_empty(pq.low) ->
          {{:value, item}, rest} = :queue.out(pq.low)
          {item, %{pq | low: rest}}
        
        true ->
          {nil, pq}
      end
    end
  end
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def enqueue(message, priority \\ :normal) do
    GenServer.cast(__MODULE__, {:enqueue, message, priority})
  end
  
  def dequeue do
    GenServer.call(__MODULE__, :dequeue)
  end
  
  @impl true
  def init(_opts) do
    {:ok, %{queue: PriorityQueue.new(), workers: [], processing: false}}
  end
  
  @impl true
  def handle_cast({:enqueue, message, priority}, state) do
    new_queue = PriorityQueue.push(state.queue, message, priority)
    new_state = %{state | queue: new_queue}
    
    if not state.processing do
      send(self(), :process_queue)
      {:noreply, %{new_state | processing: true}}
    else
      {:noreply, new_state}
    end
  end
  
  @impl true
  def handle_info(:process_queue, state) do
    case PriorityQueue.pop(state.queue) do
      {nil, _queue} ->
        {:noreply, %{state | processing: false}}
      
      {message, new_queue} ->
        # Process message asynchronously
        Task.async(fn -> process_message(message) end)
        
        # Continue processing
        send(self(), :process_queue)
        {:noreply, %{state | queue: new_queue}}
    end
  end
end
```

## State Management Patterns

### CQRS Pattern

Implement Command Query Responsibility Segregation:

```elixir
defmodule MyApp.CQRS do
  # Command Side
  defmodule Commands do
    defmodule CreateOrder do
      defstruct [:order_id, :items, :customer_id]
    end
    
    defmodule UpdateOrderStatus do
      defstruct [:order_id, :status]
    end
  end
  
  defmodule CommandHandler do
    def handle(%Commands.CreateOrder{} = cmd) do
      with {:ok, order} <- validate_order(cmd),
           {:ok, _} <- save_order(order),
           :ok <- publish_event({:order_created, order}) do
        {:ok, order.id}
      end
    end
    
    def handle(%Commands.UpdateOrderStatus{} = cmd) do
      with {:ok, order} <- get_order(cmd.order_id),
           {:ok, updated} <- update_status(order, cmd.status),
           :ok <- publish_event({:order_status_updated, updated}) do
        {:ok, updated}
      end
    end
  end
  
  # Query Side
  defmodule Queries do
    defmodule GetOrder do
      defstruct [:order_id]
    end
    
    defmodule GetOrdersByCustomer do
      defstruct [:customer_id, :status]
    end
  end
  
  defmodule QueryHandler do
    def handle(%Queries.GetOrder{order_id: id}) do
      ReadModel.get_order(id)
    end
    
    def handle(%Queries.GetOrdersByCustomer{} = query) do
      ReadModel.get_orders_by_customer(query.customer_id, query.status)
    end
  end
  
  # Read Model
  defmodule ReadModel do
    use GenServer
    
    def get_order(id) do
      GenServer.call(__MODULE__, {:get_order, id})
    end
    
    def get_orders_by_customer(customer_id, status) do
      GenServer.call(__MODULE__, {:get_by_customer, customer_id, status})
    end
    
    @impl true
    def handle_call({:get_order, id}, _from, state) do
      order = Map.get(state.orders, id)
      {:reply, order, state}
    end
    
    # Update read model based on events
    def handle_info({:event, {:order_created, order}}, state) do
      new_orders = Map.put(state.orders, order.id, order)
      {:noreply, %{state | orders: new_orders}}
    end
  end
end
```

### Saga Pattern

Implement distributed transactions with sagas:

```elixir
defmodule MyApp.OrderSaga do
  use GenStateMachine
  
  defmodule State do
    defstruct [
      :order_id,
      :customer_id,
      :items,
      :payment_id,
      :shipment_id,
      :status
    ]
  end
  
  def start_link(order_data) do
    GenStateMachine.start_link(__MODULE__, order_data)
  end
  
  @impl true
  def init(order_data) do
    state = %State{
      order_id: generate_id(),
      customer_id: order_data.customer_id,
      items: order_data.items,
      status: :started
    }
    
    {:ok, :order_created, state, [{:next_event, :internal, :reserve_inventory}]}
  end
  
  @impl true
  def handle_event(:internal, :reserve_inventory, :order_created, state) do
    case InventoryService.reserve(state.items) do
      {:ok, reservation_id} ->
        new_state = %{state | reservation_id: reservation_id}
        {:next_state, :inventory_reserved, new_state, 
         [{:next_event, :internal, :process_payment}]}
      
      {:error, reason} ->
        {:next_state, :failed, %{state | failure_reason: reason},
         [{:next_event, :internal, :compensate}]}
    end
  end
  
  @impl true
  def handle_event(:internal, :process_payment, :inventory_reserved, state) do
    case PaymentService.charge(state.customer_id, calculate_total(state.items)) do
      {:ok, payment_id} ->
        new_state = %{state | payment_id: payment_id}
        {:next_state, :payment_processed, new_state,
         [{:next_event, :internal, :arrange_shipping}]}
      
      {:error, reason} ->
        {:next_state, :failed, %{state | failure_reason: reason},
         [{:next_event, :internal, :compensate}]}
    end
  end
  
  # Compensation logic
  @impl true
  def handle_event(:internal, :compensate, :failed, state) do
    compensations = []
    
    if state.payment_id do
      compensations ++ [fn -> PaymentService.refund(state.payment_id) end]
    end
    
    if state.reservation_id do
      compensations ++ [fn -> InventoryService.cancel_reservation(state.reservation_id) end]
    end
    
    Enum.each(compensations, & &1.())
    
    {:stop, :normal, state}
  end
end
```

## Error Handling Patterns

### Retry Pattern

Implement intelligent retry logic:

```elixir
defmodule MyApp.RetryPattern do
  defmodule Retry do
    defstruct [
      :max_attempts,
      :backoff_type,
      :base_delay,
      :max_delay,
      :jitter
    ]
    
    def exponential_backoff(attempt, config) do
      delay = config.base_delay * :math.pow(2, attempt - 1)
      delay = min(delay, config.max_delay)
      
      if config.jitter do
        add_jitter(delay)
      else
        delay
      end
    end
    
    def linear_backoff(attempt, config) do
      delay = config.base_delay * attempt
      min(delay, config.max_delay)
    end
    
    defp add_jitter(delay) do
      jitter = :rand.uniform() * delay * 0.1
      delay + jitter
    end
  end
  
  def with_retry(fun, config \\ default_config()) do
    do_retry(fun, config, 1)
  end
  
  defp do_retry(fun, config, attempt) when attempt <= config.max_attempts do
    case fun.() do
      {:ok, result} ->
        {:ok, result}
      
      {:error, reason} ->
        if should_retry?(reason) and attempt < config.max_attempts do
          delay = calculate_delay(attempt, config)
          Process.sleep(round(delay))
          do_retry(fun, config, attempt + 1)
        else
          {:error, {:max_retries, reason}}
        end
    end
  end
  
  defp do_retry(_fun, _config, _attempt) do
    {:error, :max_attempts_exceeded}
  end
  
  defp should_retry?(:temporary_failure), do: true
  defp should_retry?(:network_error), do: true
  defp should_retry?({:http_error, code}) when code >= 500, do: true
  defp should_retry?(_), do: false
  
  defp calculate_delay(attempt, config) do
    case config.backoff_type do
      :exponential -> Retry.exponential_backoff(attempt, config)
      :linear -> Retry.linear_backoff(attempt, config)
      :constant -> config.base_delay
    end
  end
  
  defp default_config do
    %Retry{
      max_attempts: 3,
      backoff_type: :exponential,
      base_delay: 1000,
      max_delay: 30000,
      jitter: true
    }
  end
end
```

### Error Boundary Pattern

Isolate errors to prevent cascading failures:

```elixir
defmodule MyApp.ErrorBoundary do
  use Supervisor
  
  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @impl true
  def init(_opts) do
    children = [
      {MyApp.ConnectionSupervisor, []},
      {MyApp.MessageProcessor, []},
      {MyApp.StateManager, []}
    ]
    
    # Restart only the failed child
    Supervisor.init(children, strategy: :one_for_one)
  end
  
  defmodule ConnectionSupervisor do
    use Supervisor
    
    def start_link(opts) do
      Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
    end
    
    @impl true
    def init(_opts) do
      children = [
        {DynamicSupervisor, strategy: :one_for_one, name: ConnectionDynamicSupervisor}
      ]
      
      Supervisor.init(children, strategy: :one_for_all)
    end
    
    def start_connection(config) do
      spec = {MyApp.Connection, config}
      DynamicSupervisor.start_child(ConnectionDynamicSupervisor, spec)
    end
  end
  
  defmodule IsolatedWorker do
    use GenServer
    
    def start_link(opts) do
      GenServer.start_link(__MODULE__, opts)
    end
    
    @impl true
    def init(opts) do
      # Set up error isolation
      Process.flag(:trap_exit, true)
      {:ok, %{opts: opts}}
    end
    
    @impl true
    def handle_info({:EXIT, pid, reason}, state) do
      Logger.error("Worker #{inspect(pid)} exited: #{inspect(reason)}")
      
      # Decide whether to restart or escalate
      case analyze_exit_reason(reason) do
        :restart ->
          start_replacement_worker(state)
          {:noreply, state}
        
        :escalate ->
          {:stop, reason, state}
      end
    end
    
    defp analyze_exit_reason(:normal), do: :ignore
    defp analyze_exit_reason(:shutdown), do: :ignore
    defp analyze_exit_reason({:shutdown, _}), do: :ignore
    defp analyze_exit_reason(_), do: :restart
  end
end
```

## Scaling Patterns

### Horizontal Scaling

Scale WebSocket connections horizontally:

```elixir
defmodule MyApp.HorizontalScaling do
  defmodule NodeManager do
    use GenServer
    
    def start_link(opts) do
      GenServer.start_link(__MODULE__, opts, name: __MODULE__)
    end
    
    def register_node(node_info) do
      GenServer.call(__MODULE__, {:register_node, node_info})
    end
    
    def get_available_nodes do
      GenServer.call(__MODULE__, :get_available_nodes)
    end
    
    @impl true
    def init(_opts) do
      :net_kernel.monitor_nodes(true)
      {:ok, %{nodes: %{}, load_info: %{}}}
    end
    
    @impl true
    def handle_call({:register_node, info}, _from, state) do
      new_nodes = Map.put(state.nodes, info.node_id, info)
      {:reply, :ok, %{state | nodes: new_nodes}}
    end
    
    @impl true
    def handle_info({:nodeup, node}, state) do
      Logger.info("Node up: #{node}")
      {:noreply, state}
    end
    
    @impl true
    def handle_info({:nodedown, node}, state) do
      Logger.info("Node down: #{node}")
      new_nodes = Map.reject(state.nodes, fn {_, info} -> info.node == node end)
      {:noreply, %{state | nodes: new_nodes}}
    end
  end
  
  defmodule ConnectionDistributor do
    def distribute_connection(user_id) do
      # Consistent hashing for user affinity
      nodes = NodeManager.get_available_nodes()
      node = select_node_by_hash(user_id, nodes)
      
      # Connect to specific node
      :rpc.call(node, MyApp.Client, :connect, [user_config(user_id)])
    end
    
    defp select_node_by_hash(user_id, nodes) do
      hash = :erlang.phash2(user_id, length(nodes))
      Enum.at(nodes, hash)
    end
  end
end
```

### Sharding Pattern

Implement connection sharding:

```elixir
defmodule MyApp.Sharding do
  defmodule ShardManager do
    use GenServer
    
    defstruct [:shards, :shard_count, :strategy]
    
    def start_link(opts) do
      GenServer.start_link(__MODULE__, opts, name: __MODULE__)
    end
    
    def get_shard(key) do
      GenServer.call(__MODULE__, {:get_shard, key})
    end
    
    @impl true
    def init(opts) do
      shard_count = opts[:shard_count] || 16
      strategy = opts[:strategy] || :hash
      
      shards = for i <- 0..(shard_count - 1) do
        {:ok, pid} = ShardWorker.start_link(shard_id: i)
        {i, pid}
      end
      |> Enum.into(%{})
      
      state = %__MODULE__{
        shards: shards,
        shard_count: shard_count,
        strategy: strategy
      }
      
      {:ok, state}
    end
    
    @impl true
    def handle_call({:get_shard, key}, _from, state) do
      shard_id = calculate_shard_id(key, state)
      shard_pid = Map.get(state.shards, shard_id)
      
      {:reply, {:ok, shard_pid}, state}
    end
    
    defp calculate_shard_id(key, state) do
      case state.strategy do
        :hash -> :erlang.phash2(key, state.shard_count)
        :range -> range_shard(key, state.shard_count)
        :geographical -> geo_shard(key, state.shard_count)
      end
    end
  end
  
  defmodule ShardWorker do
    use GenServer
    
    def start_link(opts) do
      GenServer.start_link(__MODULE__, opts)
    end
    
    def handle_connection(pid, conn) do
      GenServer.call(pid, {:handle_connection, conn})
    end
    
    @impl true
    def init(opts) do
      state = %{
        shard_id: opts[:shard_id],
        connections: %{},
        metrics: init_metrics()
      }
      
      {:ok, state}
    end
    
    @impl true
    def handle_call({:handle_connection, conn}, _from, state) do
      new_connections = Map.put(state.connections, conn.id, conn)
      new_state = %{state | connections: new_connections}
      
      {:reply, :ok, new_state}
    end
  end
end
```

## Security Patterns

### Authentication Patterns

Implement secure authentication:

```elixir
defmodule MyApp.SecurityPatterns do
  defmodule TokenAuthentication do
    use WebsockexNova.Behaviors.AuthHandler
    
    @impl true
    def handle_auth(state, %{token: token}) do
      case verify_token(token) do
        {:ok, claims} ->
          new_state = state
            |> Map.put(:authenticated, true)
            |> Map.put(:user_id, claims.user_id)
            |> Map.put(:permissions, claims.permissions)
          
          {:ok, new_state}
        
        {:error, reason} ->
          {:error, {:auth_failed, reason}}
      end
    end
    
    defp verify_token(token) do
      # JWT verification
      case MyApp.JWT.verify_and_validate(token) do
        {:ok, claims} ->
          if token_valid?(claims) do
            {:ok, claims}
          else
            {:error, :token_expired}
          end
        
        error ->
          error
      end
    end
    
    defp token_valid?(claims) do
      claims.exp > System.system_time(:second)
    end
  end
  
  defmodule PermissionChecker do
    def check_permission(state, action) do
      required_permissions = get_required_permissions(action)
      user_permissions = Map.get(state, :permissions, [])
      
      Enum.all?(required_permissions, &(&1 in user_permissions))
    end
    
    defp get_required_permissions(action) do
      %{
        read_orders: ["orders:read"],
        create_order: ["orders:write"],
        delete_order: ["orders:delete", "admin"]
      }
      |> Map.get(action, [])
    end
  end
end
```

### Rate Limiting Pattern

Implement rate limiting:

```elixir
defmodule MyApp.RateLimiting do
  defmodule TokenBucket do
    defstruct [:capacity, :tokens, :refill_rate, :last_refill]
    
    def new(capacity, refill_rate) do
      %__MODULE__{
        capacity: capacity,
        tokens: capacity,
        refill_rate: refill_rate,
        last_refill: System.monotonic_time(:millisecond)
      }
    end
    
    def take_token(bucket) do
      refilled_bucket = refill(bucket)
      
      if refilled_bucket.tokens >= 1 do
        new_bucket = %{refilled_bucket | tokens: refilled_bucket.tokens - 1}
        {:ok, new_bucket}
      else
        {:error, :rate_limited}
      end
    end
    
    defp refill(bucket) do
      current_time = System.monotonic_time(:millisecond)
      time_passed = current_time - bucket.last_refill
      
      tokens_to_add = (time_passed / 1000) * bucket.refill_rate
      new_tokens = min(bucket.tokens + tokens_to_add, bucket.capacity)
      
      %{bucket | 
        tokens: new_tokens,
        last_refill: current_time
      }
    end
  end
  
  defmodule RateLimitHandler do
    use WebsockexNova.Behaviors.RateLimitHandler
    
    @impl true
    def check_rate_limit(state, _action) do
      bucket = get_or_create_bucket(state)
      
      case TokenBucket.take_token(bucket) do
        {:ok, new_bucket} ->
          {:ok, update_bucket(state, new_bucket)}
        
        {:error, :rate_limited} ->
          {:error, :rate_limited}
      end
    end
    
    defp get_or_create_bucket(state) do
      case Map.get(state, :rate_bucket) do
        nil -> TokenBucket.new(100, 10)  # 100 requests, 10/second refill
        bucket -> bucket
      end
    end
    
    defp update_bucket(state, bucket) do
      Map.put(state, :rate_bucket, bucket)
    end
  end
end
```

## Integration Patterns

### Adapter Pattern

Create protocol-specific adapters:

```elixir
defmodule MyApp.IntegrationPatterns do
  defmodule ProtocolAdapter do
    @callback encode_message(message :: map()) :: binary()
    @callback decode_message(binary :: binary()) :: {:ok, map()} | {:error, term()}
    @callback handle_protocol_error(error :: term()) :: term()
  end
  
  defmodule JsonRpcAdapter do
    @behaviour ProtocolAdapter
    
    @impl true
    def encode_message(message) do
      jsonrpc_message = %{
        jsonrpc: "2.0",
        method: message.method,
        params: message.params,
        id: message.id || generate_id()
      }
      
      Jason.encode!(jsonrpc_message)
    end
    
    @impl true
    def decode_message(binary) do
      case Jason.decode(binary) do
        {:ok, %{"jsonrpc" => "2.0"} = message} ->
          {:ok, normalize_message(message)}
        
        {:ok, _} ->
          {:error, :invalid_jsonrpc}
        
        error ->
          error
      end
    end
    
    @impl true
    def handle_protocol_error(error) do
      %{
        jsonrpc: "2.0",
        error: %{
          code: error_code(error),
          message: error_message(error)
        }
      }
    end
  end
  
  defmodule GraphQLAdapter do
    @behaviour ProtocolAdapter
    
    @impl true
    def encode_message(message) do
      graphql_message = %{
        query: message.query,
        variables: message.variables,
        operationName: message.operation_name
      }
      
      Jason.encode!(graphql_message)
    end
    
    @impl true
    def decode_message(binary) do
      case Jason.decode(binary) do
        {:ok, %{"data" => _} = message} ->
          {:ok, message}
        
        {:ok, %{"errors" => errors}} ->
          {:error, {:graphql_errors, errors}}
        
        error ->
          error
      end
    end
  end
end
```

### Bridge Pattern

Bridge different messaging systems:

```elixir
defmodule MyApp.MessageBridge do
  use GenServer
  
  defstruct [:websocket_conn, :kafka_producer, :redis_conn]
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def bridge_message(message, from: source, to: destination) do
    GenServer.cast(__MODULE__, {:bridge, message, source, destination})
  end
  
  @impl true
  def init(opts) do
    state = %__MODULE__{
      websocket_conn: opts[:websocket_conn],
      kafka_producer: opts[:kafka_producer],
      redis_conn: opts[:redis_conn]
    }
    
    {:ok, state}
  end
  
  @impl true
  def handle_cast({:bridge, message, :websocket, :kafka}, state) do
    # Transform WebSocket message to Kafka format
    kafka_message = transform_ws_to_kafka(message)
    
    # Send to Kafka
    :brod.produce_sync(
      state.kafka_producer,
      "websocket_events",
      _partition = 0,
      _key = "",
      Jason.encode!(kafka_message)
    )
    
    {:noreply, state}
  end
  
  @impl true
  def handle_cast({:bridge, message, :kafka, :websocket}, state) do
    # Transform Kafka message to WebSocket format
    ws_message = transform_kafka_to_ws(message)
    
    # Send via WebSocket
    WebsockexNova.Client.send_json(state.websocket_conn, ws_message)
    
    {:noreply, state}
  end
  
  defp transform_ws_to_kafka(message) do
    %{
      event_type: "websocket_message",
      timestamp: DateTime.utc_now(),
      payload: message
    }
  end
  
  defp transform_kafka_to_ws(message) do
    %{
      type: "kafka_event",
      data: message.payload
    }
  end
end
```

## Best Practices

1. **Choose the Right Pattern**: Select patterns based on your specific requirements
2. **Compose Patterns**: Many patterns work well together
3. **Keep It Simple**: Don't over-engineer; start simple and evolve
4. **Monitor Everything**: Add observability from the start
5. **Test at Scale**: Test patterns under realistic load
6. **Document Decisions**: Document why you chose specific patterns
7. **Plan for Evolution**: Design patterns that can evolve with requirements
8. **Consider Trade-offs**: Every pattern has trade-offs; understand them

## Next Steps

- Review [Troubleshooting Guide](troubleshooting.md)
- Explore [Migration Guide](migration_guide.md)
- Check [Advanced Macros](advanced_macros.md)