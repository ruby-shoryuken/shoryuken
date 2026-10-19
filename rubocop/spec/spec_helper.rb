# frozen_string_literal: true

require 'rubocop'
require 'rubocop/rspec/support'
require_relative '../cops/multiline_method_call_parentheses'

RSpec.configure do |config|
  config.include RuboCop::RSpec::ExpectOffense
  config.disable_monkey_patching!
  config.raise_errors_for_deprecations!
end
