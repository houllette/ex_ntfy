# Contributing to ExNtfy

Thank you for considering contributing to this project! This document provides guidelines for contributing.

## Code of Conduct

Be respectful and constructive in all interactions.

## How to Contribute

### Reporting Bugs

When reporting bugs, please include:

1. **Description**: Clear description of the issue
2. **Steps to Reproduce**: Detailed steps to reproduce the behavior
3. **Expected Behavior**: What you expected to happen
4. **Actual Behavior**: What actually happened
5. **Environment**:
   - Elixir version (`elixir --version`)
   - Erlang/OTP version
   - Operating system

### Suggesting Features

Feature suggestions are welcome! Please:

1. Check if the feature already exists or is planned
2. Clearly describe the feature and its use case
3. Explain why it would be useful
4. Consider providing implementation ideas

### Pull Requests

#### Before Submitting

1. **Check existing PRs**: Make sure a similar PR doesn't already exist
2. **Open an issue**: For significant changes, open an issue first to discuss
3. **Follow conventions**: Match the existing code style and patterns

#### PR Process

1. **Fork the repository** and create your branch from `main`
2. **Make your changes** with clear, atomic commits
3. **Add tests** for any new functionality
4. **Update documentation** including README, CHANGELOG, and code comments
5. **Run the test suite** and ensure all tests pass
6. **Format your code** with `mix format`
7. **Run the linter** with `mix credo --strict`
8. **Submit the PR** with a clear description

#### PR Requirements

- [ ] Tests pass (`mix test`)
- [ ] Code is formatted (`mix format --check-formatted`)
- [ ] Linter passes (`mix credo --strict`)
- [ ] Dialyzer passes (`mix dialyzer`)
- [ ] Documentation is updated
- [ ] CHANGELOG.md is updated (if applicable)
- [ ] Commit messages are clear and descriptive

## Development Setup

### Prerequisites

- Elixir 1.15 or later
- Erlang/OTP 26 or later
- Git

### Setup

```bash
# Clone the repository
git clone https://github.com/houllette/ex_ntfy.git
cd ex_ntfy

# Install dependencies
mix deps.get

# Run tests
mix test

# Format code
mix format

# Run linter
mix credo --strict
```

### Testing

```bash
# Run all tests
mix test

# Run with coverage
mix coveralls

# Run specific test file
mix test test/ex_ntfy_test.exs
```

### Code Style

- Follow the [Elixir Style Guide](https://github.com/christopheradams/elixir_style_guide)
- Use `mix format` before committing
- Write descriptive function names and module documentation
- Add typespecs for public functions

### Commit Messages

Write clear, concise commit messages:

```
Short summary (50 chars or less)

More detailed explanation if needed. Wrap at 72 characters.
Explain the problem this commit solves and why you chose
this solution.

Resolves: #123
See also: #456, #789
```

**Commit Message Format:**

- `feat:` - New feature
- `fix:` - Bug fix
- `docs:` - Documentation changes
- `style:` - Code style changes (formatting, etc.)
- `refactor:` - Code refactoring
- `test:` - Adding or updating tests
- `chore:` - Maintenance tasks

### Branch Naming

Use descriptive branch names:

- `feat/add-retry-logic`
- `fix/connection-timeout`
- `docs/update-readme`
- `refactor/simplify-config`

## Documentation

- Use `@moduledoc` for module documentation
- Use `@doc` for function documentation
- Include examples in documentation
- Add typespecs for public functions

## Questions?

- Open an issue for questions
- Check existing issues and discussions
- Review the documentation

## License

By contributing, you agree that your contributions will be licensed under the MIT License.

---

Thank you for contributing! 🎉
