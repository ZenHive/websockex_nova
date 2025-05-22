# Error Handling in WebsockexNew

WebsockexNew provides simple, raw error handling without custom wrapping to preserve all original error information. This document outlines the error handling patterns and how to use them effectively.

## Error Categories

The `WebsockexNew.ErrorHandler` module categorizes errors into five main types:

### 1. Connection Errors
**Recoverable** - Can be resolved through reconnection.

```elixir
# DNS resolution failures
{:error, :nxdomain}
{:error, :enotfound}

# Network connectivity issues  
{:error, :econnrefused}
{:error, :ehostunreach}
{:error, :enetunreach}

# TLS/SSL issues
{:error, {:tls_alert, reason}}

# Gun transport layer errors
{:gun_down, gun_pid, protocol, reason, killed_streams}
{:gun_error, gun_pid, stream_ref, reason}
```

### 2. Timeout Errors
**Recoverable** - Can be resolved through retry with potentially longer timeout.

```elixir
{:error, :timeout}
:timeout  # Bare atom from Gun
```

### 3. Protocol Errors
**Non-recoverable** - Indicate fundamental protocol violations.

```elixir
{:error, :invalid_frame}
{:error, :frame_too_large}
{:error, {:bad_frame, reason}}
```

### 4. Authentication Errors
**Non-recoverable** - Require credential fixes, not automatic retry.

```elixir
{:error, :unauthorized}
{:error, :invalid_credentials}
{:error, :token_expired}
```

### 5. Unknown Errors
**Non-recoverable** - Unrecognized errors handled conservatively.

## Usage Patterns

### Basic Error Handling

```elixir
case WebsockexNew.Client.connect(url) do
  {:ok, client} ->
    # Handle successful connection
    :ok
    
  {:error, reason} ->
    # Use ErrorHandler to determine appropriate action
    case WebsockexNew.ErrorHandler.handle_error(reason) do
      :reconnect ->
        # Retry connection after delay
        :timer.sleep(1000)
        connect_with_retry(url)
        
      :stop ->
        # Log error and stop attempting
        Logger.error("Connection failed: #{inspect(reason)}")
        {:error, reason}
    end
end
```

### Checking if Error is Recoverable

```elixir
case WebsockexNew.Client.connect(url) do
  {:error, reason} ->
    if WebsockexNew.ErrorHandler.recoverable?(reason) do
      schedule_reconnect()
    else
      Logger.error("Non-recoverable error: #{inspect(reason)}")
      :stop
    end
end
```

### Error Categorization

```elixir
{:error, reason} = WebsockexNew.Client.connect("wss://invalid-domain.com")

{category, original_error} = WebsockexNew.ErrorHandler.categorize_error(reason)

case category do
  :connection_error -> 
    IO.puts("Network connectivity issue")
  :timeout_error -> 
    IO.puts("Request timed out") 
  :protocol_error -> 
    IO.puts("WebSocket protocol violation")
  :auth_error -> 
    IO.puts("Authentication failed")
  :unknown_error -> 
    IO.puts("Unrecognized error")
end

# Original error is preserved for detailed inspection
IO.inspect(original_error)
```

## Integration with Reconnection Logic

Combine error handling with the reconnection module:

```elixir
defmodule MyClient do
  alias WebsockexNew.{Client, ErrorHandler, Reconnection}
  
  def connect_with_retry(url, max_retries \\ 3) do
    connect_with_retry(url, 0, max_retries)
  end
  
  defp connect_with_retry(url, attempt, max_retries) when attempt < max_retries do
    case Client.connect(url) do
      {:ok, client} -> 
        {:ok, client}
        
      {:error, reason} ->
        case ErrorHandler.handle_error(reason) do
          :reconnect ->
            delay = Reconnection.calculate_delay(attempt)
            :timer.sleep(delay)
            connect_with_retry(url, attempt + 1, max_retries)
            
          :stop ->
            {:error, reason}
        end
    end
  end
  
  defp connect_with_retry(_url, _attempt, _max_retries) do
    {:error, :max_retries_exceeded}
  end
end
```

## Platform-Specific Error Handling

### Deribit Adapter Error Handling

The `WebsockexNew.Examples.DeribitAdapter` shows how to handle platform-specific API errors:

```elixir
# API error from Deribit
error_response = %{
  "jsonrpc" => "2.0",
  "id" => 1,
  "error" => %{
    "code" => -32602,
    "message" => "invalid_credentials" 
  }
}

# Adapter automatically categorizes and handles these errors
# Authentication errors trigger auth error handlers
# Other API errors trigger general error handlers
```

## Best Practices

### 1. Preserve Raw Errors
- Never wrap errors in custom structures
- Always inspect the original error for debugging
- Pass raw errors to logging systems

### 2. Categorize Before Acting
```elixir
# Good
{category, _} = ErrorHandler.categorize_error(error)
case category do
  :connection_error -> retry_connection()
  :auth_error -> fix_credentials()
end

# Avoid - brittle pattern matching
case error do
  {:error, :econnrefused} -> retry_connection()
  {:error, :unauthorized} -> fix_credentials()
  # Many more specific cases...
end
```

### 3. Use Helper Functions
```elixir
# Check recoverability before expensive retry logic
if ErrorHandler.recoverable?(error) do
  expensive_retry_process()
end
```

### 4. Handle Unknown Errors Conservatively
- Unknown errors default to non-recoverable
- Log unknown errors for investigation
- Don't retry unknown errors automatically

### 5. Test with Real Errors
- Test error handling with actual network failures
- Use real API endpoints that return error responses
- Validate error categorization with live services

## Error Handler API Reference

### `categorize_error/1`
Returns `{category, original_error}` tuple.

### `recoverable?/1`
Returns `true` if error can be resolved through reconnection.

### `handle_error/1`
Returns suggested action: `:reconnect`, `:stop`, or `:continue`.

## Error Recovery Strategies

### Connection Errors
- Exponential backoff retry
- Check network connectivity
- Try alternative endpoints if available

### Timeout Errors  
- Increase timeout values
- Check network latency
- Retry with exponential backoff

### Protocol Errors
- Log error details for debugging
- Check client/server compatibility
- Update WebSocket implementation if needed

### Authentication Errors
- Refresh tokens/credentials
- Check API key validity
- Update authentication configuration

This approach ensures robust error handling while maintaining simplicity and preserving all original error information for debugging and monitoring purposes.