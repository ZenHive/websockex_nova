defmodule WebsockexNova.TestWrapperServer do
  @moduledoc false
  use GenServer

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts)
  end

  def init(_opts), do: {:ok, %{}}

  def handle_call({:send_frame, _stream_ref, _frame}, _from, state) do
    WebsockexNova.TransportMock.send_frame(self(), :stream_ref, :frame)
    {:reply, :ok, state}
  end
end
