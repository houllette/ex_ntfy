#!/usr/bin/env bash
set -euo pipefail

# Template Cleanup Script
# Run this after cloning the template to remove template-specific content
# and start with a fresh project history

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo_info() { echo -e "${GREEN}[CLEANUP]${NC} $*"; }
echo_warn() { echo -e "${YELLOW}[CLEANUP]${NC} $*"; }
echo_error() { echo -e "${RED}[CLEANUP]${NC} $*"; }
echo_step() { echo -e "${BLUE}[STEP]${NC} $*"; }

# Confirm action
confirm_cleanup() {
  echo ""
  echo "================================================"
  echo "  Template Cleanup Script"
  echo "================================================"
  echo ""
  echo "This script will:"
  echo "  1. Reset CHANGELOG.md to a fresh state"
  echo "  2. Clean up template-specific documentation"
  echo "  3. Remove template history files"
  echo "  4. Optionally reset git history"
  echo ""
  echo_warn "This action cannot be undone!"
  echo ""
  read -rp "Continue? [y/N] " response

  if [[ ! "$response" =~ ^[Yy]$ ]]; then
    echo_info "Cleanup cancelled."
    exit 0
  fi
}

# Reset CHANGELOG
reset_changelog() {
  echo_step "Resetting CHANGELOG.md..."

  cat > "$PROJECT_ROOT/CHANGELOG.md" << 'EOF'
# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Initial SDK implementation

---

## How to Update This File

When making changes:

1. Add entries under `[Unreleased]`
2. Categorize changes:
   - `Added` for new features
   - `Changed` for changes in existing functionality
   - `Deprecated` for soon-to-be removed features
   - `Removed` for now removed features
   - `Fixed` for bug fixes
   - `Security` for vulnerability fixes
3. When releasing, move unreleased changes to a new version section
4. Update the date in ISO 8601 format (YYYY-MM-DD)

### Example Entry Format

```markdown
## [1.0.0] - 2024-03-15

### Added
- New feature X that does Y
- Support for Z

### Changed
- Updated behavior of A to B
- Modified C to improve performance

### Fixed
- Bug in D that caused E
- Issue with F

### Breaking Changes
- Renamed G to H
- Removed deprecated I
```
EOF

  echo_info "CHANGELOG.md reset to fresh state"
}

# Clean up template docs
cleanup_docs() {
  echo_step "Cleaning up template-specific documentation..."

  # Remove template-specific files
  local files_to_remove=(
    "QUICKSTART.md"
  )

  for file in "${files_to_remove[@]}"; do
    if [[ -f "$PROJECT_ROOT/$file" ]]; then
      rm "$PROJECT_ROOT/$file"
      echo_info "Removed $file"
    fi
  done
}

# Update README
update_readme() {
  echo_step "Updating README.md..."

  # Create a minimal README
  cat > "$PROJECT_ROOT/README.md" << 'EOF'
# SDK Name

<!-- Replace with your SDK description -->
Brief description of your SDK.

## Installation

Add `your_package_name` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:your_package_name, "~> 0.1.0"}
  ]
end
```

## Configuration

Configure the SDK in your `config/runtime.exs`:

```elixir
config :your_package_name,
  base_url: System.get_env("API_BASE_URL", "https://api.example.com")
```

## Usage

```elixir
# Create a connection
conn = YourSDK.Connection.new()

# Make API calls
{:ok, response} = YourSDK.Api.SomeApi.some_operation(conn, params)
```

## Documentation

- [API Documentation](https://hexdocs.pm/your_package_name)
- [Changelog](CHANGELOG.md)
- [Contributing Guidelines](CONTRIBUTING.md)

## Development

```bash
# Install dependencies
mix deps.get

# Run tests
mix test

# Run tests with coverage
mix coveralls

# Format code
mix format

# Run linter
mix credo

# Run type checker
mix dialyzer
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

See [LICENSE](LICENSE) for details.

---

**Generated with ❤️ using the Elixir SDK Generator Template**
EOF

  echo_info "README.md updated with minimal template"
}

# Update CONTRIBUTING
update_contributing() {
  echo_step "Updating CONTRIBUTING.md..."

  # Remove template-specific references
  sed -i.bak 's/Elixir SDK Generator Template/this project/g' "$PROJECT_ROOT/CONTRIBUTING.md"
  sed -i.bak 's/elixir-sdk-generator/your-repo-name/g' "$PROJECT_ROOT/CONTRIBUTING.md"
  rm -f "$PROJECT_ROOT/CONTRIBUTING.md.bak"

  echo_info "CONTRIBUTING.md updated"
}

# Clean up this script
remove_cleanup_script() {
  echo_step "Removing cleanup script..."

  read -rp "Remove this cleanup script? [y/N] " response
  if [[ "$response" =~ ^[Yy]$ ]]; then
    rm -f "$0"
    echo_info "Cleanup script removed"
  fi
}

# Git history reset (optional)
reset_git_history() {
  echo_step "Git history cleanup..."

  if [[ ! -d "$PROJECT_ROOT/.git" ]]; then
    echo_warn "Not a git repository, skipping git cleanup"
    return 0
  fi

  echo ""
  echo_warn "Do you want to reset git history and start fresh?"
  echo_warn "This will remove all template commit history."
  echo ""
  read -rp "Reset git history? [y/N] " response

  if [[ "$response" =~ ^[Yy]$ ]]; then
    cd "$PROJECT_ROOT"

    # Remove git history
    rm -rf .git

    # Initialize fresh repo
    git init
    git add .
    git commit -m "Initial commit from Elixir SDK Generator template"

    echo_info "Git history reset"
    echo_info "Run 'git remote add origin <url>' to add your remote"
  else
    echo_info "Keeping existing git history"
  fi
}

# Update file headers and comments
update_file_references() {
  echo_step "Updating file references..."

  # Update generator-config.yaml placeholder references
  if [[ -f "$PROJECT_ROOT/generator-config.yaml" ]]; then
    # Already has placeholders, no changes needed
    echo_info "generator-config.yaml already has placeholders"
  fi

  echo_info "File references updated"
}

# Summary
show_summary() {
  echo ""
  echo "================================================"
  echo "  Cleanup Complete!"
  echo "================================================"
  echo ""
  echo_info "Next steps:"
  echo ""
  echo "  1. Review and update README.md with your SDK details"
  echo "  2. Run ./scripts/setup.sh to configure your SDK"
  echo "  3. Add your OpenAPI specification"
  echo "  4. Run ./scripts/regenerate.sh to generate your SDK"
  echo "  5. Update CHANGELOG.md as you make changes"
  echo ""
  echo "Files cleaned up:"
  echo "  ✓ CHANGELOG.md (reset to fresh state)"
  echo "  ✓ README.md (minimal template)"
  echo "  ✓ CONTRIBUTING.md (generic references)"
  echo "  ✓ Template documentation removed"
  echo "  ✓ Git history (if you chose to reset)"
  echo ""
  echo_info "Your project is ready to customize!"
  echo ""
}

# Main execution
main() {
  confirm_cleanup

  echo ""
  reset_changelog
  cleanup_docs
  update_readme
  update_contributing
  update_file_references
  reset_git_history
  remove_cleanup_script
  show_summary
}

main "$@"
