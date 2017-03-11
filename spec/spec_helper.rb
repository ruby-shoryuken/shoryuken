require 'bundler/setup'
Bundler.setup

require 'pry-byebug'
require 'shoryuken'
require 'json'
require 'dotenv'
Dotenv.load

if ENV['CODECLIMATE_REPO_TOKEN']
  require 'simplecov'
  SimpleCov.start
end

config_file = File.join(File.expand_path('../..', __FILE__), 'spec', 'shoryuken.yml')

Shoryuken::EnvironmentLoader.setup_options(config_file: config_file)

Shoryuken.logger.level = Logger::UNKNOWN

class TestWorker
  include Shoryuken::Worker

  shoryuken_options queue: 'default'

  def perform(sqs_msg, body); end
end

RSpec.configure do |config|
  # Only run slow tests if SPEC_ALL=true and AWS_ACCESS_KEY_ID is present
  # The AWS_ACCESS_KEY_ID checker is because Travis CI
  # does not expose ENV variables to pull requests from forked repositories
  # http://docs.travis-ci.com/user/pull-requests/
  config.filter_run_excluding slow: true if ENV['SPEC_ALL'] != 'true' || ENV['AWS_ACCESS_KEY_ID'].nil?

  config.before do
    Shoryuken::Client.class_variable_set :@@queues, {}

    Shoryuken::Client.sqs = nil

    Shoryuken.queues.clear

    Shoryuken.options[:concurrency] = 1
    Shoryuken.options[:delay]       = 1
    Shoryuken.options[:timeout]     = 1
    Shoryuken.options[:daemon]      = nil
    Shoryuken.options[:logfile]     = nil
    Shoryuken.options[:queues]      = nil

    TestWorker.get_shoryuken_options.clear
    TestWorker.get_shoryuken_options['queue'] = 'default'

    Shoryuken.worker_registry.clear
    Shoryuken.register_worker('default', TestWorker)
  end
end
