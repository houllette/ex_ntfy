#!/usr/bin/env bash
set -euo pipefail

# Elixir SDK Generator - Regeneration Script
# Regenerates the SDK from the OpenAPI specification

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
GENERATOR_CONFIG="$PROJECT_ROOT/generator-config.yaml"
OPENAPI_SPEC="$PROJECT_ROOT/openapi-spec.yaml"
GENERATOR_JAR="${OPENAPI_GENERATOR_JAR:-}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo_info() { echo -e "${GREEN}[INFO]${NC} $*"; }
echo_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
echo_error() { echo -e "${RED}[ERROR]${NC} $*"; }
echo_step() { echo -e "${BLUE}[STEP]${NC} $*"; }

# Check if OpenAPI Generator is available
check_generator() {
  echo_info "Checking for OpenAPI Generator..."

  # Try homebrew openapi-generator (macOS/Linux)
  if command -v openapi-generator &> /dev/null; then
    GENERATOR_CMD="openapi-generator"
    echo_info "Using OpenAPI Generator via Homebrew"
    return 0
  fi

  # Try npx (most common)
  if command -v npx &> /dev/null; then
    GENERATOR_CMD="npx @openapitools/openapi-generator-cli"
    echo_info "Using OpenAPI Generator via npx"
    return 0
  fi

  # Try docker
  if command -v docker &> /dev/null; then
    GENERATOR_CMD="docker run --rm -v \"${PROJECT_ROOT}:/local\" openapitools/openapi-generator-cli"
    echo_info "Using OpenAPI Generator via Docker"
    return 0
  fi

  # Try JAR file
  if [[ -n "$GENERATOR_JAR" ]] && [[ -f "$GENERATOR_JAR" ]]; then
    GENERATOR_CMD="java -jar \"$GENERATOR_JAR\""
    echo_info "Using OpenAPI Generator JAR at $GENERATOR_JAR"
    return 0
  fi

  echo_error "OpenAPI Generator not found!"
  echo_error "Please install it via one of these methods:"
  echo_error "  1. homebrew (macOS/Linux): brew install openapi-generator"
  echo_error "  2. npm: npm install -g @openapitools/openapi-generator-cli"
  echo_error "  3. docker: docker pull openapitools/openapi-generator-cli"
  echo_error "  4. JAR: Set OPENAPI_GENERATOR_JAR environment variable"
  exit 1
}

# Validate OpenAPI spec
validate_spec() {
  echo_step "Validating OpenAPI specification..."

  if [[ ! -f "$OPENAPI_SPEC" ]]; then
    echo_error "OpenAPI spec not found: $OPENAPI_SPEC"
    exit 1
  fi

  # Run validation script if it exists
  if [[ -x "$SCRIPT_DIR/validate-spec.sh" ]]; then
    "$SCRIPT_DIR/validate-spec.sh"
  else
    echo_warn "Validation script not found, skipping validation."
  fi
}

# Backup current generated files
backup_generated() {
  echo_step "Creating backup of generated files..."

  local backup_dir="$PROJECT_ROOT/.backup/$(date +%Y%m%d_%H%M%S)"
  mkdir -p "$backup_dir"

  if [[ -d "$PROJECT_ROOT/lib" ]]; then
    cp -r "$PROJECT_ROOT/lib" "$backup_dir/"
    echo_info "Backed up lib/ to $backup_dir"
  fi

  echo "$backup_dir" > "$PROJECT_ROOT/.last_backup"
}

# Generate SDK
generate_sdk() {
  echo_step "Generating SDK from OpenAPI specification..."

  cd "$PROJECT_ROOT"

  # Run OpenAPI Generator
  if [[ "$GENERATOR_CMD" == *"docker"* ]]; then
    # Docker command (paths are already mounted to /local)
    docker run --rm \
      -v "${PROJECT_ROOT}:/local" \
      openapitools/openapi-generator-cli generate \
      -i /local/openapi-spec.yaml \
      -g elixir \
      -o /local \
      -c /local/generator-config.yaml \
      -t /local/.openapi-generator/templates
  else
    # Homebrew, NPX, or JAR command
    eval "$GENERATOR_CMD generate \
      -i \"$OPENAPI_SPEC\" \
      -g elixir \
      -o \"$PROJECT_ROOT\" \
      -c \"$GENERATOR_CONFIG\" \
      -t \"$PROJECT_ROOT/.openapi-generator/templates\""
  fi

  echo_info "SDK generation complete."
}

# Run post-generation processing
post_generate() {
  echo_step "Running post-generation processing..."

  if [[ -x "$SCRIPT_DIR/post-generate.sh" ]]; then
    "$SCRIPT_DIR/post-generate.sh"
  else
    echo_warn "Post-generation script not found, skipping."
  fi
}

# Format generated code
format_code() {
  echo_step "Formatting generated code..."

  if command -v mix &> /dev/null; then
    cd "$PROJECT_ROOT"
    mix format || echo_warn "Failed to format code (this is non-fatal)"
  else
    echo_warn "mix not found, skipping code formatting."
  fi
}

# Install dependencies
install_deps() {
  echo_step "Installing dependencies..."

  if command -v mix &> /dev/null; then
    cd "$PROJECT_ROOT"
    mix deps.get || echo_warn "Failed to get dependencies (this is non-fatal)"
  else
    echo_warn "mix not found, skipping dependency installation."
  fi
}

# Run tests
run_tests() {
  if [[ "${SKIP_TESTS:-0}" == "1" ]]; then
    echo_info "Skipping tests (SKIP_TESTS=1)"
    return 0
  fi

  echo_step "Running tests..."

  if command -v mix &> /dev/null; then
    cd "$PROJECT_ROOT"
    if mix test --color 2>&1; then
      echo_info "All tests passed!"
    else
      echo_warn "Some tests failed. Review the output above."
    fi
  else
    echo_warn "mix not found, skipping tests."
  fi
}

# Check for breaking changes
check_breaking_changes() {
  echo_step "Checking for breaking changes..."

  local backup_file="$PROJECT_ROOT/.last_backup"
  if [[ ! -f "$backup_file" ]]; then
    echo_info "No previous backup found, skipping breaking change detection."
    return 0
  fi

  local last_backup
  last_backup=$(cat "$backup_file")

  if [[ ! -d "$last_backup" ]]; then
    echo_warn "Last backup directory not found: $last_backup"
    return 0
  fi

  # Compare public API surfaces
  echo_info "Comparing with backup from $last_backup"

  # Simple file count comparison
  local old_count new_count
  old_count=$(find "$last_backup/lib" -name "*.ex" 2>/dev/null | wc -l)
  new_count=$(find "$PROJECT_ROOT/lib" -name "*.ex" 2>/dev/null | wc -l)

  if [[ $new_count -ne $old_count ]]; then
    echo_warn "Number of generated files changed: $old_count -> $new_count"
    echo_warn "This may indicate API changes. Please review carefully."
  fi
}

# Main execution
main() {
  echo ""
  echo "================================================"
  echo "  Elixir SDK Generator - Regeneration"
  echo "================================================"
  echo ""

  check_generator
  validate_spec
  backup_generated
  generate_sdk
  post_generate
  format_code
  install_deps
  check_breaking_changes
  run_tests

  echo ""
  echo_info "SDK regeneration complete!"
  echo ""
  echo "Next steps:"
  echo "  1. Review changes: git diff"
  echo "  2. Run tests: mix test"
  echo "  3. Update CHANGELOG.md if needed"
  echo "  4. Commit changes: git add . && git commit -m 'Regenerate SDK'"
  echo ""
}

main "$@"
