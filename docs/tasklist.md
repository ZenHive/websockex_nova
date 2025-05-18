# WebsockexNova Task List

## Integration Test Setup Notes
- Use test.deribit.com for external testing
- Set environment variables DERIBIT_CLIENT_ID and DERIBIT_CLIENT_SECRET for authenticated tests
- Verify both public and authenticated endpoints
- Always test with real endpoints, no mocking for integration tests

## Test Files Created for Deribit Adapter
1. `test/websockex_nova/examples/adapter_deribit_comprehensive_test.exs`
   - Comprehensive tests for adapter functionality
   - Configuration preservation tests
   - Authentication tests
   - Reconnection tests

2. `test/integration/deribit_comprehensive_integration_test.exs`
   - Raw connection tests directly with test.deribit.com
   - Client API tests
   - Subscription tests
   - Authentication tests

3. `test/websockex_nova/examples/deribit_config_preservation_test.exs`
   - Focused tests for configuration preservation
   - Tests for custom options
   - Tests for nested configuration structures

These test files provide comprehensive test coverage of the Deribit adapter functionality, checking behavior in both normal operations and edge cases like reconnections and authentication failures.

## Simplicity Guidelines for All Tasks
- Implement the minimal viable solution first
- Test with real workloads
- Add complexity only when necessary
- Ensure backward compatibility

## Current Tasks
| ID | Description | Status | Priority | Assignee | Review Rating |
| --- | --- | --- | --- | --- | --- |
| WNX0004 | Enhance subscription preservation | Planned | Medium | | |

## Completed Tasks
| ID | Description | Status | Priority | Assignee | Review Rating |
| --- | --- | --- | --- | --- | --- |
| WNX0001 | Fix connection tracking during reconnection | Completed | Critical | Executor | 4.5 (2023-10-24) |
| WNX0002 | Implement Access behavior for ClientConn | Completed | High | Executor | 4.5 |
| WNX0003 | Fix transport options format validation | Completed | High | Executor | |

## Active Task Details

### Implementation Status Check (2025-01-18)

**WNX0003: Fix transport options format validation**
- **Status**: Completed (2025-01-18)
- **Implementation**: 
  - Added `normalize_transport_opts/1` function in `Client` module to convert keyword lists to maps
  - The function handles maps (pass-through), keyword lists (converts to map), and nil/invalid inputs (returns empty map)
  - Minimal change to `prepare_transport_options/2` to normalize options before passing to handlers
  - Added tests to verify both keyword list and nil transport_opts are handled correctly
  - Updated the `connect_options` type to accept `map() | Keyword.t() | nil` for transport_opts
  - Added typespecs for `normalize_transport_opts/1` and `prepare_transport_options/2`
  - All existing tests pass without modification

**WNX0004: Enhance subscription preservation** 
- **Status**: Partially implemented
- **Findings**:
  - `SubscriptionManager` has `prepare_for_reconnect/1` and `resubscribe_after_reconnect/1` functions
  - Reconnection logic exists in `ConnectionWrapper`
  - Missing integration between subscription restoration and reconnection flow
  - Subscription preservation is not automatically triggered during reconnections


### WNX0003: Fix transport options format validation
**Description**: Currently, transport options must be passed as a map, but the code doesn't properly validate or convert keyword lists, leading to function clause errors.

This issue was discovered during integration testing:
- **Test File**: `test/integration/deribit_comprehensive_integration_test.exs`
- **Test Method**: We created tests that:
  1. Initialized connection options with transport_opts as a keyword list:
     ```elixir
     transport_opts = [
       verify: :verify_peer,
       cacerts: :certifi.cacerts(),
       server_name_indication: ~c"test.deribit.com"
     ]
     ```
  2. Attempted to pass these to the connection function
- **Bug Manifestation**: The tests failed with the error: `** (FunctionClauseError) no function clause matching in WebsockexNova.Client.Handlers.configure_handlers/2`
- **Resolution**: We had to convert the transport_opts to a map to make the tests pass:
  ```elixir
  transport_opts = %{
    verify: :verify_peer,
    cacerts: :certifi.cacerts(),
    server_name_indication: ~c"test.deribit.com"
  }
  ```

**Simplicity Progression Plan**:
1. Add proper validation/conversion of transport options
2. Update documentation to clarify expected format
3. Add tests for different input formats

**Simplicity Principle**:
Accept diverse input formats but normalize internally for consistent handling

**Abstraction Evaluation**:
- **Challenge**: How should we handle different option formats?
- **Minimal Solution**: Convert keyword lists to maps when received
- **Justification**:
  1. Provides better developer experience
  2. Prevents confusing errors
  3. Matches Elixir conventions for handling options

**Requirements**:
- Handle both map and keyword list formats for transport options
- Provide clear error messages for invalid formats
- Update documentation to clarify expected formats

**ExUnit Test Requirements**:
- Tests with map-style options
- Tests with keyword-list options
- Tests with invalid option formats

**Integration Test Scenarios**:
- Verify both map and keyword list formats work in real connections

**Typespec Requirements**:
- Define transport options type specifications that allow both maps and keyword lists
- Update validation function typespecs to properly indicate input/output types
- Document type constraints for transport options

**TypeSpec Documentation**:
Document transport options types with examples of both map and keyword list formats

**TypeSpec Verification**:
Use Dialyzer to verify type compatibility across the transport layer

**Status**: Planned
**Priority**: High

### WNX0004: Enhance subscription preservation during reconnection
**Description**: While the library attempts to preserve subscriptions across reconnection, the tests revealed that it's difficult to verify this functionality due to issues with connection tracking. After fixing the connection tracking issue, subscription preservation needs to be thoroughly tested and potentially enhanced.

This issue was discovered during our comprehensive testing:
- **Test File**: `test/websockex_nova/examples/adapter_deribit_comprehensive_test.exs`
- **Test Method**: We created a test called `preserves subscriptions across reconnects` that:
  1. Connected to the Deribit test server
  2. Subscribed to multiple channels (ticker, trades)
  3. Attempted to access subscription state via the internal connection state
  4. Forced a disconnection and waited for reconnection
  5. Tried to verify subscriptions were restored after reconnection
- **Bug Manifestation**: The test failed with both access issues and connection tracking issues
- **Validation Challenge**: We couldn't properly validate subscription preservation because:
  1. We couldn't access the internal state reliably
  2. The reconnection tracking issue prevented performing operations after reconnect
  3. There's no standardized way to query current active subscriptions

**Simplicity Progression Plan**:
1. Add proper tests for subscription preservation
2. Fix any issues discovered in subscription handling
3. Add metrics/logging for subscription tracking
4. Consider improvements to subscription restoration process

**Simplicity Principle**:
Maintain subscription state transparently across reconnections without extra client code

**Abstraction Evaluation**:
- **Challenge**: How to reliably preserve subscriptions across reconnects?
- **Minimal Solution**: Maintain subscription list and resubscribe after reconnection
- **Justification**:
  1. Essential for financial data streaming
  2. Expected by client applications
  3. Reduces complexity in client code

**Requirements**:
- Ensure all active subscriptions are tracked
- Automatically resubscribe after successful reconnection
- Provide configuration options for subscription behavior
- Handle errors during resubscription

**ExUnit Test Requirements**:
- Tests verifying subscriptions are preserved after reconnection
- Tests for subscription failure handling
- Tests for configuration options

**Integration Test Scenarios**:
- Subscribe to multiple channels, force disconnect, verify all are restored
- Test with authenticated (private) subscription channels
- Test with mix of subscription types

**Typespec Requirements**:
- Define subscription state types
- Define subscription restoration function typespecs
- Create typespecs for subscription tracking mechanisms

**TypeSpec Documentation**:
Document subscription-related types with examples of common subscription patterns

**TypeSpec Verification**:
Use Dialyzer to verify type consistency in subscription handling code

**Status**: Planned
**Priority**: Medium
