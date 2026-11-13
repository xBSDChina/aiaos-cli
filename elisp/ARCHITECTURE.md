# AIAOS-CLI Emacs Frontend Architecture

## Overview

The AIAOS-CLI Emacs frontend is an Emacs Lisp interface that provides a rich user experience for the AIAOS-CLI command-line tool. It follows the AIAOS-CLI paradigm defined in `~/aiaos-cli_design.md`:

- **Elisp as primary, external process as auxiliary**
- **Async non-blocking IO**
- **Buffer as interface (not popup)**
- **C-c a key prefix**

## System Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    AIAOS-CLI Emacs Frontend                   │
├─────────────────────────────────────────────────────────────┤
│  Main Entry Point (aiaos-cli.el)                            │
│  ├── Core Interfaces (aiaos-cli-core.el)                    │
│  ├── State Management (aiaos-cli-state.el)                  │
│  ├── Context Management (aiaos-cli-context.el)              │
│  ├── Lifecycle Hooks (aiaos-cli-lifecycle.el)               │
│  ├── Component Management (aiaos-cli-component.el)          │
│  ├── Component Definitions (aiaos-cli-components.el)        │
│  ├── Command Routing (aiaos-cli-router.el)                  │
│  ├── Application Logic (aiaos-cli-app.el)                   │
│  ├── Command Execution (aiaos-cli-command.el)               │
│  ├── Theme & Faces (aiaos-cli-theme.el)                     │
│  ├── LLM Integration (aiaos-cli-llm.el)                     │
│  ├── Events (aiaos-cli-events.el)                           │
│  ├── History (aiaos-cli-history.el)                         │
│  ├── Monitoring (aiaos-cli-monitor.el)                      │
│  ├── Security (aiaos-cli-security.el)                       │
│  ├── Self-Healing (aiaos-cli-selfheal.el)                   │
│  └── Tests (aiaos-cli-tests.el)                             │
└─────────────────────────────────────────────────────────────┘
```

## Module Details

### Core Layer

- **aiaos-cli-core.el**: Core interfaces, types, and base functionality
- **aiaos-cli-state.el**: Application state management
- **aiaos-cli-context.el**: Context management for sessions

### Application Layer

- **aiaos-cli-app.el**: Application logic and orchestration
- **aiaos-cli-command.el**: Command execution and parsing
- **aiaos-cli-router.el**: Command routing and dispatch

### Component Layer

- **aiaos-cli-component.el**: Component management framework
- **aiaos-cli-components.el**: Pre-defined components

### Support Layer

- **aiaos-cli-lifecycle.el**: Lifecycle hooks and initialization
- **aiaos-cli-theme.el**: Theme and face definitions
- **aiaos-cli-events.el**: Event handling system
- **aiaos-cli-history.el**: Command history management
- **aiaos-cli-monitor.el**: Performance monitoring
- **aiaos-cli-security.el**: Security features
- **aiaos-cli-selfheal.el**: Self-healing mechanisms

### Integration Layer

- **aiaos-cli-llm.el**: LLM integration and API communication

## Data Flow

```
User Input → Router → Command → Execution → Result Buffer
                ↓
           Context Manager
                ↓
           State Manager
```

## Design Principles

1. **Elisp First**: Primary logic in Emacs Lisp, external processes only for heavy lifting
2. **Async Non-blocking**: All I/O operations are asynchronous to keep Emacs responsive
3. **Buffer Interface**: Results displayed in dedicated buffers, not popups
4. **Extensible**: Skills and components can be loaded dynamically
5. **Modular**: Each module has a single responsibility and clear interfaces

## Key Patterns

### Command Pattern

```elisp
(aiaos-cli-run "command" :arg1 val1 :arg2 val2)
```

### Session Pattern

```elisp
(aiaos-cli-session-create "session-name")
(aiaos-cli-session-switch "session-name")
(aiaos-cli-session-close "session-name")
```

### Context Pattern

```elisp
(aiaos-cli-context-set "key" "value")
(aiaos-cli-context-list)
(aiaos-cli-context-export)
```

## Performance Characteristics

- **Async Operations**: All I/O operations are non-blocking
- **Timeout Management**: Configurable timeouts for different operations
- **Memory Management**: Efficient state management with minimal overhead
- **Caching**: Strategic caching for frequently accessed data

## Security Model

- **Input Validation**: All user inputs are validated
- **Process Isolation**: External processes run in isolated environments
- **Access Control**: Fine-grained access control for sensitive operations

## Extensibility Points

1. **Skills**: Custom commands can be added via skill files
2. **Components**: New UI components can be registered
3. **Themes**: Custom themes can be created
4. **Hooks**: Lifecycle hooks allow customization at various points