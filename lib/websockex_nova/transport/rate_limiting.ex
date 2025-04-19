defmodule WebsockexNova.Transport.RateLimiting do
  @moduledoc """
  Provides rate limiting functionality for WebSocket requests.

  This module serves as a centralized interface for rate limiting across the application,
  delegating to the configured RateLimitHandler implementation. It includes:

  * An Agent process for persistent state management
  * Functions for checking rate limits before sending requests
  * Automatic processing of queued requests
  * Configuration via application environment

  ## Configuration

  Configure rate limiting in your application config:

  ```elixir
  config :websockex_nova, :rate_limiting,
    handler: MyApp.CustomRateLimitHandler,
    capacity: 100,
    refill_rate: 5,
    refill_interval: 1000,
    queue_limit: 200,
    process_interval: 100,
    cost_map: %{
      subscription: 5,
      auth: 10,
      query: 1
    }
  ```

  ## Usage

  ```elixir
  alias WebsockexNova.Transport.RateLimiting

  # Start the rate limiter
  {:ok, _pid} = RateLimiting.start_link()

  # Check if a request can proceed
  request = %{type: :query, method: "get_data", data: %{id: 123}}

  case RateLimiting.check(request) do
    :allow ->
      # Send the request immediately
      send_request(request)

    {:queue, request_id} ->
      # Request is queued, will be processed automatically
      Logger.info("Request queued with id \#{request_id}")

    {:reject, reason} ->
      # Request was rejected
      Logger.warn("Request rejected: \#{reason}")
  end
  ```
  """

  use GenServer

  alias WebsockexNova.Defaults.DefaultRateLimitHandler

  require Logger

  # Default interval to process queue (ms)
  @process_interval 100

  @doc """
  Starts the rate limiting GenServer.

  ## Options

  * `:name` - The name to register the server under
  * `:handler` - The module implementing the `WebsockexNova.Behaviors.RateLimitHandler` behavior
  * `:handler_opts` - Options to pass to the handler module
  * `:process_interval` - Interval in milliseconds to process the queue
  * `:mode` - Rate limiting mode (`:normal`, `:always_allow`, `:always_queue`, `:always_reject`)
  """
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)

    case GenServer.start_link(__MODULE__, opts, name: name) do
      {:ok, pid} ->
        Logger.info("Rate limiting server started with options: #{inspect(opts)}")
        {:ok, pid}

      error ->
        Logger.error("Failed to start rate limiting server: #{inspect(error)}")
        error
    end
  end

  @doc """
  Checks if a request can proceed based on rate limits.

  ## Parameters

  * `request` - The request to check
  * `server` - The server to check with (default: __MODULE__)

  ## Returns

  * `:allow` - Request can proceed immediately
  * `{:queue, request_id}` - Request is queued and will be processed later
  * `{:reject, reason}` - Request is rejected with the given reason
  """
  @spec check(map(), GenServer.server()) ::
          :allow
          | {:queue, reference()}
          | {:reject, term()}
  def check(request, server \\ __MODULE__) do
    request_id = generate_request_id()
    # Attach the request_id to the request for tracking
    request = Map.put(request, :id, request_id)
    GenServer.call(server, {:check, request, request_id})
  end

  @doc """
  Adds a callback to be executed when a queued request is processed.

  ## Parameters

  * `request_id` - The ID of the queued request
  * `callback` - Function to call when the request is processed
  * `server` - The server to register with (default: __MODULE__)

  ## Returns

  * `:ok` - Callback registered
  * `{:error, :not_found}` - Request ID not found
  """
  @spec on_process(reference(), (-> any()), GenServer.server()) ::
          :ok
          | {:error, :not_found}
  def on_process(request_id, callback, server \\ __MODULE__) do
    GenServer.call(server, {:on_process, request_id, callback})
  end

  @doc """
  Forces processing of the queue, regardless of rate limits.

  This is primarily for testing and debugging.

  ## Parameters

  * `server` - The server to process queue for (default: __MODULE__)

  ## Returns

  * `{:ok, count}` - Number of requests processed
  """
  @spec force_process_queue(GenServer.server()) :: {:ok, non_neg_integer()}
  def force_process_queue(server \\ __MODULE__) do
    GenServer.call(server, :force_process_queue)
  end

  # GenServer Callbacks

  @impl true
  def init(opts) do
    # Extract options with defaults
    handler_module = get_handler_module(opts)
    handler_opts = get_handler_opts(opts)
    process_interval = get_process_interval(opts)

    # If mode is set in opts, pass it to handler_opts
    handler_opts =
      if Keyword.has_key?(opts, :mode) do
        Keyword.put(handler_opts, :mode, Keyword.get(opts, :mode))
      else
        handler_opts
      end

    # Initialize the handler
    {:ok, handler_state} = handler_module.init(handler_opts)

    # Set up the timer for automatic queue processing
    timer_ref = Process.send_after(self(), :process_queue, process_interval)

    # Initial state
    state = %{
      handler_module: handler_module,
      handler_state: handler_state,
      process_interval: process_interval,
      timer_ref: timer_ref,
      callbacks: %{},
      request_count: 0,
      queued_request_ids: MapSet.new()
    }

    Logger.debug("Rate limiting initialized with handler: #{inspect(handler_module)}, interval: #{process_interval}ms")
    {:ok, state}
  end

  @impl true
  def handle_call({:check, request, request_id}, _from, state) do
    %{handler_module: handler_module, handler_state: handler_state} = state

    case handler_module.check_rate_limit(request, handler_state) do
      {:allow, new_handler_state} ->
        {:reply, {:allow, request_id}, %{state | handler_state: new_handler_state}}

      {:queue, new_handler_state} ->
        # Track the queued request_id in state.queued_request_ids
        new_queued = MapSet.put(Map.get(state, :queued_request_ids, MapSet.new()), request_id)
        {:reply, {:queue, request_id}, %{state | handler_state: new_handler_state, queued_request_ids: new_queued}}

      {:reject, reason, new_handler_state} ->
        {:reply, {:reject, reason}, %{state | handler_state: new_handler_state}}
    end
  end

  @impl true
  def handle_call({:on_process, request_id, callback}, _from, state) do
    # Check if the request_id is tracked as queued
    if check_request_in_queue(request_id, state) do
      new_callbacks = Map.put(state.callbacks, request_id, callback)
      {:reply, :ok, %{state | callbacks: new_callbacks}}
    else
      {:reply, {:error, :not_found}, state}
    end
  end

  @impl true
  def handle_call(:force_process_queue, _from, state) do
    # Process all requests in the queue
    {processed_count, new_state} = process_all_requests(state)

    {:reply, {:ok, processed_count}, new_state}
  end

  @impl true
  def handle_info(:process_queue, state) do
    # Process the next request in queue (if any)
    {_, new_state} = process_next_request(state)

    # Set up the next timer
    timer_ref = Process.send_after(self(), :process_queue, state.process_interval)

    {:noreply, %{new_state | timer_ref: timer_ref}}
  end

  # Private helper functions

  defp get_handler_module(opts) do
    app_opts = Application.get_env(:websockex_nova, :rate_limiting, [])

    cond do
      Keyword.has_key?(opts, :handler) ->
        Keyword.get(opts, :handler)

      Keyword.has_key?(app_opts, :handler) ->
        Keyword.get(app_opts, :handler)

      true ->
        DefaultRateLimitHandler
    end
  end

  defp get_handler_opts(opts) do
    app_opts = Application.get_env(:websockex_nova, :rate_limiting, [])

    # Start with defaults
    handler_opts = []

    # Apply app configs
    handler_opts =
      if Keyword.has_key?(app_opts, :handler_opts) do
        Keyword.merge(handler_opts, Keyword.get(app_opts, :handler_opts, []))
      else
        # If there's no :handler_opts key, merge all app options
        Keyword.merge(handler_opts, app_opts)
      end

    # Apply passed options (overrides)
    handler_opts =
      if Keyword.has_key?(opts, :handler_opts) do
        Keyword.merge(handler_opts, Keyword.get(opts, :handler_opts, []))
      else
        # If the handler_opts key doesn't exist, just pass all the options
        # This allows setting things like mode: :always_queue directly
        excluded_keys = [:name, :handler, :process_interval]
        opts_to_pass = Keyword.drop(opts, excluded_keys)
        Keyword.merge(handler_opts, opts_to_pass)
      end

    handler_opts
  end

  defp get_process_interval(opts) do
    app_opts = Application.get_env(:websockex_nova, :rate_limiting, [])

    cond do
      Keyword.has_key?(opts, :process_interval) ->
        Keyword.get(opts, :process_interval)

      Keyword.has_key?(app_opts, :process_interval) ->
        Keyword.get(app_opts, :process_interval)

      true ->
        @process_interval
    end
  end

  defp check_request_in_queue(request_id, state) do
    MapSet.member?(Map.get(state, :queued_request_ids, MapSet.new()), request_id)
  end

  defp process_next_request(state) do
    %{handler_module: handler_module, handler_state: handler_state} = state

    case handler_module.handle_tick(handler_state) do
      {:process, request, new_handler_state} ->
        request_id = Map.get(request, :id)
        # Remove from queued_request_ids
        new_queued = MapSet.delete(Map.get(state, :queued_request_ids, MapSet.new()), request_id)

        if request_id && Map.has_key?(state.callbacks, request_id) do
          callback = Map.get(state.callbacks, request_id)
          Task.start(callback)
          new_callbacks = Map.delete(state.callbacks, request_id)

          new_state = %{
            state
            | handler_state: new_handler_state,
              callbacks: new_callbacks,
              queued_request_ids: new_queued
          }

          {1, new_state}
        else
          new_state = %{state | handler_state: new_handler_state, queued_request_ids: new_queued}
          {1, new_state}
        end

      {:ok, new_handler_state} ->
        {0, %{state | handler_state: new_handler_state}}
    end
  end

  defp process_all_requests(state) do
    case process_next_request(state) do
      {0, new_state} ->
        # No more requests to process
        {0, new_state}

      {count, new_state} ->
        # Process more requests
        {more_count, final_state} = process_all_requests(new_state)
        {count + more_count, final_state}
    end
  end

  defp generate_request_id do
    make_ref()
  end
end
