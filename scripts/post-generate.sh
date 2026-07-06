#!/usr/bin/env bash
set -euo pipefail

# Post-generation processing script
# Runs after OpenAPI Generator completes

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo_info() { echo -e "${GREEN}[POST-GEN]${NC} $*"; }
echo_warn() { echo -e "${YELLOW}[POST-GEN]${NC} $*"; }

# Fix common issues in generated code
fix_generated_code() {
  echo_info "Fixing common issues in generated code..."

  # Remove any accidentally generated files in protected directories
  if [[ -d "$PROJECT_ROOT/test" ]]; then
    # Remove auto-generated test files that might conflict with our custom tests
    find "$PROJECT_ROOT/test" -name "*_test.exs" -type f -exec grep -l "AUTO-GENERATED" {} \; | while read -r file; do
      echo_warn "Removing auto-generated test file: $file"
      rm -f "$file"
    done
  fi

  echo_info "Code fixes applied."
}

# Update .openapi-generator/VERSION file
update_version_file() {
  local version_file="$PROJECT_ROOT/.openapi-generator/VERSION"
  local version_dir
  version_dir=$(dirname "$version_file")

  mkdir -p "$version_dir"

  # Record the generator version and timestamp
  {
    echo "Generated at: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    echo "OpenAPI Generator version: $(npx @openapitools/openapi-generator-cli version 2>/dev/null || echo 'unknown')"
    echo "Spec file: openapi-spec.yaml"
  } > "$version_file"

  echo_info "Updated version file."
}

# Ensure test directories exist
ensure_test_structure() {
  echo_info "Ensuring test directory structure..."

  mkdir -p "$PROJECT_ROOT/test/unit"
  mkdir -p "$PROJECT_ROOT/test/integration"
  mkdir -p "$PROJECT_ROOT/test/support"

  # Create .gitkeep files if directories are empty
  for dir in unit integration support; do
    if [[ -z "$(ls -A "$PROJECT_ROOT/test/$dir" 2>/dev/null)" ]]; then
      touch "$PROJECT_ROOT/test/$dir/.gitkeep"
    fi
  done

  echo_info "Test structure verified."
}

# Check for API changes that need new tests
check_test_coverage() {
  echo_info "Analyzing API coverage..."

  local lib_dir="$PROJECT_ROOT/lib"
  local test_dir="$PROJECT_ROOT/test"

  if [[ ! -d "$lib_dir" ]]; then
    echo_warn "lib/ directory not found, skipping coverage check."
    return 0
  fi

  # Count API modules
  local api_count
  api_count=$(find "$lib_dir" -name "*_api.ex" -o -name "*api.ex" | wc -l)

  echo_info "Found $api_count API modules"

  if [[ $api_count -gt 0 ]]; then
    echo_warn "Remember to add tests for new API endpoints!"
    echo_warn "Run 'mix test --cover' to check test coverage."
  fi
}

# Generate a simple test template for new APIs
generate_test_templates() {
  echo_info "Checking for new API modules without tests..."

  local lib_dir="$PROJECT_ROOT/lib"
  local test_unit_dir="$PROJECT_ROOT/test/unit"

  if [[ ! -d "$lib_dir" ]]; then
    return 0
  fi

  # Find API files
  find "$lib_dir" -type f -name "*_api.ex" | while read -r api_file; do
    local basename
    basename=$(basename "$api_file" .ex)
    local test_file="$test_unit_dir/${basename}_test.exs"

    # Skip if test already exists
    if [[ -f "$test_file" ]]; then
      continue
    fi

    # Extract module name from file
    local module_name
    module_name=$(grep -m1 "defmodule" "$api_file" | sed 's/defmodule \(.*\) do/\1/')

    if [[ -z "$module_name" ]]; then
      continue
    fi

    echo_info "Creating test template for $module_name"

    cat > "$test_file" <<EOF
defmodule ${module_name}Test do
  use ExUnit.Case, async: true
  use ${module_name%.*}.TestCase

  alias ${module_name}

  describe "${basename}" do
    # TODO: Add tests for each API operation
    test "placeholder - remove this and add real tests" do
      # This is a placeholder test to maintain code coverage
      # Add real tests for each API operation in this module
      assert true
    end
  end
end
EOF

  done
}

# Main execution
main() {
  echo_info "Running post-generation processing..."

  fix_generated_code
  update_version_file
  ensure_test_structure
  check_test_coverage
  generate_test_templates

  echo_info "Post-generation processing complete."
}

main
