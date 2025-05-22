defmodule WebsockexNew.JsonRpc do
  @moduledoc """
  JSON-RPC 2.0 request builder and response matcher.

  Simple API builder for WebSocket APIs using JSON-RPC 2.0 protocol.
  Generates request functions with automatic ID tracking and correlation.
  """

  @doc """
  Builds a JSON-RPC 2.0 request with unique ID.

  ## Examples
      iex> {:ok, request} = JsonRpc.build_request("public/auth", %{grant_type: "client_credentials"})
      iex> request["method"]
      "public/auth"
  """
  @spec build_request(String.t(), map() | nil) :: {:ok, map()}
  def build_request(method, params \\ nil) do
    request = %{
      "jsonrpc" => "2.0",
      "id" => generate_id(),
      "method" => method
    }

    request = if params, do: Map.put(request, "params", params), else: request
    {:ok, request}
  end

  defmacro __using__(_opts) do
    quote do
      import WebsockexNew.JsonRpc, only: [defrpc: 2, defrpc: 3]
    end
  end

  @doc """
  Generates RPC method functions with automatic request building.

  ## Examples
      defmodule MyApi do
        use WebsockexNew.JsonRpc

        defrpc :authenticate, "public/auth"
        defrpc :subscribe, "public/subscribe"
        defrpc :get_order_book, "public/get_order_book"
      end
  """
  defmacro defrpc(name, method, opts \\ []) do
    doc = Keyword.get(opts, :doc, "Calls #{method} via JSON-RPC 2.0")

    quote do
      @doc unquote(doc)
      def unquote(name)(params \\ %{}) do
        WebsockexNew.JsonRpc.build_request(unquote(method), params)
      end
    end
  end

  @doc """
  Matches a JSON-RPC response to determine if it's a result or error.

  Returns:
  - {:ok, result} for successful responses
  - {:error, {code, message}} for JSON-RPC errors
  - {:notification, method, params} for notifications
  """
  @spec match_response(map()) :: {:ok, term()} | {:error, {integer(), String.t()}} | {:notification, String.t(), map()}
  def match_response(%{"result" => result}), do: {:ok, result}

  def match_response(%{"error" => %{"code" => code, "message" => message}}) do
    {:error, {code, message}}
  end

  def match_response(%{"method" => method, "params" => params}) do
    {:notification, method, params}
  end

  # Generate unique request ID
  defp generate_id do
    :erlang.unique_integer([:positive])
  end
end
