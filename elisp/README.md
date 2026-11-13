# AIAOS-CLI Emacs Frontend

AIAOS-CLI Emacs frontend provides an Emacs interface for the AIAOS-CLI command-line tool. It follows the AIAOS-CLI paradigm defined in `~/aiaos-cli_design.md`:

- **Elisp as primary, external process as auxiliary**
- **Async non-blocking IO**
- **Buffer as interface (not popup)**
- **C-c a key prefix**

## Features

- Run arbitrary aiaos-cli subcommands from Emacs
- Session management (create, list, switch, close)
- Context management (set, list, export, clear)
- Skill management (load, list, execute)
- Agent chat (interactive)
- Environment doctor (`aiaos-cli-doctor`)
- Log tailing in dedicated buffer
- Customizable major modes for results and chat

## Installation

### Prerequisites

- Emacs 29.0 or later
- aiaos executable in PATH or specified via `aiaos-cli-bin`

### Setup

```elisp
;; Add to your Emacs configuration
(add-to-list 'load-path "/path/to/aiaos-cli/elisp")
(require 'aiaos-cli)
(aiaos-cli-init)
```

### Keybindings

After loading, the following keybindings are available (prefix `C-c a`):

- `C-c a r` - Run aiaos-cli subcommand
- `C-c a s` - Session commands
- `C-c a c` - Context commands
- `C-c a k` - Skill commands
- `C-c a C-c` - Agent chat
- `C-c a d` - Doctor
- `C-c a l` - Log tail

## Configuration

### Customizable Variables

- `aiaos-cli-bin` - Path to the aiaos executable
- `aiaos-cli-default-format` - Default output format (json, table, raw)
- `aiaos-cli-async-timeout` - Timeout for async invocations (seconds)
- `aiaos-cli-key-prefix` - Key prefix for aiaos-cli commands
- `aiaos-cli-result-buffer-name` - Name of the result buffer
- `aiaos-cli-chat-buffer-name` - Name of the agent chat buffer
- `aiaos-cli-skills-dir` - Directory containing skills

### Example

```elisp
;; Set custom aiaos binary path
(customize aiaos-cli-bin "/usr/local/bin/aiaos")

;; Increase timeout for complex operations
(customize aiaos-cli-async-timeout 180)
```

## Architecture

### Module Structure

```
aiaos-cli.el              - Main entry point and keybindings
├── aiaos-cli-core.el      - Core interfaces and types
├── aiaos-cli-state.el     - State management
├── aiaos-cli-context.el   - Context management
├── aiaos-cli-lifecycle.el - Lifecycle hooks
├── aiaos-cli-component.el - Component management
├── aiaos-cli-components.el - Component definitions
├── aiaos-cli-router.el    - Command routing
├── aiaos-cli-app.el       - Application logic
├── aiaos-cli-command.el   - Command execution
├── aiaos-cli-theme.el     - Theme and faces
├── aiaos-cli-llm.el       - LLM integration
├── aiaos-cli-events.el    - Event handling
├── aiaos-cli-history.el   - History management
├── aiaos-cli-monitor.el   - Monitoring
├── aiaos-cli-security.el  - Security features
├── aiaos-cli-selfheal.el  - Self-healing mechanisms
└── aiaos-cli-tests.el     - Test suite
```

### Design Principles

1. **Elisp First**: Primary logic in Emacs Lisp, external processes only for heavy lifting
2. **Async Non-blocking**: All I/O operations are asynchronous to keep Emacs responsive
3. **Buffer Interface**: Results displayed in dedicated buffers, not popups
4. **Extensible**: Skills and components can be loaded dynamically
5. **Modular**: Each module has a single responsibility and clear interfaces

## Usage

### Running Commands

```elisp
;; Run a simple command
(aiaos-cli-run "list" :format 'json)

;; Run with context
(aiaos-cli-run "search" :query "example" :limit 10)
```

### Session Management

```elisp
;; Create a new session
(aiaos-cli-session-create "my-session")

;; Switch to an existing session
(aiaos-cli-session-switch "my-session")

;; Close a session
(aiaos-cli-session-close "my-session")
```

### Agent Chat

```elisp
;; Start an interactive agent chat
(aiaos-cli-agent-chat)
```

## Testing

Run the test suite:

```elisp
;; Load and run tests
(require 'aiaos-cli-tests)
(aiaos-cli-run-tests)
```

### Using Makefile

```bash
# Compile all files
make compile

# Run tests
make test

# Check code quality
make check

# Clean compiled files
make clean
```

## Development

### Setup

```bash
# Set up development environment
make setup

# Build the project
make build

# Run tests
make test
```

### Code Style

- Use `lexical-binding: t` at the top of all files
- Use `defcustom` for user-configurable variables
- Use `defgroup` for grouping related variables
- Use `require` for dependencies
- Use `cl-lib` for Common Lisp extensions

### Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines on contributing to the project.

## Documentation

- [Architecture](ARCHITECTURE.md) - Detailed architecture documentation
- [Dependencies](DEPENDENCIES.md) - Dependency management
- [Contributing](CONTRIBUTING.md) - Contribution guidelines
- [Implementation Summary](IMPLEMENTATION-SUMMARY.md) - Implementation details
- [Modules](MODULES.md) - Module documentation
- [LLM Integration](README-AIAOS-LLM.md) - LLM integration guide
- [Testing](TESTING.md) - Testing documentation
- [API](API.md) - API documentation
- [Examples](EXAMPLES.md) - Usage examples
- [Skills](SKILLS.md) - Skills documentation
- [Configuration](docs/CONFIGURATION.md) - Configuration guide
- [Design](docs/DESIGN.md) - Design document
- [Troubleshooting](docs/TROUBLESHOOTING.md) - Troubleshooting guide

## License

MIT License - see [LICENSE](LICENSE) file for details.

## Author

AIAOS Project / xBSDChina

## Links

- GitHub: https://github.com/xBSDChina/aiaos-cli
- Issue Tracker: https://github.com/xBSDChina/aiaos-cli/issues