# frozen_string_literal: true

Warning[:performance] = true if RUBY_VERSION >= '3.3'
Warning[:deprecated] = true
$VERBOSE = true

require 'warning'

Warning.process do |warning|
  next unless warning.include?(Dir.pwd)
  next if warning.include?('useless use of a variable in void context') && warning.include?('core_ext')
  next if warning.include?('vendor/')

  raise "Warning in your code: #{warning}"
end

require 'bundler/setup'
Bundler.setup

begin
  require 'pry-byebug'
rescue LoadError
end

require 'shoryuken'
require 'json'
require 'dotenv'
require 'securerandom'
require 'ostruct'
Dotenv.load

require 'simplecov'
SimpleCov.start

config_file = File.join(File.expand_path('..', __dir__), 'spec', 'shoryuken.yml')

Shoryuken::EnvironmentLoader.setup_options(config_file: config_file)

Shoryuken.logger.level = Logger::UNKNOWN

class TestWorker
  include Shoryuken::Worker

  shoryuken_options queue: 'default'

  def perform(sqs_msg, body); end
end

RSpec.configure do |config|
  config.before do
    Shoryuken::Client.class_variable_set :@@queues, {}

    Shoryuken::Client.sqs = nil

    Shoryuken.groups.clear

    Shoryuken.options[:concurrency] = 1
    Shoryuken.options[:delay]       = 1.0
    Shoryuken.options[:timeout]     = 1
    Shoryuken.options[:daemon]      = nil
    Shoryuken.options[:logfile]     = nil
    Shoryuken.options[:queues]      = nil

    Shoryuken.options[:exception_handlers] = []

    TestWorker.get_shoryuken_options.clear
    TestWorker.get_shoryuken_options['queue'] = 'default'

    Shoryuken.active_job_queue_name_prefixing = false

    Shoryuken.worker_registry.clear
    Shoryuken.register_worker('default', TestWorker)

    Aws.config[:stub_responses] = true

    Shoryuken.sqs_client_receive_message_opts.clear

    Shoryuken.cache_visibility_timeout = false

    allow(Shoryuken).to receive(:active_job?).and_return(false)
  end
end
