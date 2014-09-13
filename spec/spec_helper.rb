require 'bundler/setup'
Bundler.setup

require 'pry-byebug'
require 'shoryuken'

options_file = File.join(File.expand_path('../..', __FILE__), 'shoryuken.yml')

if File.exist? options_file
  $options = YAML.load(File.read(options_file)).deep_symbolize_keys

  AWS.config $options[:aws]
end

Shoryuken.logger.level = Logger::ERROR

RSpec.configure do |config|
  config.filter_run_excluding slow: true unless ENV['SPEC_ALL']
end
