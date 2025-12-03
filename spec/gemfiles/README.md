# Test Gemfiles

This directory contains Gemfiles for testing Shoryuken with different Rails versions.

## Structure

- `rails_X_Y.gemfile` - Full Rails framework testing (for comprehensive integration tests)  
- `rails_X_Y_activejob.gemfile` - ActiveJob-only testing (for focused adapter testing)

## Usage

### CI/Automated Testing
These gemfiles are automatically used by GitHub Actions in `.github/workflows/specs.yml`.

### Manual Testing
```bash
# Test with Rails 8.0 full framework
BUNDLE_GEMFILE=spec/gemfiles/rails_8_0.gemfile bundle install
BUNDLE_GEMFILE=spec/gemfiles/rails_8_0.gemfile bundle exec rspec

# Test with Rails 8.0 ActiveJob only
BUNDLE_GEMFILE=spec/gemfiles/rails_8_0_activejob.gemfile bundle install
BUNDLE_GEMFILE=spec/gemfiles/rails_8_0_activejob.gemfile bundle exec rspec
```

## Adding New Rails Versions

1. Copy an existing gemfile pair (e.g., `rails_8_0.gemfile` and `rails_8_0_activejob.gemfile`)
2. Update the Rails version constraints
3. Add the new gemfiles to the CI matrix in `.github/workflows/specs.yml`
4. Test locally before committing

## Integration Tests

Integration tests in `spec/integration/` have their own dedicated Gemfiles that are self-contained and independent of these version-specific gemfiles.

## Renovate

Renovate is configured to automatically detect and update dependencies in these gemfiles through the `renovate.json` configuration.