# AIAOS CLI - Emacs Integration

AIAOS CLI Emacs integration provides a powerful command-line interface within Emacs, enabling seamless interaction with the AIAOS framework.

## Features

- **Full Emacs Integration**: Run AIAOS commands directly from Emacs
- **Multi-Layer Architecture**: Foundation, analysis, and closed-loop layers
- **Self-Adaptive Mechanisms**: Self-adaptive, self-completion, self-alignment, and self-improvement
- **Multi-Dimensional Analysis**: Intent, semantic, context, and confidence analysis
- **LLM Provider Support**: Configurable LLM providers with fallback mechanisms

## Installation

### Prerequisites
- Emacs 27+
- AIAOS framework installed

### Setup
```elisp
;; Add to your Emacs config
(add-to-list 'load-path "~/.lab_A/aiaos-cli")
(require 'aiaos-cli)

;; Initialize AIAOS CLI
(aiaos-cli-mode 1)
```

## Usage

### Basic Commands
- `M-x aiaos-cli` - Open AIAOS CLI interface
- `M-x aiaos-cli-execute` - Execute a command
- `M-x aiaos-cli-history` - View command history
- `M-x aiaos-cli-config` - View configuration

### Example
```elisp
;; Execute a simple command
(aiaos-cli-execute "list files in current directory")

;; Query system status
(aiaos-cli-execute "show system status")
```

## Architecture

### Layers
1. **Foundation Layer**: Core functionality, configuration, and utilities
2. **Analysis Layer**: Multi-dimensional matrix analysis and intent recognition
3. **Closed-Loop Layer**: Execution, monitoring, and feedback mechanisms

### Self-Adaptive Mechanisms
- **Self-Adaptive**: Automatically adjust behavior based on context
- **Self-Completion**: Fill in missing information intelligently
- **Self-Alignment**: Ensure consistency across all components
- **Self-Improvement**: Learn from execution history and improve

## Configuration

Configuration files are stored in `~/.config/aiaos/`:
- `aiaos-cli.json` - Main configuration
- `llm_providers.json` - LLM provider settings

## Testing

Run the test suite:
```bash
emacs --batch -l test-aiaos-llm.el -l test-emacs-batch.el -l test-emacsclient.el --eval "(message \"Tests completed\")"
```

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Contributing

1. Fork the repository
2. Create a feature branch
3. Commit your changes
4. Push to the branch
5. Create a Pull Request
