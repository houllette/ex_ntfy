# Quick Start Guide

Get your SDK up and running in minutes!

## Prerequisites

- Elixir and Erlang/OTP
- OpenAPI Generator installed via preferred method
- Git

## Step 1: Clone or Use Template

### Option A: Use GitHub Template

1. Click "Use this template" on GitHub
2. Name your new repository
3. Clone your new repository

### Option B: Clone Directly

```bash
git clone https://github.com/your-username/elixir-sdk-generator.git my-sdk
cd my-sdk
```

## Step 2: Clean Up Template (Optional but Recommended)

Remove template-specific content to start fresh:

```bash
chmod +x scripts/*.sh  # Make scripts executable (if needed)
./scripts/cleanup-template.sh
```

This will:
- Reset CHANGELOG.md to a fresh state
- Create a minimal README for your SDK
- Remove template documentation files
- Optionally reset git history to start clean

**Tip:** Run this immediately after cloning to avoid confusion with template history!

## Step 3: Run Setup

```bash
./scripts/setup.sh
```

You'll be prompted for:
- **Package name**: `my_api_client` (lowercase, underscores)
- **Module name**: `MyApiClient` (PascalCase)
- **Description**: Brief description of your SDK
- **Author info**: Your name and email
- **GitHub info**: Username and repo name
- **Base URL**: API base URL (optional)
- **OpenAPI spec**: Path or URL to your OpenAPI specification

## Step 4: Generate SDK

```bash
./scripts/regenerate.sh
```

This will:
✅ Validate your OpenAPI spec
✅ Generate Elixir SDK code
✅ Set up connection pooling
✅ Add retry logic
✅ Format code
✅ Install dependencies
✅ Run tests

## Step 5: Review Generated Code

```bash
# View generated structure
tree lib/

# Run tests
mix test

# Check code quality
mix format
mix credo
```

## Step 6: Add Custom Tests

Create tests for your API endpoints

## Step 7: Configure GitHub Actions

### Required Secrets

Add these secrets in GitHub Settings → Secrets:

1. **HEX_API_KEY**: Get from `mix hex.user auth`

### Enable Workflows

Your repository now has these workflows:

- ✅ **test.yml**: Runs on every push
- ✅ **regenerate-sdk.yml**: Auto-regenerates on spec changes
- ✅ **publish.yml**: Publishes to Hex.pm on version tags
- ✅ **breaking-changes.yml**: Detects breaking changes in PRs

## Step 8: Make Your First Release

```bash
# 1. Update version in mix.exs
# @version "1.0.0"

# 2. Update CHANGELOG.md
vim CHANGELOG.md

# 3. Commit and tag
git add .
git commit -m "Release v1.0.0"
git tag v1.0.0

# 4. Push (this triggers automatic publishing)
git push origin main --tags
```

## Common Tasks

### Update API from New Spec

```bash
# Replace openapi-spec.yaml with new version
cp /path/to/new/spec.yaml openapi-spec.yaml

# Regenerate
./scripts/regenerate.sh

# Review changes
git diff

# Commit
git add .
git commit -m "Update API from spec v2.0"
git push
```

### Add Integration Tests

```elixir
# test/integration/user_workflow_test.exs
defmodule UserWorkflowTest do
  use TestCase

  setup do
    bypass = MockServer.setup()
    conn = Connection.new(base_url: MockServer.url(bypass))
    {:ok, bypass: bypass, conn: conn}
  end

  test "complete user workflow", %{bypass: bypass, conn: conn} do
    # Create user
    MockServer.expect_post(bypass, "/users", 201, %{id: 1})
    {:ok, response} = Users.create_user(conn, %{name: "Test"})

    # Get user
    MockServer.expect_get(bypass, "/users/1", 200, %{id: 1})
    {:ok, response} = Users.get_user(conn, 1)

    # Update user
    MockServer.expect_put(bypass, "/users/1", 200, %{id: 1})
    {:ok, response} = Users.update_user(conn, 1, %{name: "Updated"})
  end
end
```

### Configure Runtime Settings

```elixir
# config/runtime.exs
config :my_api_client,
  base_url: System.get_env("API_BASE_URL", "https://api.example.com"),
  pool_size: String.to_integer(System.get_env("HTTP_POOL_SIZE", "25")),
  api_key: System.get_env("API_KEY")
```

### Customize Generated Code

Edit templates in `.openapi-generator/templates/`:

- `connection.ex.mustache` - Connection logic
- `mix.exs.mustache` - Dependencies and configuration
- `application.ex.mustache` - Application supervisor
- `README.md.mustache` - Generated README

After editing templates, run `./scripts/regenerate.sh`.

## Troubleshooting

### OpenAPI Generator Not Found

```bash
# Install via Homebrew (macOS/Linux) - Recommended
brew install openapi-generator

# Or via npm
npm install -g @openapitools/openapi-generator-cli

# Or use Docker
docker pull openapitools/openapi-generator-cli
```

### Tests Failing After Regeneration

1. Check if API changed (breaking changes)
2. Update test expectations
3. Add tests for new endpoints

### Coverage Below Threshold

```bash
# Generate coverage report
mix coveralls.html

# Open coverage report
open cover/excoveralls.html

# Add tests for uncovered code
```

### Format Errors

```bash
# Auto-fix formatting
mix format

# Check what would change
mix format --check-formatted
```

## Next Steps

1. ⭐ Star the repository on GitHub
2. 📖 Read the full [README.md](README.md)
3. 🤝 Review [CONTRIBUTING.md](CONTRIBUTING.md)
4. 📝 Check [CHANGELOG.md](CHANGELOG.md)
5. 🚀 Deploy your SDK to production!

## Resources

- [OpenAPI Specification](https://swagger.io/specification/)
- [OpenAPI Generator Docs](https://openapi-generator.tech/docs/generators/elixir)
- [Elixir Tesla](https://github.com/elixir-tesla/tesla)
- [Finch HTTP Client](https://github.com/sneako/finch)
- [Hex.pm Publishing Guide](https://hex.pm/docs/publish)

## Support

- 🐛 [Report a bug](../../issues/new?template=bug_report.md)
- 💡 [Request a feature](../../issues/new?template=feature_request.md)
- 📚 [View documentation](README.md)
- 💬 [Join discussions](../../discussions)

---

Happy coding! 🎉
