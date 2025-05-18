# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2025-01-19

### Added
- Initial release of WebsockexNova
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

[Unreleased]: https://github.com/ZenHive/websockex_nova/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/ZenHive/websockex_nova/releases/tag/v0.1.0