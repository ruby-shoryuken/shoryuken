require 'bundler/setup'
Bundler.setup

require 'pry-byebug'
require 'shoryuken'

options_file = File.join(File.expand_path('../..', __FILE__), 'shoryuken.yml')

if File.exist? options_file
  options = YAML.load(File.read(options_file)).deep_symbolize_keys

  AWS.config options[:aws]

  Shoryuken.options.merge!(options)

  Shoryuken.queues << 'shoryuken'
end

Shoryuken.logger.level = Logger::ERROR

RSpec.configure do |config|
  config.filter_run_excluding slow: true unless ENV['SPEC_ALL']

  config.before do
    # remove doubles, preventing:
    # Double "Queue" was originally created in one example but has leaked into another example and can no longer be used.
    # rspec-mocks' doubles are designed to only last for one example, and you need to create a new one in each example you wish to use it for.
    Shoryuken::Client.reset!
  end
end
