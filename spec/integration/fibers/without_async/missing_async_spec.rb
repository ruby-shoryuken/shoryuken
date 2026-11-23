# frozen_string_literal: true

# This spec tests that the fiber executor without the async gem in the bundle raises a clear error when the launcher
# is built, before any message is fetched.

Shoryuken.executor = :fiber
Shoryuken.add_group('default', 1)
Shoryuken.add_queue('fiber-without-async', 1, 'default')

refute(Gem.loaded_specs.key?('async'), 'the bundle must not have the async gem')

error = raised_error(Shoryuken::Errors::InvalidConfigurationError) { Shoryuken::Launcher.new }

refute(error.nil?, 'building the launcher must raise')
assert_includes(error.message, "The fiber executor needs the async gem. Add `gem 'async'` to your Gemfile")
