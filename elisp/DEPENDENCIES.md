# AIAOS-CLI Emacs Frontend Dependencies

This document lists the dependencies for the AIAOS-CLI Emacs Frontend.

## Core Dependencies

### Emacs Lisp Packages

These are the core dependencies required by AIAOS-CLI:

- **cl-lib**: Common Lisp extensions (built-in with Emacs 26+)
- **json**: JSON parsing (built-in with Emacs 26+)
- **url**: URL handling (built-in with Emacs 26+)
- **package**: Package management (built-in)

### External Dependencies

- **aiaos**: The AIAOS-CLI command-line tool
  - Install from: https://github.com/xBSDChina/aiaos-cli
  - Or build from source in `~/aiaos/bin/aiaos`

## Optional Dependencies

- **org**: For org-mode integration (built-in)
- **ivy**: For enhanced completion (optional)
- **magit**: For Git integration (optional)
- **which-key**: For keybinding help (optional)

## Version Requirements

| Package | Minimum Version | Notes |
|---------|----------------|-------|
| Emacs | 29.0 | Required for `lexical-binding` and modern features |
| cl-lib | 2.0 | Built-in with Emacs 26+ |
| json | 1.0 | Built-in with Emacs 26+ |
| aiaos | 1.0.0 | External dependency |

## Installation

### Manual Installation

```bash
# Clone the repository
git clone https://github.com/xBSDChina/aiaos-cli.git
cd aiaos-cli/elisp

# Add to your Emacs configuration
(add-to-list 'load-path "/path/to/aiaos-cli/elisp")
(require 'aiaos-cli)
(aiaos-cli-init)
```

### Using package-archives

```elisp
;; Add to your Emacs configuration
(add-to-list 'package-archives
             '("melpa" . "https://melpa.org/packages/") t)
(package-initialize)

;; Install aiaos-cli
(unless (package-installed-p 'aiaos-cli)
  (package-install 'aiaos-cli))
```

## Dependency Management

### Adding New Dependencies

When adding new dependencies:

1. Update this document
2. Add `(require '<package>)` to the appropriate file
3. Add to `Package-Requires` in the file header
4. Update the version requirements if necessary

### Checking Dependencies

```bash
# Check all dependencies are loaded
make check-deps

# List missing dependencies
make list-deps
```

## Troubleshooting

### Missing Dependency

If you encounter a "Cannot open load file" error:

1. Check if the package is installed
2. Verify the load path includes the package directory
3. Ensure the package is required in the correct file

### Version Conflicts

If you encounter version conflicts:

1. Update to the latest version of the dependency
2. Check compatibility with your Emacs version
3. Consult the dependency's documentation

## License

Dependencies retain their original licenses. See individual package documentation for details.