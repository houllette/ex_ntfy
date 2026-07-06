# Elixir SDK Generator Template

A production-ready GitHub template for generating Elixir SDKs from OpenAPI specifications using [openapi-generator](https://openapi-generator.tech/).

## Features

✨ **Automated Generation**: One-command SDK generation with zero manual intervention
🔄 **Auto-Regeneration**: GitHub Actions automatically regenerate SDK when specs change
🏊 **Connection Pooling**: Built-in Finch connection pooling for optimal performance
♻️ **Retry Logic**: Automatic retries with exponential backoff for transient failures
📊 **Telemetry**: Integrated telemetry for monitoring and observability
🧪 **Test Infrastructure**: Comprehensive test helpers that survive regeneration
📈 **Code Coverage**: Automatic coverage tracking with threshold enforcement
🔍 **Breaking Changes**: Automatic detection of API breaking changes
📦 **Hex.pm Ready**: Pre-configured publishing workflow

## Quick Start

> **Prerequisites**: Elixir 1.18+, Erlang/OTP 26+, and OpenAPI Generator
> Install OpenAPI Generator via: `brew install openapi-generator` (macOS/Linux) or `npm install -g @openapitools/openapi-generator-cli`

### 1. Use This Template

Click the "Use this template" button on GitHub to create your own repository.

### 2. Run Setup

```bash
./scripts/setup.sh
```

This interactive script will prompt you for:
- Package name (e.g., `my_api_client`)
- Module name (e.g., `MyApiClient`)
- Author information
- GitHub repository details
- OpenAPI specification location

### 3. Generate SDK

```bash
./scripts/regenerate.sh
```

This will:
- Validate your OpenAPI spec
- Generate the SDK code
- Run post-processing
- Format the code
- Install dependencies
- Run tests

### 4. Review and Test

```bash
mix test
mix credo
mix dialyzer
```

## Project Structure

```
elixir-sdk-generator/
├── .github/workflows/      # CI/CD pipelines
│   ├── test.yml           # Test on every push
│   ├── regenerate-sdk.yml # Auto-regenerate SDK
│   ├── publish.yml        # Publish to Hex.pm
│   └── breaking-changes.yml # Detect breaking changes
├── .openapi-generator/
│   └── templates/         # Custom Mustache templates
├── config/                # Elixir configuration
├── lib/                   # Generated SDK code (disposable)
├── scripts/               # Automation scripts
├── test/                  # Tests (persistent, never regenerated)
│   ├── unit/
│   ├── integration/
│   └── support/
├── generator-config.yaml  # OpenAPI Generator config
└── openapi-spec.yaml     # Your OpenAPI specification
```

## Usage

### Basic Example

```elixir
# Create a connection
conn = MySDK.Connection.new()

# Make API calls
{:ok, response} = MySDK.Api.Users.get_user(conn, user_id)
```

### Custom Configuration

```elixir
# Custom base URL
conn = MySDK.Connection.new(base_url: "https://api.example.com")

# Custom timeout
conn = MySDK.Connection.new(timeout: 60_000)

# Custom retry configuration
conn = MySDK.Connection.new(
  retry: [
    max_retries: 5,
    delay: 200,
    max_delay: 10_000
  ]
)
```

### Runtime Configuration

```elixir
# config/runtime.exs
config :my_sdk,
  base_url: System.get_env("API_BASE_URL", "https://api.example.com"),
  pool_size: String.to_integer(System.get_env("HTTP_POOL_SIZE", "25"))
```

## Development Workflow

### 1. Update OpenAPI Spec

Edit `openapi-spec.yaml` with your API changes.

### 2. Regenerate SDK

```bash
./scripts/regenerate.sh
```

### 3. Add Tests

Add tests for new endpoints in `test/unit/` or `test/integration/`:

```elixir
defmodule MySDK.Api.UsersTest do
  use TestCase

  test "creates a user" do
    conn = Connection.new(base_url: MockServer.url(bypass))
    assert {:ok, response} = Users.create_user(conn, %{name: "Test"})
  end
end
```

### 4. Commit Changes

```bash
git add .
git commit -m "Add user creation endpoint"
git push
```

## GitHub Actions Workflows

### Continuous Integration (test.yml)

Runs on every push and PR:
- Tests across multiple Elixir/OTP versions
- Code formatting checks
- Credo linting
- Dialyzer type checking
- Code coverage with threshold enforcement

### Auto-Regeneration (regenerate-sdk.yml)

Automatically triggered when:
- `openapi-spec.yaml` changes
- Manual workflow dispatch
- Weekly schedule (configurable)

Creates a PR with regenerated SDK code.

### Publishing (publish.yml)

Triggered on version tags (`v*.*.*`):
- Runs all tests
- Publishes to Hex.pm
- Creates GitHub release

```bash
# Bump version in mix.exs, then:
git tag v1.0.0
git push origin v1.0.0
```

### Breaking Changes Detection (breaking-changes.yml)

Runs on PRs that modify:
- OpenAPI spec
- API modules

Detects and reports:
- Breaking changes in API spec
- Removed functions
- Modified signatures

## Advanced Features

### Custom Templates

Modify templates in `.openapi-generator/templates/` to customize generated code:

- `connection.ex.mustache` - HTTP client configuration
- `mix.exs.mustache` - Mix project file
- `application.ex.mustache` - Application supervisor
- `README.md.mustache` - Generated README

### Protected Files

Files listed in `.openapi-generator-ignore` are never overwritten:

- All configuration files
- All tests
- All scripts
- Custom documentation

### Post-Generation Processing

Edit `scripts/post-generate.sh` to add custom post-processing:

- Code transformations
- Additional file generation
- Custom validation

## Testing

### Run All Tests

```bash
mix test
```

### Run with Coverage

```bash
mix coveralls
mix coveralls.html  # Generate HTML report
```

### Run Integration Tests Only

```bash
mix test test/integration/
```

### Run Specific Test

```bash
mix test test/unit/connection_test.exs
```

## Code Quality

### Format Code

```bash
mix format
```

### Run Linter

```bash
mix credo --strict
```

### Run Type Checker

```bash
mix dialyzer
```

## Publishing

### Manual Publishing

```bash
./scripts/publish.sh
```

This script will:
- Run all tests
- Check code formatting
- Verify version
- Build documentation
- Publish to Hex.pm
- Create git tag

### Automatic Publishing

Push a version tag to trigger automatic publishing:

```bash
# Update version in mix.exs
git add mix.exs
git commit -m "Bump version to 1.0.0"
git tag v1.0.0
git push origin main --tags
```

## Configuration

### Generator Config

Edit `generator-config.yaml` to customize SDK generation:

```yaml
additionalProperties:
  packageName: "my_api_client"
  moduleName: "MyApiClient"
  packageVersion: "1.0.0"
```

### GitHub Secrets

Required secrets for workflows:

- `HEX_API_KEY` - For publishing to Hex.pm (get from `mix hex.user auth`)

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for development guidelines.

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for version history.

## Resources

- [OpenAPI Generator](https://openapi-generator.tech/)
- [Elixir Tesla](https://github.com/elixir-tesla/tesla)
- [Finch](https://github.com/sneako/finch)
- [Hex.pm](https://hex.pm/)

## Support

- Open an issue on GitHub
- Check existing issues for solutions
- Review the documentation

---

**Generated with ❤️ using the Elixir SDK Generator Template**
