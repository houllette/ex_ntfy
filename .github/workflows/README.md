# GitHub Actions Workflows

## Status: Disabled by Default

All workflow files in this directory have a `.disabled` extension, which means they are **inactive** and will not run on this template repository.

## Why Are They Disabled?

These workflows are designed for SDK projects created from this template, not for the template itself. They are disabled to:

1. **Prevent unnecessary workflow runs** on the template repository
2. **Avoid confusion** about what the workflows are testing
3. **Save GitHub Actions minutes**
4. **Allow clean activation** when you use the template

## How to Enable Workflows

Workflows are automatically enabled when you run the setup script:

```bash
./scripts/setup.sh
```

This script will:
1. Prompt you for your SDK configuration
2. Enable all workflows by renaming `*.yml.disabled` → `*.yml`
3. Commit the enabled workflows to your repository

After setup, the workflows will be active and ready to use!

## Manual Enabling (Alternative)

If you prefer to enable workflows manually:

```bash
cd .github/workflows
for file in *.disabled; do
  mv "$file" "${file%.disabled}"
done
```

## Available Workflows

Once enabled, you'll have these workflows:

### 1. `test.yml`
- **Trigger**: Every push and pull request
- **Purpose**: Run tests, linting, and type checking
- **Matrix**: Tests across multiple Elixir/OTP versions

### 2. `regenerate-sdk.yml`
- **Trigger**: OpenAPI spec changes, manual dispatch, weekly schedule
- **Purpose**: Auto-regenerate SDK when spec changes
- **Output**: Creates PR with regenerated code

### 3. `publish.yml`
- **Trigger**: Version tags (e.g., `v1.0.0`)
- **Purpose**: Publish to Hex.pm
- **Requirements**: `HEX_API_KEY` secret must be configured

### 4. `breaking-changes.yml`
- **Trigger**: Pull requests that modify spec or API code
- **Purpose**: Detect breaking changes
- **Output**: Comments on PR with analysis

## Configuration Required

After enabling workflows, you'll need to configure:

1. **Repository Secrets** (Settings → Secrets → Actions):
   - `HEX_API_KEY`: Required for publishing to Hex.pm
     - Get it by running: `mix hex.user auth`

2. **Branch Protection** (Settings → Branches) - Recommended:
   - Require status checks to pass before merging
   - Require pull request reviews
   - Enable "Require branches to be up to date before merging"

## Customization

All workflow files can be customized for your needs:

- **Change Elixir/OTP versions**: Edit the `matrix` in `test.yml`
- **Adjust coverage threshold**: Edit the threshold check in `test.yml`
- **Modify schedule**: Change the `cron` expression in `regenerate-sdk.yml`
- **Add notifications**: Add notification steps to any workflow

## Testing Workflows

After enabling, test that workflows are working:

```bash
# Make a small change
echo "# Test" >> README.md

# Commit and push
git add README.md
git commit -m "Test workflows"
git push

# Check Actions tab on GitHub
```

You should see the `test.yml` workflow start automatically.

## Troubleshooting

### Workflows not running after enabling?

1. Check that files have `.yml` extension (not `.yml.disabled`)
2. Verify files are committed and pushed to GitHub
3. Check the Actions tab for any error messages
4. Ensure you have Actions enabled in repository settings

### Workflows failing?

1. Check the workflow logs in the Actions tab
2. Verify all required secrets are configured
3. Ensure your OpenAPI spec is valid
4. Run tests locally first: `mix test`

## More Information

- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [Setup Script Documentation](../../scripts/README.md)
- [Main README](../../README.md)
