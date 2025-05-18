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
| WNX0002 | Implement Access behavior for ClientConn | Planned | High | | |
| WNX0003 | Fix transport options format validation | Planned | High | | |
| WNX0004 | Enhance subscription preservation | Planned | Medium | | |

## Completed Tasks
| ID | Description | Status | Priority | Assignee | Review Rating |
| --- | --- | --- | --- | --- | --- |
| WNX0001 | Fix connection tracking during reconnection | Completed | Critical | Executor | 4.5 (2023-10-24) |

## Active Task Details

### WNX0001: Fix connection tracking during reconnection
**Description**: When a connection is lost and automatically reconnected, the client's connection object doesn't get updated with the new process information. This leads to errors when attempting to use the connection after reconnection, as it still references the old (dead) process. Instead of rewriting a lot of code, we will simply use the existing conn that we receive and match it internally to the new process, minimizing code changes while solving the underlying issue.

This bug was discovered in our comprehensive test suite for the Deribit adapter:
- **Test File**: `test/websockex_nova/examples/adapter_deribit_comprehensive_test.exs`
- **Test Method**: We created a test called `handles reconnection gracefully` that:
  1. Established a connection to test.deribit.com
  2. Forced a disconnect using `Client.close(conn)`
  3. Waited for automatic reconnection
  4. Attempted to send a message using the original connection reference
- **Bug Manifestation**: The test failed with the error: `** (EXIT) no process: the process is not alive or there's no process currently associated with the given name` because the conn.transport_pid still pointed to the original (now dead) process.

**Implementation Summary**:
The issue was fixed using the following approach:
1. Created a `ConnectionRegistry` module that maps stable connection IDs to transport PIDs
2. Added a `connection_id` field to `ClientConn` struct that persists across reconnections
3. Implemented `ClientConn.get_current_transport_pid/1` for dynamic transport PID resolution
4. Updated `WebsockexNova.Gun.ConnectionWrapper.send_frame/3` to use the dynamic resolution
5. Enhanced connection wrapper to register and update the registry during reconnection
6. Added comprehensive unit tests for the registry and ClientConn functionality

This approach allows transparent reconnection by:
- Using a stable `connection_id` reference that persists across reconnections
- Looking up the current transport_pid dynamically when operations are performed
- Automatically updating the registry when reconnection occurs
- Requiring no changes to client code that uses existing connections

**Technical Details**:
- `ConnectionRegistry` implements a simple Registry-based lookup system
- When a connection is established, it generates a unique `connection_id` (reference)
- During reconnection, only the registry is updated with the new transport PID
- ClientConn operations use `get_current_transport_pid/1` to dynamically resolve the current PID
- The solution falls back to the stored PID if registry lookup fails
- Connection references remain valid across any number of reconnections

**Simplicity Progression Plan**:
1. ✅ Created minimal registry for connection ID to transport_pid mapping
2. ✅ Added connection_id field to ClientConn struct
3. ✅ Modified transport operations to use current transport_pid from registry
4. ✅ Updated reconnection logic to update registry entries
5. ✅ Added tests to verify the solution works

**Simplicity Principle**:
Use indirection rather than update propagation to maintain connection identity across reconnects

**Abstraction Evaluation**:
- **Challenge**: Should we create a new abstraction for tracking connections across reconnects?
- **Minimal Solution**: Created a simple registry to map stable IDs to current transport PIDs
- **Justification**:
  1. The registry provides a level of indirection without changing existing interfaces
  2. Client code continues to work with the same connection objects
  3. No changes required to client API or behavior

**ExUnit Test Verification**:
- Added test `connection_id persists across reconnection and registry updates correctly`
- Enhanced existing reconnection test to verify operations work with original connection
- Created unit tests for `ConnectionRegistry` with 7 test cases
- Created unit tests for `ClientConn.get_current_transport_pid/1` with 4 test cases
- Verified both direct lookup and transport operations work after reconnection

**Status**: Completed
**Priority**: Critical
**Implementation Date**: 2023-10-24
**Implementation Notes**: Elegant indirection pattern using Registry for PID resolution
**Complexity Assessment**: Low - Used built-in Registry with minimal custom code
**Maintenance Impact**: Low - Self-contained solution with clear interface
**Review Rating**: 4.5

### WNX0002: Implement Access behavior for ClientConn
**Description**: The ClientConn struct doesn't implement the Access protocol, preventing use of map-like access patterns with it. This leads to errors when trying to access response data in a map-like way.

This issue was discovered during testing:
- **Test Files**: 
  - `test/websockex_nova/examples/adapter_deribit_comprehensive_test.exs`
  - `test/integration/deribit_comprehensive_integration_test.exs`
- **Test Method**: We created tests that:
  1. Performed authentication with the Deribit API
  2. Attempted to access the response data using map-like access syntax: `response["result"]["access_token"]`
- **Bug Manifestation**: The tests failed with the error: `** (UndefinedFunctionError) function WebsockexNova.ClientConn.fetch/2 is undefined (WebsockexNova.ClientConn does not implement the Access behaviour)`
- **Impact**: This prevents natural map-like interaction with response data, forcing developers to use more verbose access patterns.

**Simplicity Progression Plan**:
1. Implement basic Access behavior for ClientConn
2. Add tests to verify Access protocol functionality
3. Consider enhanced Access patterns if needed

**Simplicity Principle**:
Provide interfaces that match user expectations for standard Elixir patterns

**Abstraction Evaluation**:
- **Challenge**: Should ClientConn behave like a map?
- **Minimal Solution**: Implement Access behavior for connection_info field only
- **Justification**:
  1. Provides consistent interface for config access
  2. Matches user expectations for struct behavior
  3. Simplifies code that needs to work with connection configuration

**Requirements**:
- Implement fetch/2, get/3, get_and_update/3, and pop/2 for ClientConn
- Focus on connection_info as the primary access point
- Maintain backward compatibility

**ExUnit Test Requirements**:
- Tests verifying all Access protocol functions
- Tests for nested access patterns
- Tests for backward compatibility

**Integration Test Scenarios**:
- Verify code that uses map-like access patterns works with ClientConn

**Typespec Requirements**:
- Define proper Access behavior typespecs for ClientConn
- Update client API typespecs to reflect new access patterns
- Document type constraints for access behavior

**TypeSpec Documentation**:
Access behavior implementation should be documented with common access patterns

**TypeSpec Verification**:
Test with Dialyzer to ensure Access protocol implementation is complete

**Status**: Planned
**Priority**: High

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