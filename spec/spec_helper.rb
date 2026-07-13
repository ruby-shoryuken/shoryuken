# frozen_string_literal: true

require 'warning'

$VERBOSE = true

if Warning.respond_to?(:categories)
  (Warning.categories - %i[experimental]).each do |cat|
    Warning[cat] = true
  end
end

Warning.process do |warning|
  # Only check warnings from our code (not dependencies)
  next unless warning.include?(Dir.pwd)

  # Filter out warnings we don't care about in specs
  next if warning.include?('_spec')

  # Ignore vendor and bundle directories
  next if warning.include?('vendor/')
  next if warning.include?('bundle/')
  next if warning.include?('.bundle/')

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

unless ENV['SIMPLECOV_DISABLED']
  require 'simplecov'
  SimpleCov.start do
  skip '/spec/'
  skip '/test_workers/'
  skip '/examples/'
  skip '/vendor/'
  skip '/.bundle/'

  group 'Library', 'lib/'
  group 'ActiveJob', 'lib/active_job'
  group 'Middleware', 'lib/shoryuken/middleware'
  group 'Polling', 'lib/shoryuken/polling'
  group 'Workers', 'lib/shoryuken/worker'
  group 'Helpers', 'lib/shoryuken/helpers'

  enable_coverage :branch

  minimum_coverage 89
  coverage(:line) { minimum_per_file 60 }
  end
end

config_file = File.join(File.expand_path('..', __dir__), 'spec', 'shoryuken.yml')

Shoryuken::EnvironmentLoader.setup_options(config_file: config_file)

Shoryuken.logger.level = Logger::UNKNOWN

class TestWorker
  include Shoryuken::Worker

  shoryuken_options queue: 'default'

  def perform(sqs_msg, body); end
end

# Emit a full Ruby thread dump when the process receives USR1.  The CI
# watchdog (specs.yml) sends this signal when unit specs run longer than
# expected so we can see exactly which thread is stuck without waiting for the
# job-level timeout to kill the process silently.
if Signal.list.key?('USR1')
  Signal.trap('USR1') do
    # Signal handlers run in a restricted context; use a plain IO write
    # rather than puts/logger to stay async-signal safe.
    output = +"\n=== Thread dump (USR1 watchdog) ===\n"
    Thread.list.each do |t|
      output << "--- Thread #{t.object_id} [#{t.status}] ---\n"
      output << ((t.backtrace || ['(no backtrace)']).join("\n")) << "\n"
    end
    output << "=== End thread dump ===\n"
    $stderr.write(output)
  end
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
    Shoryuken.active_job_fifo_message_deduplication = true

    Shoryuken.worker_registry.clear
    Shoryuken.register_worker('default', TestWorker)

    Aws.config[:stub_responses] = true

    Shoryuken.sqs_client_receive_message_opts.clear

    Shoryuken.cache_visibility_timeout = false

    allow(Shoryuken).to receive(:active_job?).and_return(false)
  end
end
