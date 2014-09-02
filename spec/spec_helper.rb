require 'bundler/setup'
Bundler.setup

require 'pry-byebug'
require 'shoryuken'

config_file = File.join(File.expand_path('../..', __FILE__), 'shoryuken.yml')

if File.exist? config_file
  $config = YAML.load File.read(config_file)

  AWS.config($config['aws'])
end

Shoryuken::Util.logger.level = Logger::ERROR

RSpec.configure do |config|
  config.filter_run_excluding slow: true unless ENV['SPEC_ALL']
end
