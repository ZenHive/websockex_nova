defmodule WebsockexNew.ErrorHandler do
  @moduledoc """
  Simple error handling for WebSocket connections.

  Handles common error scenarios:
  - Connection errors (network failures)
  - Protocol errors (malformed frames)
  - Authentication errors
  - Timeout errors

  Passes raw errors without wrapping to preserve original error information.
  """

  @doc """
  Categorizes errors into common types for easier handling.

  Returns the raw error unchanged to preserve all original information.
  """
  @spec categorize_error(term()) ::
          {:connection_error | :protocol_error | :auth_error | :timeout_error | :unknown_error, term()}
  def categorize_error(error) do
    case error do
      # Connection errors from Gun
      {:error, :econnrefused} -> {:connection_error, error}
      {:error, :timeout} -> {:timeout_error, error}
      :timeout -> {:timeout_error, {:error, error}}
      {:error, :nxdomain} -> {:connection_error, error}
      {:error, {:tls_alert, _}} -> {:connection_error, error}
      {:error, :enotfound} -> {:connection_error, error}
      {:error, :ehostunreach} -> {:connection_error, error}
      {:error, :enetunreach} -> {:connection_error, error}
      {:gun_down, _, _, reason, _} -> {:connection_error, {:gun_down, reason}}
      {:gun_error, _, _, reason} -> {:connection_error, {:gun_error, reason}}
      # Protocol errors
      {:error, :invalid_frame} -> {:protocol_error, error}
      {:error, :frame_too_large} -> {:protocol_error, error}
      {:error, {:bad_frame, _}} -> {:protocol_error, error}
      # Authentication errors
      {:error, :unauthorized} -> {:auth_error, error}
      {:error, :invalid_credentials} -> {:auth_error, error}
      {:error, :token_expired} -> {:auth_error, error}
      # Catch-all for unknown errors
      _ -> {:unknown_error, error}
    end
  end

  @doc """
  Determines if an error is recoverable through reconnection.
  """
  @spec recoverable?(term()) :: boolean()
  def recoverable?(error) do
    case categorize_error(error) do
      {:connection_error, _} -> true
      {:timeout_error, _} -> true
      {:protocol_error, _} -> false
      {:auth_error, _} -> false
      {:unknown_error, _} -> false
    end
  end

  @doc """
  Handles errors by returning appropriate actions.

  Returns either :reconnect, :stop, or :continue based on error type.
  """
  @spec handle_error(term()) :: :reconnect | :stop | :continue
  def handle_error(error) do
    case categorize_error(error) do
      {:connection_error, _} -> :reconnect
      {:timeout_error, _} -> :reconnect
      {:protocol_error, _} -> :stop
      {:auth_error, _} -> :stop
      {:unknown_error, _} -> :stop
    end
  end
end
