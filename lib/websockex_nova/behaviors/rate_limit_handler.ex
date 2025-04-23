defmodule WebsockexNova.Behaviors.RateLimitHandler do
  @moduledoc """
  Behaviour for rate limit handlers.
  All state is a map. All arguments and return values are explicit and documented.
  """

  @typedoc "Handler state"
  @type state :: map()

  @typedoc "Request data"
  @type request :: map()

  @doc """
  Initialize the rate limit handler's state.
  """
  @callback rate_limit_init(opts :: term()) :: {:ok, state}

  @doc """
  Check if a request can proceed based on current rate limits.
  Returns:
    - `{:allow, state}`
    - `{:queue, state}`
    - `{:reject, reason, state}`
  """
  @callback check_rate_limit(request, state) ::
              {:allow, state}
              | {:queue, state}
              | {:reject, term(), state}

  @doc """
  Process queued requests on a periodic tick.
  Returns:
    - `{:ok, state}`
    - `{:process, request, state}`
  """
  @callback handle_tick(state) ::
              {:ok, state}
              | {:process, request, state}

  # Define which callbacks are optional
  @optional_callbacks [handle_tick: 1]
end
