require 'bundler/setup'
Bundler.setup

require 'pry-byebug'
require 'celluloid'
require 'shoryuken'
require 'json'

options_file = File.join(File.expand_path('../..', __FILE__), 'shoryuken.yml')

$options = {}

if File.exists? options_file
  $options = YAML.load(File.read(options_file)).deep_symbolize_keys

  AWS.config $options[:aws]
end

Shoryuken.logger.level = Logger::UNKNOWN
Celluloid.logger.level = Logger::UNKNOWN

class TestWorker
  include Shoryuken::Worker

  shoryuken_options queue: 'default'

  def perform(sqs_msg, body); end
end

RSpec.configure do |config|
  config.filter_run_excluding slow: true unless ENV['SPEC_ALL']

  config.before do
    # remove doubles, preventing:
    # Double "Queue" was originally created in one example but has leaked into another example and can no longer be used.
    # rspec-mocks' doubles are designed to only last for one example, and you need to create a new one in each example you wish to use it for.
    Shoryuken::Client.class_variable_set :@@queues, {}
    Shoryuken::Client.class_variable_set :@@visibility_timeouts, {}

    Shoryuken.options.clear
    Shoryuken.options.merge!($options)

    Shoryuken.queues.clear

    Shoryuken.options[:concurrency] = 1
    Shoryuken.options[:delay]       = 1
    Shoryuken.options[:timeout]     = 1

    Shoryuken.options[:aws] = {}

    TestWorker.get_shoryuken_options.clear
    TestWorker.get_shoryuken_options['queue'] = 'default'

    Shoryuken.workers.clear
    Shoryuken.register_worker('default', TestWorker)
  end
end
