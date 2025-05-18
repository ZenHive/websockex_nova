# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

### Running Tests
```bash
# Run all tests
mix test

# Run a specific test file
mix test test/path/to/test_file.exs

# Run with coverage
mix coverage

# Run tests in watch mode
mix test.watch
```

### Code Quality & Linting
```bash
# Run Credo (Elixir linter) with strict mode
mix lint

# Run Dialyzer (type checker)
mix typecheck

# Run Sobelow (security scanner)
mix security

# Run all quality checks
mix check

# Rebuild project from scratch with quality checks
mix rebuild
```

### Documentation
```bash
# Generate documentation
mix docs
```

### Environment Setup
```bash
# Install dependencies
mix deps.get

# Compile the project
mix compile
```

## Environment Variables

For integration tests with Deribit:
```bash
export DERIBIT_CLIENT_ID="your_client_id"
export DERIBIT_CLIENT_SECRET="your_client_secret"
```

Integration tests use `test.deribit.com` and require valid API credentials.

## High-Level Architecture

### Project Structure
WebsockexNova uses a behavior-based architecture with Gun as the underlying WebSocket transport layer. The main components are:

- **Behaviors**: Interface definitions for extensibility (`lib/websockex_nova/behaviors/`)
- **Gun Integration**: WebSocket transport wrapper (`lib/websockex_nova/gun/`)
- **Client API**: High-level client interface (`lib/websockex_nova/client.ex`)
- **Adapters**: Platform-specific integrations (`lib/websockex_nova/examples/`)
- **Macros**: ClientMacro and AdapterMacro for rapid development

### Key Architectural Concepts

1. **Behavior-Based Design**: Every major component is defined as a behavior with default implementations
   - `ConnectionHandler`: Connection lifecycle management
   - `MessageHandler`: Message parsing and validation
   - `SubscriptionHandler`: Channel/topic subscription management
   - `ErrorHandler`: Error recovery strategies
   - `AuthHandler`: Authentication flows
   - `RateLimitHandler`: Rate limiting logic

2. **Gun Process Management**: Uses process monitoring (not linking) for resilience
   - Connection processes are monitored for crash detection
   - Ownership transfer support for advanced use cases
   - Explicit monitor references with await functions

3. **Connection State Management**: 
   - `ClientConn` struct maintains connection state
   - `ConnectionRegistry` maps stable connection IDs to transport PIDs
   - Automatic reconnection with subscription preservation

4. **Adapter Pattern**: Platform-specific adapters implement behaviors
   - Example: `AdapterDeribit` for Deribit exchange integration
   - Adapters customize authentication, message formats, etc.

### Configuration Profiles
WebsockexNova supports different profiles for varying requirements:
- **Financial**: High-frequency trading with aggressive reconnection
- **Standard**: General-purpose with balanced reliability
- **Lightweight**: Simple integrations with minimal overhead
- **Messaging**: Chat/messaging platforms with presence tracking

### Testing Infrastructure
- Mock transport implementation for testing
- Comprehensive test helpers in `test/support/`
- Integration tests connect to real endpoints (e.g., test.deribit.com)
- Test harness for simulating connection failures and reconnections

## Development Workflow

1. **Implement behaviors** in `lib/websockex_nova/behaviors/`
2. **Create adapters** in `lib/websockex_nova/examples/` for specific platforms
3. **Write tests** using the mock transport or real endpoints
4. **Run quality checks** with `mix check` before committing
5. **Document** any new behaviors or adapters in the docs/ directory

## Critical Code Paths

1. **Connection Establishment**: `WebsockexNova.Client.connect/2`
2. **Message Handling**: `ConnectionWrapper` → `MessageHandler` → `SubscriptionHandler`
3. **Reconnection Flow**: `ConnectionManager` → `ConnectionWrapper` → `ConnectionRegistry`
4. **Authentication**: `AuthHandler` behavior with platform-specific implementation
5. **Frame Processing**: `FrameCodec` handles WebSocket frame encoding/decoding

## Common Tasks

### Adding a New Platform Adapter
1. Create adapter module implementing required behaviors
2. Use `WebsockexNova.Adapter` macro for defaults
3. Override only necessary callbacks
4. Add integration tests for the platform
5. Document the adapter in docs/

### Debugging Connection Issues
1. Check `ConnectionRegistry` for connection ID mapping
2. Verify Gun process is alive and monitored
3. Review state transitions in `ConnectionManager`
4. Enable debug logging in test_helper.exs
5. Use `StateTracer` for detailed connection history