# WebsockexNew Advanced Guides

This directory contains advanced documentation for WebsockexNew's macro system and behavior implementations.

## 📚 Guide Index

### Core Concepts
- [Advanced Macros](advanced_macros.md) - Complex macro patterns and techniques
- [Behavior Composition](behavior_composition.md) - Composing behaviors for flexibility
- [Architectural Patterns](architectural_patterns.md) - Proven patterns for WebSocket systems

### Development
- [Testing Behaviors](testing_behaviors.md) - Comprehensive testing strategies
- [Performance Tuning](performance_tuning.md) - Optimization techniques for production
- [Troubleshooting](troubleshooting.md) - Debugging and problem resolution

### Migration
- [Migration Guide](migration_guide.md) - Moving from raw behaviors to macros

### Existing Guides
- [Gun Integration](gun_integration.md) - Working with the Gun transport layer
- [Metrics Export](metrics_export.md) - Exporting metrics for monitoring

## 🎯 Quick Start

If you're new to WebsockexNew's advanced features, we recommend reading the guides in this order:

1. Start with [Advanced Macros](advanced_macros.md) to understand the macro system
2. Learn about [Behavior Composition](behavior_composition.md) for building complex behaviors
3. Review [Testing Behaviors](testing_behaviors.md) to ensure reliability
4. Explore [Architectural Patterns](architectural_patterns.md) for system design
5. Optimize with [Performance Tuning](performance_tuning.md)

## 🔍 Finding Information

### By Topic

**Macros & Behaviors**
- Macro composition patterns → [Advanced Macros](advanced_macros.md)
- Behavior stacking and delegation → [Behavior Composition](behavior_composition.md)
- Testing strategies → [Testing Behaviors](testing_behaviors.md)

**System Design**
- Architecture patterns → [Architectural Patterns](architectural_patterns.md)
- Connection management → [Architectural Patterns](architectural_patterns.md#connection-management-patterns)
- Message flow patterns → [Architectural Patterns](architectural_patterns.md#message-flow-patterns)

**Performance & Production**
- Optimization techniques → [Performance Tuning](performance_tuning.md)
- Production issues → [Troubleshooting](troubleshooting.md#production-issues)
- Monitoring → [Metrics Export](metrics_export.md)

**Migration & Integration**
- Migrating existing code → [Migration Guide](migration_guide.md)
- Gun integration → [Gun Integration](gun_integration.md)

### By Use Case

**"I want to create a complex client with multiple behaviors"**
→ See [Behavior Composition](behavior_composition.md) and [Advanced Macros](advanced_macros.md)

**"I need to optimize my WebSocket performance"**
→ See [Performance Tuning](performance_tuning.md) and [Architectural Patterns](architectural_patterns.md#scaling-patterns)

**"I'm having issues with my behaviors not working"**
→ See [Troubleshooting](troubleshooting.md#behavior-issues)

**"I want to migrate my existing implementation"**
→ See [Migration Guide](migration_guide.md)

## 📖 Guide Conventions

All guides follow these conventions:

- **Code examples** are complete and runnable
- **Best practices** are highlighted in each section
- **Common pitfalls** are explicitly called out
- **Performance implications** are noted where relevant
- **Testing approaches** are included for all patterns

## 🤝 Contributing

To contribute to these guides:

1. Follow the existing format and conventions
2. Include working code examples
3. Add troubleshooting sections for complex topics
4. Link to related guides where appropriate
5. Update this index when adding new guides

## 📞 Getting Help

If you need help with any topic:

1. Check the [Troubleshooting Guide](troubleshooting.md)
2. Review the specific guide's troubleshooting section
3. Search the codebase for usage examples
4. Open an issue on GitHub

## 🚀 Next Steps

After reading these guides, you might want to:

- Explore the [examples directory](../../lib/websockex_new/examples/) for real implementations
- Review the [test suite](../../test/) for testing patterns
- Check the [API documentation](../api/) for detailed references