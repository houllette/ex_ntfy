#!/usr/bin/env bash
set -euo pipefail

# Hex.pm Publishing Script

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo_info() { echo -e "${GREEN}[PUBLISH]${NC} $*"; }
echo_warn() { echo -e "${YELLOW}[PUBLISH]${NC} $*"; }
echo_error() { echo -e "${RED}[PUBLISH]${NC} $*"; }
echo_step() { echo -e "${BLUE}[STEP]${NC} $*"; }

# Check prerequisites
check_prerequisites() {
  echo_step "Checking prerequisites..."

  if ! command -v mix &> /dev/null; then
    echo_error "mix not found. Please install Elixir."
    exit 1
  fi

  # Check if hex is authenticated
  if ! mix hex.info &> /dev/null; then
    echo_error "Not authenticated with Hex. Run: mix hex.user auth"
    exit 1
  fi

  echo_info "Prerequisites satisfied."
}

# Check git status
check_git_status() {
  echo_step "Checking git status..."

  if [[ ! -d "$PROJECT_ROOT/.git" ]]; then
    echo_warn "Not a git repository. Skipping git checks."
    return 0
  fi

  # Check for uncommitted changes
  if ! git diff-index --quiet HEAD -- 2>/dev/null; then
    echo_error "Uncommitted changes detected. Please commit or stash them first."
    exit 1
  fi

  # Check if on main/master branch
  local branch
  branch=$(git rev-parse --abbrev-ref HEAD)

  if [[ "$branch" != "main" ]] && [[ "$branch" != "master" ]]; then
    echo_warn "Not on main/master branch (current: $branch)"
    read -rp "Continue anyway? [y/N] " response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
      echo_info "Aborted."
      exit 0
    fi
  fi

  echo_info "Git status is clean."
}

# Run tests
run_tests() {
  echo_step "Running tests..."

  cd "$PROJECT_ROOT"

  if ! mix test; then
    echo_error "Tests failed. Fix them before publishing."
    exit 1
  fi

  echo_info "All tests passed."
}

# Run code quality checks
run_quality_checks() {
  echo_step "Running code quality checks..."

  cd "$PROJECT_ROOT"

  # Format check
  if ! mix format --check-formatted; then
    echo_error "Code is not formatted. Run: mix format"
    exit 1
  fi

  # Credo (if available)
  if mix help credo &> /dev/null; then
    if ! mix credo --strict; then
      echo_warn "Credo found issues (continuing anyway)"
    fi
  fi

  # Dialyzer (if available and fast)
  if mix help dialyzer &> /dev/null; then
    echo_info "Skipping dialyzer (run manually if needed: mix dialyzer)"
  fi

  echo_info "Quality checks passed."
}

# Check version
check_version() {
  echo_step "Checking version..."

  cd "$PROJECT_ROOT"

  local version
  version=$(grep '@version' mix.exs | sed -E 's/.*"(.+)".*/\1/')

  echo_info "Current version: $version"

  # Check if this version is already published
  if mix hex.info "$(grep 'app:' mix.exs | sed -E 's/.*:([^,]+).*/\1/')" | grep -q "$version"; then
    echo_error "Version $version is already published!"
    echo_error "Please bump the version in mix.exs"
    exit 1
  fi

  # Check if CHANGELOG.md mentions this version
  if [[ -f "$PROJECT_ROOT/CHANGELOG.md" ]]; then
    if ! grep -q "$version" "$PROJECT_ROOT/CHANGELOG.md"; then
      echo_warn "Version $version not found in CHANGELOG.md"
      read -rp "Continue anyway? [y/N] " response
      if [[ ! "$response" =~ ^[Yy]$ ]]; then
        echo_info "Aborted. Please update CHANGELOG.md"
        exit 0
      fi
    fi
  fi

  echo_info "Version check passed."
}

# Build docs
build_docs() {
  echo_step "Building documentation..."

  cd "$PROJECT_ROOT"

  if ! mix docs; then
    echo_warn "Failed to build docs (continuing anyway)"
  else
    echo_info "Documentation built successfully."
  fi
}

# Publish to Hex
publish_hex() {
  echo_step "Publishing to Hex.pm..."

  cd "$PROJECT_ROOT"

  echo ""
  echo_warn "You are about to publish to Hex.pm!"
  echo_warn "This action cannot be undone."
  echo ""
  read -rp "Are you sure? [y/N] " response

  if [[ ! "$response" =~ ^[Yy]$ ]]; then
    echo_info "Aborted."
    exit 0
  fi

  # Publish (--yes to skip the second confirmation)
  if mix hex.publish --yes; then
    echo_info "Successfully published to Hex.pm!"
  else
    echo_error "Publishing failed."
    exit 1
  fi
}

# Create git tag
create_git_tag() {
  if [[ ! -d "$PROJECT_ROOT/.git" ]]; then
    return 0
  fi

  echo_step "Creating git tag..."

  cd "$PROJECT_ROOT"

  local version
  version=$(grep '@version' mix.exs | sed -E 's/.*"(.+)".*/\1/')
  local tag="v$version"

  if git rev-parse "$tag" >/dev/null 2>&1; then
    echo_warn "Tag $tag already exists."
    return 0
  fi

  git tag -a "$tag" -m "Release $version"

  echo_info "Created tag: $tag"
  echo_info "Push it with: git push origin $tag"
}

# Main execution
main() {
  echo ""
  echo "================================================"
  echo "  Hex.pm Publishing"
  echo "================================================"
  echo ""

  check_prerequisites
  check_git_status
  run_tests
  run_quality_checks
  check_version
  build_docs
  publish_hex
  create_git_tag

  echo ""
  echo_info "✓ Publishing complete!"
  echo ""
  echo "Next steps:"
  echo "  1. Push the git tag: git push origin --tags"
  echo "  2. Create a GitHub release"
  echo "  3. Announce the release"
  echo ""
}

main "$@"
