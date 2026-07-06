#!/usr/bin/env bash
set -euo pipefail

# OpenAPI Specification Validation Script

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
OPENAPI_SPEC="$PROJECT_ROOT/openapi-spec.yaml"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo_info() { echo -e "${GREEN}[VALIDATE]${NC} $*"; }
echo_warn() { echo -e "${YELLOW}[VALIDATE]${NC} $*"; }
echo_error() { echo -e "${RED}[VALIDATE]${NC} $*"; }

# Check if spec file exists
check_spec_exists() {
  if [[ ! -f "$OPENAPI_SPEC" ]]; then
    echo_error "OpenAPI spec not found: $OPENAPI_SPEC"
    exit 1
  fi
  echo_info "Found spec file: $OPENAPI_SPEC"
}

# Basic YAML syntax validation
validate_yaml_syntax() {
  echo_info "Validating YAML syntax..."

  # Try using yq if available
  if command -v yq &> /dev/null; then
    if yq eval '.' "$OPENAPI_SPEC" > /dev/null 2>&1; then
      echo_info "YAML syntax is valid"
      return 0
    else
      echo_error "YAML syntax is invalid"
      return 1
    fi
  fi

  # Try using python
  if command -v python3 &> /dev/null; then
    if python3 -c "import yaml; yaml.safe_load(open('$OPENAPI_SPEC'))" 2>&1; then
      echo_info "YAML syntax is valid"
      return 0
    else
      echo_error "YAML syntax is invalid"
      return 1
    fi
  fi

  echo_warn "No YAML validator found (yq or python3), skipping syntax check"
  return 0
}

# Validate OpenAPI structure
validate_openapi_structure() {
  echo_info "Validating OpenAPI structure..."

  # Check for required fields
  local required_fields=("openapi" "info" "paths")

  if command -v yq &> /dev/null; then
    for field in "${required_fields[@]}"; do
      if ! yq eval "has(\"$field\")" "$OPENAPI_SPEC" | grep -q "true"; then
        echo_error "Missing required field: $field"
        return 1
      fi
    done
    echo_info "Required fields present"
  else
    echo_warn "Cannot validate structure without yq"
  fi

  return 0
}

# Validate with OpenAPI Generator (if available)
validate_with_generator() {
  echo_info "Validating with OpenAPI Generator..."

  local validator=""

  # Try npx
  if command -v npx &> /dev/null; then
    validator="npx @openapitools/openapi-generator-cli validate"
  # Try docker
  elif command -v docker &> /dev/null; then
    validator="docker run --rm -v \"${PROJECT_ROOT}:/local\" openapitools/openapi-generator-cli validate"
  else
    echo_warn "OpenAPI Generator not found, skipping validation"
    return 0
  fi

  if [[ "$validator" == *"docker"* ]]; then
    if docker run --rm -v "${PROJECT_ROOT}:/local" openapitools/openapi-generator-cli validate -i /local/openapi-spec.yaml 2>&1; then
      echo_info "OpenAPI Generator validation passed"
      return 0
    else
      echo_error "OpenAPI Generator validation failed"
      return 1
    fi
  else
    if eval "$validator -i \"$OPENAPI_SPEC\"" 2>&1; then
      echo_info "OpenAPI Generator validation passed"
      return 0
    else
      echo_error "OpenAPI Generator validation failed"
      return 1
    fi
  fi
}

# Check for common issues
check_common_issues() {
  echo_info "Checking for common issues..."

  local warnings=0

  # Check if there are any paths defined
  if command -v yq &> /dev/null; then
    local path_count
    path_count=$(yq eval '.paths | length' "$OPENAPI_SPEC")

    if [[ "$path_count" == "0" ]]; then
      echo_warn "No paths defined in the spec"
      ((warnings++))
    else
      echo_info "Found $path_count path(s)"
    fi

    # Check for schemas/components
    local schema_count
    schema_count=$(yq eval '.components.schemas | length' "$OPENAPI_SPEC" 2>/dev/null || echo "0")

    if [[ "$schema_count" == "0" ]]; then
      echo_warn "No schemas defined in components"
      ((warnings++))
    else
      echo_info "Found $schema_count schema(s)"
    fi
  fi

  if [[ $warnings -gt 0 ]]; then
    echo_warn "Found $warnings warning(s)"
  fi

  return 0
}

# Main execution
main() {
  echo_info "Starting OpenAPI specification validation..."
  echo ""

  local errors=0

  check_spec_exists || ((errors++))
  validate_yaml_syntax || ((errors++))
  validate_openapi_structure || ((errors++))
  validate_with_generator || ((errors++))
  check_common_issues

  echo ""
  if [[ $errors -eq 0 ]]; then
    echo_info "✓ Validation passed!"
    exit 0
  else
    echo_error "✗ Validation failed with $errors error(s)"
    exit 1
  fi
}

main "$@"
