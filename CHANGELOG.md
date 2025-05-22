# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

_Last updated: 2025-05-22_

## [0.1.1] - 2025-05-22

### Fixed
- Resolved compiler warnings in tests
- Removed unused init function in adapter_deribit.ex for cleaner code
- Enhanced Deribit heartbeat handling with proper test_request response format
- Improved connection management with ConnectionHandler callbacks

### Changed
- Updated function signatures to ignore unused parameters for better clarity
- Enhanced test assertions for stream_ref verification in heartbeat responses
- Refactored adapter_deribit for better connection state management
- Improved code formatting and readability across multiple files

### Added
- Better ConnectionHandler callback implementations in AdapterDeribit
- Enhanced heartbeat integration test coverage
- Improved message handler verification in tests

_Last updated: 2025-05-22_

## [0.1.0] - 2025-05-19

### Added
- Initial release of WebsockexNew
- Behavior-based architecture for WebSocket client functionality
- Gun transport layer integration for high-performance connections
- Automatic reconnection support with configurable strategies
- Subscription management with preservation across reconnections
- Authentication handler behavior for custom auth flows
- Rate limiting support with configurable behavior
- Comprehensive telemetry events for monitoring
- Connection registry for stable connection ID tracking
- Example adapters for common use cases (Deribit exchange)
- ClientMacro and AdapterMacro for rapid development
- Extensive test coverage including integration tests
- Full documentation and usage examples

### Fixed
- Connection tracking during reconnection cycles (WNX0001)
- Access behavior implementation for ClientConn (WNX0002)
- Transport options format validation for keyword lists (WNX0003)
- Subscription preservation enhancements (WNX0004)

[Unreleased]: https://github.com/ZenHive/websockex_new/compare/v0.1.1...HEAD
[0.1.1]: https://github.com/ZenHive/websockex_new/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/ZenHive/websockex_new/releases/tag/v0.1.0