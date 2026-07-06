# Contributing to Elixir SDK Generator

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
   - OpenAPI Generator version

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
7. **Run the linter** with `mix credo`
8. **Submit the PR** with a clear description

#### PR Requirements

- [ ] Tests pass (`mix test`)
- [ ] Code is formatted (`mix format --check-formatted`)
- [ ] Linter passes (`mix credo`)
- [ ] Documentation is updated
- [ ] CHANGELOG.md is updated (if applicable)
- [ ] Commit messages are clear and descriptive

## Development Setup

### Prerequisites

- Elixir 1.14 or later
- Erlang/OTP 25 or later
- OpenAPI Generator (install via Homebrew, npm, or Docker)
- Git

### Setup

```bash
# Clone the repository
git clone https://github.com/your-username/elixir-sdk-generator.git
cd elixir-sdk-generator

# Install dependencies
mix deps.get

# Run tests
mix test

# Format code
mix format

# Run linter
mix credo
```

### Testing

```bash
# Run all tests
mix test

# Run with coverage
mix coveralls

# Run specific test file
mix test test/unit/connection_test.exs

# Run in watch mode (requires mix_test_watch)
mix test.watch
```

### Code Style

- Follow the [Elixir Style Guide](https://github.com/christopheradams/elixir_style_guide)
- Use `mix format` before committing
- Keep lines under 120 characters
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

## Project Structure

```
elixir-sdk-generator/
├── .github/workflows/      # CI/CD workflows
├── .openapi-generator/     # Custom templates
│   └── templates/
├── config/                 # Configuration files (protected)
├── lib/                    # Generated SDK code (regenerated)
├── scripts/                # Automation scripts (protected)
├── test/                   # Tests (protected)
│   ├── unit/              # Unit tests
│   ├── integration/       # Integration tests
│   └── support/           # Test helpers
├── .formatter.exs         # Elixir formatter config
├── .gitignore
├── .openapi-generator-ignore  # Files to protect from regeneration
├── CHANGELOG.md
├── CONTRIBUTING.md
├── README.md
├── generator-config.yaml  # OpenAPI Generator config
└── mix.exs                # Generated (via template)
```

## Protected vs Generated Files

### Protected Files (Never Regenerated)

These files are listed in `.openapi-generator-ignore` and are safe to edit:

- All files in `config/`
- All files in `test/`
- All files in `scripts/`
- All files in `.github/`
- `CONTRIBUTING.md`, `CHANGELOG.md`
- `.formatter.exs`, `.tool-versions`
- `.openapi-generator-ignore`

### Generated Files (Regenerated from Spec)

These files are regenerated and should not be manually edited:

- Most files in `lib/`
- Generated README sections
- Mix dependencies (via template)

To modify generated files, update the templates in `.openapi-generator/templates/`.

## Adding Custom Templates

1. Create a new file in `.openapi-generator/templates/`
2. Use Mustache syntax for templating
3. Reference OpenAPI Generator documentation for available variables
4. Test generation with your template

Example:

```mustache
defmodule {{moduleName}}.CustomModule do
  @moduledoc """
  {{description}}
  """

  # Your custom code here
end
```

## Running Scripts

### Setup Script

```bash
./scripts/setup.sh
```

Initializes a new SDK project.

### Regenerate Script

```bash
./scripts/regenerate.sh
```

Regenerates SDK from OpenAPI spec.

### Validate Script

```bash
./scripts/validate-spec.sh
```

Validates OpenAPI specification.

### Publish Script

```bash
./scripts/publish.sh
```

Publishes to Hex.pm (requires authentication).

## Documentation

### Code Documentation

- Use `@moduledoc` for module documentation
- Use `@doc` for function documentation
- Include examples in documentation
- Add typespecs for public functions

Example:

```elixir
defmodule MyModule do
  @moduledoc """
  This module does something useful.

  ## Examples

      iex> MyModule.do_something()
      :ok
  """

  @doc """
  Does something useful.

  ## Parameters

    - `arg1` - First argument
    - `arg2` - Second argument

  ## Returns

  Returns `:ok` on success, `{:error, reason}` on failure.
  """
  @spec do_something(String.t(), integer()) :: :ok | {:error, any()}
  def do_something(arg1, arg2) do
    # Implementation
  end
end
```

### Updating README

When adding features, update:

1. Feature list
2. Usage examples
3. Configuration options
4. Relevant sections

## Testing Guidelines

### Unit Tests

- Test individual functions in isolation
- Mock external dependencies
- Use descriptive test names
- One assertion per test when possible

```elixir
defmodule ConnectionTest do
  use TestCase

  describe "new/1" do
    test "creates client with default config" do
      client = Connection.new()
      assert %Tesla.Client{} = client
    end

    test "creates client with custom timeout" do
      client = Connection.new(timeout: 60_000)
      assert %Tesla.Client{} = client
    end
  end
end
```

### Integration Tests

- Test full request/response cycles
- Use Bypass for mock HTTP servers
- Test error scenarios
- Test retry logic

```elixir
defmodule ApiIntegrationTest do
  use TestCase

  setup do
    bypass = MockServer.setup()
    {:ok, bypass: bypass}
  end

  test "handles successful request", %{bypass: bypass} do
    MockServer.expect_get(bypass, "/users/1", 200, %{id: 1})
    conn = Connection.new(base_url: MockServer.url(bypass))
    assert {:ok, response} = Api.get_user(conn, 1)
  end
end
```

## Release Process

1. **Update version** in `mix.exs`
2. **Update CHANGELOG.md** with changes
3. **Run tests**: `mix test`
4. **Run quality checks**: `mix format && mix credo`
5. **Commit changes**: `git commit -m "Bump version to X.Y.Z"`
6. **Create tag**: `git tag vX.Y.Z`
7. **Push**: `git push origin main --tags`
8. **GitHub Actions** will automatically publish to Hex.pm

## Questions?

- Open an issue for questions
- Check existing issues and discussions
- Review the documentation

## License

By contributing, you agree that your contributions will be licensed under the MIT License.

---

Thank you for contributing! 🎉
