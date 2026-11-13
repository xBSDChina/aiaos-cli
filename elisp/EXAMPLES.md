# AIAOS-CLI Examples

This document provides examples of using AIAOS-CLI.

## Basic Usage

### Running a command

```elisp
;; Run ls command
(aiaos-cli-run "ls" '("-la"))

;; Run with custom buffer
(aiaos-cli-run "git" '("status") "*git-status*")
```

### Session management

```elisp
;; Create a session
(aiaos-cli-session-create "my-session")

;; List sessions
(aiaos-cli-session-list)

;; Switch to a session
(aiaos-cli-session-switch "my-session")

;; Close a session
(aiaos-cli-session-close "my-session")
```

### Context management

```elisp
;; Set context
(aiaos-cli-context-set "working-directory" "/home/user/projects")

;; Get context
(aiaos-cli-context-get "working-directory")

;; Clear context
(aiaos-cli-context-clear "working-directory")
```

## LLM Integration

### Register a provider

```elisp
(aiaos-llm-register-provider
 "openrouter"
 "https://openrouter.ai/api/v1"
 "mistralai/mistral-7b-instruct"
 "your-api-key")
```

### Call LLM

```elisp
;; Simple call
(aiaos-llm-call "What is Emacs?")

;; With provider
(aiaos-llm-call "What is Emacs?" "openrouter")

;; With callback
(aiaos-llm-call "What is Emacs?" "openrouter"
                (lambda (response) (message "Response: %s" response)))
```

### Fallback chain

```elisp
;; Set fallback chain
(customize-set-variable 'aiaos-llm-fallback-chain
                          '("openrouter" "deepseek" "anthropic"))

;; Call with fallback
(aiaos-llm-call-with-fallback "Hello")
```

## Skills

### Load a skill

```elisp
(aiaos-cli-skill-load "git-commit")
```

### Execute a skill command

```elisp
(aiaos-cli-skill-execute "git-commit" "commit-all")
```

## Security

### Store API key

```elisp
(aiaos-cli-security-store-key "openrouter" "sk-...")
```

### Retrieve API key

```elisp
(aiaos-cli-security-retrieve-key "openrouter")
```

## Events

### Publish an event

```elisp
(aiaos-cli-events-publish 'task-started '((name . "my-task")))
```

### Subscribe to an event

```elisp
(aiaos-cli-events-subscribe 'task-completed
                            (lambda (event)
                              (message "Task completed: %s" event)))
```

## Advanced Examples

### Continuous task execution

```elisp
;; Execute a chain of tasks
(aiaos-llm-task-chain
 '(("Analyze codebase" . "src/")
  ("Generate tests" . "test/")
  ("Run tests" . "make test")))
```

### Custom UI component

```elisp
;; Create a custom component
(aiaos-cli-component-create
 :name 'my-custom-component
 :render (lambda () (aiaos-cli-component-text "Hello World!"))
 :update (lambda (new-data) (message "Updated: %s" new-data)))
```

### Performance monitoring

```elisp
;; Start monitoring
(aiaos-cli-monitor-start)

;; Get metrics
(aiaos-cli-monitor-get-metric 'response-time)

;; Stop monitoring
(aiaos-cli-monitor-stop)
```

### Self-healing

```elisp
;; Check system health
(aiaos-cli-selfheal-check)

;; Manual recovery
(aiaos-cli-selfheal-recover)
```