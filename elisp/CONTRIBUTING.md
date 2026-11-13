# Contributing to AIAOS-CLI

Thank you for your interest in contributing to AIAOS-CLI! This document outlines the process for contributing.

## Getting Started

1. **Fork the repository** on GitHub
2. **Clone your fork**:
   ```bash
   git clone https://github.com/your-username/aiaos-cli.git
   cd aiaos-cli
   ```
3. **Set up the remote**:
   ```bash
   git remote upstream https://github.com/xBSDChina/aiaos-cli.git
   ```
4. **Install dependencies**:
   ```bash
   make deps
   ```

## Development Workflow

1. **Create a feature branch**:
   ```bash
   git checkout -b feature/my-feature
   ```

2. **Make your changes**:
   - Follow the existing code style
   - Add documentation for new features
   - Add tests for new functionality

3. **Run tests**:
   ```bash
   make test
   ```

4. **Commit your changes**:
   ```bash
   git add .
   git commit -m "Add my feature"
   ```

5. **Push to your fork**:
   ```bash
   git push origin feature/my-feature
   ```

6. **Create a Pull Request**

## Code Style

- Use **2-space indentation**
- Use **CamelCase** for functions and variables
- Use **kebab-case** for file names
- Add **docstrings** to all public functions
- Use **lexical binding** (`lexical-binding: t`)

## Testing

- Write tests for all new features
- Ensure all tests pass before submitting
- Use the existing test framework

## Reporting Issues

- Use the issue tracker
- Provide reproduction steps
- Include version information

## License

By contributing, you agree that your contributions will be licensed under the MIT License.