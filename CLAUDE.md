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

# Run integration tests only
mix test --only integration

# Real API testing commands
mix test.api                    # Run all real API tests
mix test.api --deribit         # Run Deribit-specific tests
mix test.api --performance     # Run performance tests
mix test.api --stress          # Run stress tests

# Environment management
mix test.env.health            # Check health of all test environments
mix test.env.setup deribit_test # Setup specific environment
mix test.env.list              # List available environments

# Performance benchmarking
mix test.performance           # Run all performance benchmarks
mix test.performance --connection --duration 60
```

### Code Quality & Linting
```bash
# Run Credo (Elixir linter) with strict mode
mix lint

# Run Dialyzer (type checker)
mix dialyzer

# Run Sobelow (security scanner)
mix sobelow

# Run all quality checks
mix check

# Rebuild project from scratch with quality checks
mix rebuild

# Format code
mix format

# Validate task list format
mix validate_tasklist
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
WebsockexNew uses a behavior-based architecture with Gun as the underlying WebSocket transport layer. The main components are:

- **Behaviors**: Interface definitions for extensibility (`lib/websockex_new/behaviors/`)
- **Gun Integration**: WebSocket transport wrapper (`lib/websockex_new/gun/`)
- **Client API**: High-level client interface (`lib/websockex_new/client.ex`)
- **Adapters**: Platform-specific integrations (`lib/websockex_new/examples/`)
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
WebsockexNew supports different profiles for varying requirements:
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

### Code Quality Standards
- **Documentation**: Use concise, structured `@moduledoc` with clear bullet points
- **Function Documentation**: Single-sentence summary followed by structured details
- **Code Organization**: Group related functions, use clear naming conventions
- **Error Handling**: Pass raw errors without wrapping, use `{:ok, result} | {:error, reason}` pattern
- **Simplicity**: Start with minimal viable solution, add complexity incrementally

### TDD Workflow
1. **Write tests first** - Create comprehensive test cases before implementation
2. **Implement behaviors** in `lib/websockex_new/behaviors/`
3. **Create adapters** in `lib/websockex_new/examples/` for specific platforms
4. **Write integration tests** using real WebSocket endpoints when possible
5. **Run quality checks** with `mix check` before committing
6. **Document** any new behaviors or adapters in the docs/ directory

### Task Management
- Use `docs/TaskList.md` for structured task tracking
- Follow WNX#### ID format for all tasks
- Include detailed task descriptions with test requirements
- Mark tasks as completed immediately after finishing

## Critical Code Paths

1. **Connection Establishment**: `WebsockexNew.Client.connect/2`
2. **Message Handling**: `ConnectionWrapper` → `MessageHandler` → `SubscriptionHandler`
3. **Reconnection Flow**: `ConnectionManager` → `ConnectionWrapper` → `ConnectionRegistry`
4. **Authentication**: `AuthHandler` behavior with platform-specific implementation
5. **Frame Processing**: `FrameCodec` handles WebSocket frame encoding/decoding

## Common Tasks

### Adding a New Platform Adapter
1. Create adapter module implementing required behaviors
2. Use `WebsockexNew.Adapter` macro for defaults
3. Override only necessary callbacks
4. Keep adapters thin - focus on protocol translation only
5. Add integration tests for the platform using real endpoints
6. Document the adapter in docs/

### Debugging Connection Issues
1. Check `ConnectionRegistry` for connection ID mapping
2. Verify Gun process is alive and monitored
3. Review state transitions in `ConnectionManager`
4. Enable debug logging in test_helper.exs
5. Use `StateTracer` for detailed connection history

### Error Handling Best Practices
- Pass raw errors without custom wrapping
- Use pattern matching on raw error data
- Apply "let it crash" philosophy for unexpected errors
- Distinguish network errors from protocol/application errors
- Include minimal context information when necessary

## Simplicity Guidelines

### Core Principles
- Code simplicity is a primary feature, not an afterthought
- Implement the minimal viable solution first
- Each component has a limited "complexity budget"
- Create abstractions only with proven value (≥3 concrete examples)
- Start simple and add complexity incrementally

### Module Structure Limits
- Maximum 5 functions per module initially
- Maximum function length of 15 lines
- Maximum of 2 levels of function calls for any operation
- Prefer pure functions over processes when possible

### Anti-Patterns to Avoid
- No premature optimization without performance data
- No "just-in-case" code for hypothetical requirements
- No abstractions without at least 3 concrete usage examples
- No complex macros unless absolutely necessary
- No overly clever solutions that prioritize elegance over maintainability

## Integration Testing Requirements

### Core Principles
- Test with REAL WebSocket endpoints when possible
- Use local test server with `Plug.Cowboy` for controlled testing
- Test behavior under realistic conditions (network issues, reconnection)
- Document test scenarios thoroughly

### Test Structure
- Create proper test helpers in `test/support/`
- Use modular test server implementation
- Tag integration tests with `@tag :integration`
- Structure test cases to cover full client lifecycle
- Test both success and failure scenarios

## Documentation Requirements

### Required Documentation Structure
- `docs/architecture.md`: Component diagrams and design decisions
- `docs/client_macro.md`: Usage examples and best practices
- `docs/integration_testing.md`: Integration testing patterns
- `docs/behaviors.md`: Available behaviors and their purposes
- `docs/TaskList.md`: Structured task tracking with WNX#### format

### Documentation Standards
- All public modules and functions must have documentation
- Use consistent formatting and examples
- Include typical usage patterns
- Document error scenarios and handling
- Follow token-optimized documentation patterns from .rules