# Changelog

All notable changes to this project will be documented in this file.

## [1.0.0] - 2026-10-01

### Added
- Initial release of AIAOS-CLI Emacs frontend
- Core modules: aiaos-cli-core, aiaos-cli-app, aiaos-cli-components
- LLM provider management with fallback chain
- Security module with API key encryption
- Self-healing engine for automatic recovery
- Performance monitoring and metrics collection
- Event system for decoupled component communication
- History and context memory management
- Async processing utilities
- Caching system
- Logging framework
- Input validation

### Features
- Run aiaos-cli subcommands from Emacs
- Session management (create, list, switch, close)
- Context management (set, list, clear)
- Buffer-based interface (not popup)
- C-c a key prefix
- LLM provider registration and switching
- Fallback chain for LLM providers
- Continuous task execution
- Skills management
- Security features (API key encryption, ACL, rate limiting)

## [0.9.0] - 2026-09-15

### Added
- Early prototype with basic command execution
- Simple buffer interface
- Basic LLM integration

## [0.8.0] - 2026-09-01

### Added
- Project restructuring
- Initial documentation