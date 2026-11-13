# AIAOS-CLI API Documentation

This document provides API documentation for AIAOS-CLI.

## Core Functions

### aiaos-cli-run

```elisp
(aiaos-cli-run COMMAND &optional ARGS BUFFER)
```

Run an aiaos-cli command.

**Parameters:**
- `COMMAND`: The command to run (string)
- `ARGS`: Optional arguments (list)
- `BUFFER`: Optional buffer name (string)

**Returns:**
- Process object

### aiaos-cli-session-create

```elisp
(aiaos-cli-session-create &optional NAME)
```

Create a new session.

**Parameters:**
- `NAME`: Optional session name (string)

**Returns:**
- Session ID (string)

### aiaos-cli-session-list

```elisp
(aiaos-cli-session-list)
```

List all sessions.

**Returns:**
- List of session objects

### aiaos-cli-context-set

```elisp
(aiaos-cli-context-set KEY VALUE)
```

Set a context value.

**Parameters:**
- `KEY`: Context key (string)
- `VALUE`: Context value (any)

### aiaos-cli-context-get

```elisp
(aiaos-cli-context-get KEY &optional DEFAULT)
```

Get a context value.

**Parameters:**
- `KEY`: Context key (string)
- `DEFAULT`: Default value if key not found

**Returns:**
- Context value or DEFAULT

### aiaos-llm-register-provider

```elisp
(aiaos-llm-register-provider NAME ENDPOINT MODEL API-KEY &optional OPTIONS)
```

Register an LLM provider.

**Parameters:**
- `NAME`: Provider name (string)
- `ENDPOINT`: API endpoint (string)
- `MODEL`: Model name (string)
- `API-KEY`: API key (string)
- `OPTIONS`: Optional provider options (alist)

### aiaos-llm-call

```elisp
(aiaos-llm-call PROMPT &optional PROVIDER CALLBACK)
```

Call an LLM with a prompt.

**Parameters:**
- `PROMPT`: Prompt text (string)
- `PROVIDER`: Optional provider name (string)
- `CALLBACK`: Optional callback function

### aiaos-cli-skill-load

```elisp
(aiaos-cli-skill-load SKILL-NAME)
```

Load a skill by name.

**Parameters:**
- `SKILL-NAME`: Skill name (string)

**Returns:**
- Skill object or nil

## Configuration

### aiaos-cli-config-get

```elisp
(aiaos-cli-config-get KEY &optional DEFAULT)
```

Get configuration value.

### aiaos-cli-config-set

```elisp
(aiaos-cli-config-set KEY VALUE)
```

Set configuration value.

## Events

### aiaos-cli-events-publish

```elisp
(aiaos-cli-events-publish TYPE &optional DATA)
```

Publish an event.

**Parameters:**
- `TYPE`: Event type (symbol)
- `DATA`: Optional event data

### aiaos-cli-events-subscribe

```elisp
(aiaos-cli-events-subscribe TYPE CALLBACK)
```

Subscribe to an event.

**Parameters:**
- `TYPE`: Event type (symbol)
- `CALLBACK`: Callback function

## Security

### aiaos-cli-security-store-key

```elisp
(aiaos-cli-security-store-key NAME KEY)
```

Store an API key securely.

**Parameters:**
- `NAME`: Key name (string)
- `KEY`: API key (string)

### aiaos-cli-security-retrieve-key

```elisp
(aiaos-cli-security-retrieve-key NAME)
```

Retrieve a stored API key.

**Parameters:**
- `NAME`: Key name (string)

**Returns:**
- API key or nil