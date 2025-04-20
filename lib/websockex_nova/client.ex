defmodule WebsockexNova.Client do
  @moduledoc """
  Ergonomic, adapter-agnostic client API for interacting with platform adapter connections in WebsockexNova.

  This module is the primary, recommended interface for sending messages, subscribing, authenticating, and more,
  to any process-based connection (e.g., Echo, Deribit) started via `WebsockexNova.Connection.start_link/1`.

  - Adapter-agnostic: works with any adapter implementing the platform contract.
  - Ready for extension: featureful adapters (like Deribit) may support more operations.
  - See the Echo adapter for a minimal example.

  ## Examples

      iex> {:ok, pid} = WebsockexNova.Connection.start_link(adapter: WebsockexNova.Platform.Echo.Adapter, host: "echo.websocket.org", port: 443)
      iex> WebsockexNova.Client.send_text(pid, "Hello")
      {:text, "Hello"}

      iex> WebsockexNova.Client.send_json(pid, %{foo: "bar"})
      {:text, "{\"foo\":\"bar\"}"}

  See the Echo adapter for a minimal example, and featureful adapters (like Deribit) for advanced usage.
  """

  alias WebsockexNova.ClientConn

  @doc """
  Sends a text message to the connection and waits for a reply.

  Returns the reply tuple (e.g., `{:text, reply}`) or `{:error, :timeout}` if no reply is received.
  """
  @spec send_text(ClientConn.t(), String.t(), timeout()) :: {:text, String.t()} | {:error, :timeout}
  def send_text(%ClientConn{pid: pid, stream_ref: stream_ref}, text, timeout \\ 1000)
      when is_pid(pid) and is_binary(text) do
    send(pid, {:platform_message, stream_ref, text, self()})

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
  @spec send_json(ClientConn.t(), map(), timeout()) :: {:text, String.t()} | {:error, :timeout}
  def send_json(%ClientConn{pid: pid, stream_ref: stream_ref}, map, timeout \\ 1000) when is_pid(pid) and is_map(map) do
    send(pid, {:platform_message, stream_ref, map, self()})

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
  @spec subscribe(ClientConn.t(), String.t(), map(), timeout()) :: any()
  def subscribe(%ClientConn{pid: pid, stream_ref: stream_ref}, channel, params \\ %{}, timeout \\ 1000) do
    send(pid, {:subscribe, stream_ref, channel, params, self()})

    receive do
      {:reply, reply} -> normalize_inert(reply)
    after
      timeout -> {:error, :timeout}
    end
  end

  @doc """
  Unsubscribes from a channel/topic via the connection.

  Returns the reply or `{:error, :timeout}`.
  """
  @spec unsubscribe(ClientConn.t(), String.t(), timeout()) :: any()
  def unsubscribe(%ClientConn{pid: pid, stream_ref: stream_ref}, channel, timeout \\ 1000) do
    send(pid, {:unsubscribe, stream_ref, channel, self()})

    receive do
      {:reply, reply} -> normalize_inert(reply)
    after
      timeout -> {:error, :timeout}
    end
  end

  @doc """
  Sends authentication data to the connection.

  Returns the reply or `{:error, :timeout}`.
  """
  @spec authenticate(ClientConn.t(), map(), timeout()) :: any()
  def authenticate(%ClientConn{pid: pid, stream_ref: stream_ref}, credentials, timeout \\ 1000) do
    send(pid, {:authenticate, stream_ref, credentials, self()})

    receive do
      {:reply, reply} -> normalize_inert(reply)
    after
      timeout -> {:error, :timeout}
    end
  end

  @doc """
  Sends a ping frame to the connection.

  Returns the reply or `{:error, :timeout}`.
  """
  @spec ping(ClientConn.t(), timeout()) :: any()
  def ping(%ClientConn{pid: pid, stream_ref: stream_ref}, timeout \\ 1000) do
    send(pid, {:ping, stream_ref, self()})

    receive do
      {:reply, reply} -> normalize_inert(reply)
    after
      timeout -> {:error, :timeout}
    end
  end

  @doc """
  Requests connection status.

  Returns the status or `{:error, :timeout}`.
  """
  @spec status(ClientConn.t(), timeout()) :: any()
  def status(%ClientConn{pid: pid, stream_ref: stream_ref}, timeout \\ 1000) do
    send(pid, {:status, stream_ref, self()})

    receive do
      {:reply, status} -> normalize_inert(status)
    after
      timeout -> {:error, :timeout}
    end
  end

  @doc """
  Sends a raw message to the connection and waits for a reply.

  Returns the reply or `{:error, :timeout}`.
  """
  @spec send_raw(ClientConn.t(), any(), timeout()) :: any()
  def send_raw(%ClientConn{pid: pid, stream_ref: stream_ref}, message, timeout \\ 1000) do
    send(pid, {:platform_message, stream_ref, message, self()})

    receive do
      {:reply, reply} -> normalize_inert(reply)
    after
      timeout -> {:error, :timeout}
    end
  end

  @doc """
  Sends a text message to the connection without waiting for a reply (fire-and-forget).
  """
  @spec cast_text(ClientConn.t(), String.t()) :: :ok
  def cast_text(%ClientConn{pid: pid, stream_ref: stream_ref}, text) when is_pid(pid) and is_binary(text) do
    send(pid, {:platform_message, stream_ref, text, nil})
    :ok
  end

  defp normalize_inert({:error, :not_implemented}), do: {:text, ""}
  defp normalize_inert(other), do: other

  @doc """
  Waits until the connection is ready for WebSocket upgrade (status == :connected).
  Blocks until the connection is ready or the timeout is reached.

  ## Options
    - timeout: maximum time to wait in milliseconds (default: 2000)
    - interval: polling interval in milliseconds (default: 50)

  Returns :ok if connected, {:error, :timeout} otherwise.
  """
  @spec wait_until_connected(pid(), keyword()) :: :ok | {:error, :timeout}
  def wait_until_connected(pid, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 2000)
    interval = Keyword.get(opts, :interval, 50)
    start = System.monotonic_time(:millisecond)
    do_wait_until_connected(pid, start, timeout, interval)
  end

  defp do_wait_until_connected(pid, start, timeout, interval) do
    case :sys.get_state(pid) do
      %{ws_status: :connected} ->
        :ok

      _ ->
        if System.monotonic_time(:millisecond) - start > timeout do
          {:error, :timeout}
        else
          Process.sleep(interval)
          do_wait_until_connected(pid, start, timeout, interval)
        end
    end
  end

  # This module can be extended with more helpers (subscribe, auth, etc.) as needed.
end
