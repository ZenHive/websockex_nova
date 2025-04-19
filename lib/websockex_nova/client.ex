defmodule WebsockexNova.Client do
  @moduledoc """
  Ergonomic, adapter-agnostic client API for interacting with platform adapter connections in WebsockexNova.

  This module is the primary, recommended interface for sending messages, subscribing, authenticating, and more,
  to any process-based connection (e.g., Echo, Deribit) started via `WebsockexNova.Connection.start_link/1`.

  - Adapter-agnostic: works with any adapter implementing the platform contract.
  - Ready for extension: featureful adapters (like Deribit) may support more operations.
  - See the Echo adapter for a minimal example.

  ## Examples

      iex> {:ok, pid} = WebsockexNova.Connection.start_link(adapter: WebsockexNova.Platform.Echo.Adapter)
      iex> WebsockexNova.Client.send_text(pid, "Hello")
      {:text, "Hello"}

      iex> WebsockexNova.Client.send_json(pid, %{foo: "bar"})
      {:text, "{\"foo\":\"bar\"}"}

  See the Echo adapter for a minimal example, and featureful adapters (like Deribit) for advanced usage.
  """

  @doc """
  Sends a text message to the connection and waits for a reply.

  Returns the reply tuple (e.g., `{:text, reply}`) or `{:error, :timeout}` if no reply is received.
  """
  @spec send_text(pid(), String.t(), timeout()) :: {:text, String.t()} | {:error, :timeout}
  def send_text(pid, text, timeout \\ 1000) when is_pid(pid) and is_binary(text) do
    send(pid, {:platform_message, text, self()})

    receive do
      {:reply, reply} -> reply
    after
      timeout -> {:error, :timeout}
    end
  end

  @doc """
  Sends a JSON-encodable map to the connection and waits for a reply.

  Returns the reply tuple (e.g., `{:text, json}`) or `{:error, :timeout}` if no reply is received.
  """
  @spec send_json(pid(), map(), timeout()) :: {:text, String.t()} | {:error, :timeout}
  def send_json(pid, map, timeout \\ 1000) when is_pid(pid) and is_map(map) do
    send(pid, {:platform_message, map, self()})

    receive do
      {:reply, reply} -> reply
    after
      timeout -> {:error, :timeout}
    end
  end

  @doc """
  Subscribes to a channel/topic via the connection.

  Returns the reply or `{:error, :timeout}`.
  """
  @spec subscribe(pid(), String.t(), map(), timeout()) :: any()
  def subscribe(pid, channel, params \\ %{}, timeout \\ 1000) do
    send(pid, {:subscribe, channel, params, self()})

    receive do
      {:reply, reply} -> reply
    after
      timeout -> {:error, :timeout}
    end
  end

  @doc """
  Unsubscribes from a channel/topic via the connection.

  Returns the reply or `{:error, :timeout}`.
  """
  @spec unsubscribe(pid(), String.t(), timeout()) :: any()
  def unsubscribe(pid, channel, timeout \\ 1000) do
    send(pid, {:unsubscribe, channel, self()})

    receive do
      {:reply, reply} -> reply
    after
      timeout -> {:error, :timeout}
    end
  end

  @doc """
  Sends authentication data to the connection.

  Returns the reply or `{:error, :timeout}`.
  """
  @spec authenticate(pid(), map(), timeout()) :: any()
  def authenticate(pid, credentials, timeout \\ 1000) do
    send(pid, {:authenticate, credentials, self()})

    receive do
      {:reply, reply} -> reply
    after
      timeout -> {:error, :timeout}
    end
  end

  @doc """
  Sends a ping frame to the connection.

  Returns the reply or `{:error, :timeout}`.
  """
  @spec ping(pid(), timeout()) :: any()
  def ping(pid, timeout \\ 1000) do
    send(pid, {:ping, self()})

    receive do
      {:reply, reply} -> reply
    after
      timeout -> {:error, :timeout}
    end
  end

  @doc """
  Requests connection status.

  Returns the status or `{:error, :timeout}`.
  """
  @spec status(pid(), timeout()) :: any()
  def status(pid, timeout \\ 1000) do
    send(pid, {:status, self()})

    receive do
      {:reply, status} -> status
    after
      timeout -> {:error, :timeout}
    end
  end

  @doc """
  Sends a raw message to the connection and waits for a reply.

  Returns the reply or `{:error, :timeout}`.
  """
  @spec send_raw(pid(), any(), timeout()) :: any()
  def send_raw(pid, message, timeout \\ 1000) do
    send(pid, {:platform_message, message, self()})

    receive do
      {:reply, reply} -> reply
    after
      timeout -> {:error, :timeout}
    end
  end

  @doc """
  Sends a text message to the connection without waiting for a reply (fire-and-forget).
  """
  @spec cast_text(pid(), String.t()) :: :ok
  def cast_text(pid, text) when is_pid(pid) and is_binary(text) do
    send(pid, {:platform_message, text, nil})
    :ok
  end

  # This module can be extended with more helpers (subscribe, auth, etc.) as needed.
end
