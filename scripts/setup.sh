#!/usr/bin/env bash
set -euo pipefail

# Elixir SDK Generator - Setup Script
# This script initializes a new SDK project from this template

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
SETUP_JSON="$PROJECT_ROOT/setup.json"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo_info() { echo -e "${GREEN}[INFO]${NC} $*"; }
echo_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
echo_error() { echo -e "${RED}[ERROR]${NC} $*"; }

# Check dependencies
check_dependencies() {
  echo_info "Checking dependencies..."

  local missing_deps=()

  if ! command -v jq &> /dev/null; then
    missing_deps+=("jq")
  fi

  if ! command -v java &> /dev/null; then
    echo_warn "Java not found. OpenAPI Generator requires Java 8+."
    missing_deps+=("java")
  fi

  if [ ${#missing_deps[@]} -ne 0 ]; then
    echo_error "Missing dependencies: ${missing_deps[*]}"
    echo_error "Please install them and try again."
    exit 1
  fi

  echo_info "All dependencies found."
}

# Prompt user for configuration
prompt_config() {
  echo ""
  echo "================================================"
  echo "  Elixir SDK Generator - Initial Setup"
  echo "================================================"
  echo ""
  echo "This script will configure your new SDK project."
  echo ""

  # Package name
  read -rp "Package name (e.g., my_api_client): " PACKAGE_NAME
  if [[ ! $PACKAGE_NAME =~ ^[a-z][a-z0-9_]*$ ]]; then
    echo_error "Invalid package name. Must be lowercase with underscores."
    exit 1
  fi

  # Module name
  read -rp "Module name (e.g., MyApiClient): " MODULE_NAME
  if [[ ! $MODULE_NAME =~ ^[A-Z][A-Za-z0-9]*$ ]]; then
    echo_error "Invalid module name. Must be PascalCase."
    exit 1
  fi

  # Description
  read -rp "Description: " DESCRIPTION

  # Author info
  read -rp "Author name: " AUTHOR_NAME
  read -rp "Author email: " AUTHOR_EMAIL

  # Git info
  read -rp "GitHub username/org: " GIT_USER
  read -rp "GitHub repo name: " GIT_REPO

  # Base URL (optional)
  read -rp "API base URL (optional, can be configured later): " BASE_URL

  # OpenAPI spec
  read -rp "Path to OpenAPI spec (or URL): " OPENAPI_SPEC_PATH

  # Hex organization (optional)
  read -rp "Hex.pm organization (optional, for private packages): " HEX_ORG

  echo ""
}

# Apply configuration to files
apply_config() {
  echo_info "Applying configuration..."

  # Update generator-config.yaml
  local generator_config="$PROJECT_ROOT/generator-config.yaml"
  sed -i.bak "s/{{PACKAGE_NAME}}/$PACKAGE_NAME/g" "$generator_config"
  sed -i.bak "s/{{MODULE_NAME}}/$MODULE_NAME/g" "$generator_config"
  sed -i.bak "s/{{AUTHOR_NAME}}/$AUTHOR_NAME/g" "$generator_config"
  sed -i.bak "s/{{AUTHOR_EMAIL}}/$AUTHOR_EMAIL/g" "$generator_config"
  sed -i.bak "s/{{GIT_REPO}}/$GIT_REPO/g" "$generator_config"
  sed -i.bak "s/{{GIT_USER}}/$GIT_USER/g" "$generator_config"
  rm -f "$generator_config.bak"

  # Copy OpenAPI spec if it's a file
  if [[ -f "$OPENAPI_SPEC_PATH" ]]; then
    cp "$OPENAPI_SPEC_PATH" "$PROJECT_ROOT/openapi-spec.yaml"
    echo_info "Copied OpenAPI spec to openapi-spec.yaml"
  elif [[ "$OPENAPI_SPEC_PATH" =~ ^https?:// ]]; then
    echo_info "Downloading OpenAPI spec from $OPENAPI_SPEC_PATH"
    curl -sSL "$OPENAPI_SPEC_PATH" -o "$PROJECT_ROOT/openapi-spec.yaml"
  else
    echo_error "Invalid OpenAPI spec path: $OPENAPI_SPEC_PATH"
    exit 1
  fi

  # Create config directory if it doesn't exist
  mkdir -p "$PROJECT_ROOT/config"

  # Update runtime.exs if base URL was provided
  if [[ -n "$BASE_URL" ]]; then
    local runtime_config="$PROJECT_ROOT/config/runtime.exs"
    if [[ -f "$runtime_config" ]]; then
      sed -i.bak "s|base_url:.*|base_url: System.get_env(\"API_BASE_URL\", \"$BASE_URL\"),|g" "$runtime_config"
      rm -f "$runtime_config.bak"
    fi
  fi

  echo_info "Configuration applied successfully."
}

# Enable GitHub Actions workflows
enable_workflows() {
  echo_info "Enabling GitHub Actions workflows..."

  local workflows_dir="$PROJECT_ROOT/.github/workflows"

  if [[ ! -d "$workflows_dir" ]]; then
    echo_warn "Workflows directory not found, skipping."
    return 0
  fi

  local enabled_count=0

  # Enable all disabled workflow files
  for disabled_file in "$workflows_dir"/*.disabled; do
    if [[ -f "$disabled_file" ]]; then
      local enabled_file="${disabled_file%.disabled}"
      mv "$disabled_file" "$enabled_file"
      echo_info "Enabled: $(basename "$enabled_file")"
      ((enabled_count++))
    fi
  done

  if [[ $enabled_count -eq 0 ]]; then
    echo_info "No disabled workflows found (may already be enabled)"
  else
    echo_info "Enabled $enabled_count workflow(s)"
  fi
}

# Initialize git if not already a repo
init_git() {
  if [[ ! -d "$PROJECT_ROOT/.git" ]]; then
    echo_info "Initializing git repository..."
    cd "$PROJECT_ROOT"
    git init
    git add .
    git commit -m "Initial commit from elixir-sdk-generator template"

    # Set up remote if we have git info
    if [[ -n "$GIT_USER" ]] && [[ -n "$GIT_REPO" ]]; then
      echo_info "Setting up git remote..."
      git remote add origin "git@github.com:${GIT_USER}/${GIT_REPO}.git"
      echo_info "Remote 'origin' set to: git@github.com:${GIT_USER}/${GIT_REPO}.git"
    fi
  else
    echo_info "Git repository already initialized."
  fi
}

# Main execution
main() {
  check_dependencies
  prompt_config
  apply_config
  enable_workflows
  init_git

  echo ""
  echo_info "Setup complete! Next steps:"
  echo ""
  echo "  1. Review the configuration in generator-config.yaml"
  echo "  2. Run: ./scripts/regenerate.sh"
  echo "  3. Run tests: mix test"
  echo "  4. Review the generated SDK in lib/"
  echo ""
  echo_info "To regenerate the SDK after updating the OpenAPI spec:"
  echo "  ./scripts/regenerate.sh"
  echo ""
}

main
