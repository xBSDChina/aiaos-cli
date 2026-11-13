# Troubleshooting

Common issues and solutions for AIAOS-CLI.

## Installation Issues

### Emacs version too old

**Symptoms**: Error when loading aiaos-cli.el

**Solution**: Upgrade to Emacs 29.0 or later
```bash
# Check version
emacs --version

# Install newer version
sudo apt install emacs  # Ubuntu/Debian
brew install emacs     # macOS
```

### Missing dependencies

**Symptoms**: Error about missing packages

**Solution**: Install required packages
```bash
make deps
```

## Configuration Issues

### Configuration file not found

**Symptoms**: "Config file not found" error

**Solution**: Create configuration file
```elisp
(aiaos-cli-config-init)
```

### Invalid configuration

**Symptoms**: "Invalid configuration" error

**Solution**: Validate configuration
```elisp
(aiaos-cli-config-validate (aiaos-cli-config-load))
```

## LLM Issues

### Provider not responding

**Symptoms**: Timeout errors when calling LLM

**Solution**:
1. Check API key
2. Check endpoint URL
3. Try fallback provider
```elisp
(aiaos-llm-call-with-fallback prompt)
```

### HTTP 404 error

**Symptoms**: "HTTP 404" error

**Solution**:
1. Check model name
2. Check endpoint URL
3. Verify provider configuration
```elisp
(aiaos-llm-probe-provider provider-name)
```

## Performance Issues

### Slow response

**Symptoms**: AIAOS-CLI is slow

**Solution**:
1. Check network connection
2. Reduce timeout
3. Enable caching
```elisp
(customize-set-variable 'aiaos-cli-cache-default-ttl 60)
```

### High memory usage

**Symptoms**: Emacs using too much memory

**Solution**:
1. Clear cache
```elisp
(aiaos-cli-cache-clear)
```
2. Reduce history size
```elisp
(customize-set-variable 'aiaos-history-max-entries 50)
```

## UI Issues

### Buffer not showing

**Symptoms**: AIAOS-CLI buffer not appearing

**Solution**:
1. Check if process started
2. Check buffer name
```elisp
(switch-to-buffer "*aiaos-cli*")
```

### Keybindings not working

**Symptoms**: C-c a prefix not working

**Solution**:
1. Check for conflicting bindings
2. Re-load keybindings
```elisp
(aiaos-cli-keybindings-setup)
```

## Getting Help

If you can't find a solution:

1. Check the [issues](https://github.com/xBSDChina/aiaos-cli/issues)
2. Create a new issue with:
   - Emacs version
   - AIAOS-CLI version
   - Error message
   - Steps to reproduce