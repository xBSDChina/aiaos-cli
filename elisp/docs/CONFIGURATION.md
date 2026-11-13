# AIAOS-CLI Configuration

## Configuration File

AIAOS-CLI uses `~/.aiaos-cli.json` for configuration.

## Configuration Structure

```json
{
  "providers": [
    {
      "name": "openrouter",
      "endpoint": "https://openrouter.ai/api/v1",
      "model": "mistralai/mistral-7b-instruct",
      "api-key": "your-api-key"
    }
  ],
  "skills": {
    "directory": "~/aiaos/aiaos-cli/skills"
  },
  "ui": {
    "theme": "dark",
    "buffer-name": "*aiaos-cli*",
    "key-prefix": "C-c a"
  },
  "security": {
    "keychain-file": "~/.aiaos-cli-keychain",
    "encrypt-method": "xor"
  },
  "monitoring": {
    "enabled": true,
    "interval": 30
  }
}
```

## Configuration Options

### providers

List of LLM provider configurations.

- `name`: Provider name
- `endpoint`: API endpoint URL
- `model`: Model name
- `api-key`: API key

### skills

Skill configuration.

- `directory`: Directory containing skills

### UI

User interface configuration.

- `theme`: Theme name
- `buffer-name`: Buffer name
- `key-prefix`: Key prefix

### security

Security configuration.

- `keychain-file`: File for storing API keys
- `encrypt-method`: Encryption method

### monitoring

Monitoring configuration.

- `enabled`: Enable monitoring
- `interval`: Check interval in seconds

## Loading Configuration

```elisp
;; Load configuration
(aiaos-cli-config-load)

;; Get configuration value
(aiaos-cli-config-get 'providers)

;; Set configuration value
(aiaos-cli-config-set 'providers (list ...))
```

## Hot Reload

```elisp
;; Reload configuration from disk
(aiaos-cli-config-reload)
```