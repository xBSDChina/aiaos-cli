# AIAOS-CLI Design

## Overview

AIAOS-CLI is an AI-powered command-line interface that combines the flexibility of a CLI with the intelligence of LLMs.

## Core Principles

1. **Elisp as primary, external process as auxiliary**
2. **Async non-blocking IO**
3. **Buffer as interface (not popup)**
4. **C-c a key prefix**

## Architecture

```
┌─────────────────────────────────────────────┐
│              AIAOS-CLI Emacs                 │
├─────────────────────────────────────────────┤
│  Core Layer                                  │
│  ├─ aiaos-cli-core.el     (Configuration)    │
│  ├─ aiaos-cli-app.el      (Application)     │
│  ├─ aiaos-cli-state.el    (State management) │
│  └─ aiaos-cli-context.el  (Context)          │
├─────────────────────────────────────────────┤
│  UI Layer                                    │
│  ├─ aiaos-cli-components.el (UI components)  │
│  ├─ aiaos-cli-component.el  (Base component) │
│  └─ aiaos-cli-theme.el     (Theming)         │
├─────────────────────────────────────────────┤
│  LLM Layer                                   │
│  ├─ aiaos-cli-llm.el       (LLM management)  │
│  ├─ aiaos-cli-security.el  (Security)        │
│  └─ aiaos-cli-selfheal.el  (Self-healing)    │
├─────────────────────────────────────────────┤
│  Utilities                                   │
│  ├─ aiaos-cli-events.el    (Event system)    │
│  ├─ aiaos-cli-monitor.el   (Monitoring)      │
│  ├─ aiaos-cli-history.el   (History)         │
│  ├─ aiaos-cli-router.el    (Routing)         │
│  ├─ aiaos-cli-command.el   (Commands)        │
│  ├─ aiaos-cli-lifecycle.el (Lifecycle)        │
│  ├─ aiaos-cli-utils.el     (Utilities)       │
│  ├─ aiaos-cli-async.el     (Async)           │
│  ├─ aiaos-cli-cache.el     (Caching)         │
│  ├─ aiaos-cli-logging.el   (Logging)         │
│  └─ aiaos-cli-validate.el  (Validation)      │
└─────────────────────────────────────────────┘
```

## Data Flow

1. User input → Command parser → Router
2. Router → LLM provider → Response
3. Response → UI renderer → Buffer display
4. Buffer → User input (loop)

## Configuration

See `CONFIGURATION.md` for configuration details.

## Extensibility

- **Skills**: Custom commands via skill files
- **Components**: New UI components
- **Themes**: Custom themes
- **Hooks**: Lifecycle hooks