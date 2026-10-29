# frozen_string_literal: true

# Integration test helper for process-isolated testing

require 'warning'

$VERBOSE = true

if Warning.respond_to?(:categories)
  (Warning.categories - %i[experimental]).each do |cat|
    Warning[cat] = true
  end
end

# Process warnings and raise on unexpected ones from our code
Warning.process do |warning|
  # Only check warnings from our code (not dependencies)
  next unless warning.include?(Dir.pwd)

  # Filter out warnings we don't care about in specs
  next if warning.include?('_spec')

  # Ignore vendor directory
  next if warning.include?('vendor/')

  # Ignore bundle path
  next if warning.include?('bundle/')

  raise "Warning in your code: #{warning}"
end

require 'timeout'
require 'json'
require 'open3'
require 'rbconfig'
require 'tmpdir'
require 'fileutils'
require 'securerandom'
require 'aws-sdk-sqs'
require 'shoryuken'
require 'singleton'

require_relative 'integration_helpers/data_collector'
require_relative 'integration_helpers/cleanup_helper'
require_relative 'integration_helpers/dead_letter_queue_helper'
require_relative 'integration_helpers/process_helper'

module IntegrationsHelper
  include CleanupHelper
  include DeadLetterQueueHelper
  include ProcessHelper

  class TestFailure < StandardError; end

  # Assertions
  def assert(condition, message = 'Assertion failed')
    raise TestFailure, message unless condition
  end

  def assert_equal(expected, actual, message = nil)
    message ||= "Expected #{expected.inspect}, got #{actual.inspect}"
    assert(expected == actual, message)
  end

  def assert_includes(collection, item, message = nil)
    message ||= "Expected #{collection.inspect} to include #{item.inspect}"
    assert(collection.include?(item), message)
  end

  def refute(condition, message = 'Refutation failed')
    assert(!condition, message)
  end

  # Configure ActiveJob with Shoryuken adapter
  def setup_active_job
    require 'active_job'
    require 'active_job/queue_adapters/shoryuken_adapter'
    require 'active_job/extensions'

    ActiveJob::Base.queue_adapter = :shoryuken
  end

  # Configure Shoryuken to use ElasticMQ for real SQS integration tests
  def setup_sqs
    Aws.config[:stub_responses] = false

    sqs_client = Aws::SQS::Client.new(
      region: 'us-east-1',
      endpoint: 'http://localhost:9324',
      access_key_id: 'fake',
      secret_access_key: 'fake'
    )

    Shoryuken.options[:concurrency] = 25
    Shoryuken.options[:delay] = 0
    Shoryuken.options[:timeout] = 8

    executor = Concurrent::CachedThreadPool.new(auto_terminate: true)
    Shoryuken.define_singleton_method(:launcher_executor) { executor }

    Shoryuken.configure_client { |config| config.sqs_client = sqs_client }
    Shoryuken.configure_server { |config| config.sqs_client = sqs_client }
  end

  # Queue helpers
  def create_test_queue(queue_name, attributes: {})
    Shoryuken::Client.sqs.create_queue(queue_name: queue_name, attributes: attributes)
  end

  def delete_test_queue(queue_name)
    queue_url = Shoryuken::Client.sqs.get_queue_url(queue_name: queue_name).queue_url
    Shoryuken::Client.sqs.delete_queue(queue_url: queue_url)
  rescue Aws::SQS::Errors::NonExistentQueue
  end

  def create_fifo_queue(queue_name, attributes: {})
    create_test_queue(
      queue_name, attributes: {
        'FifoQueue' => 'true',
        'ContentBasedDeduplication' => 'true'
      }.merge(attributes)
    )
  end

  # Messages in a queue, visible and in flight, plus delayed ones with delayed: true
  def queue_size(queue_name, delayed: false)
    queue_url = Shoryuken::Client.sqs.get_queue_url(queue_name: queue_name).queue_url
    attribute_names = %w[ApproximateNumberOfMessages ApproximateNumberOfMessagesNotVisible]
    attribute_names << 'ApproximateNumberOfMessagesDelayed' if delayed

    Shoryuken::Client.sqs.get_queue_attributes(
      queue_url: queue_url,
      attribute_names: attribute_names
    ).attributes.values.sum(&:to_i)
  end

  # Poll until condition met
  def poll_queues_until(timeout: 15)
    launcher = Shoryuken::Launcher.new
    launcher.start
    Timeout.timeout(timeout) { sleep 0.5 until yield }
  ensure
    # Guard stop with a hard deadline so a stuck dispatch thread (e.g. an SQS
    # HTTP call that never returns) can't block the spec process forever.
    Timeout.timeout(30) { launcher.stop }
  end

  # Simple mock object
  def double(_name = nil)
    Object.new
  end

  # Job capture for ActiveJob tests
  class JobCapture
    attr_reader :jobs

    def initialize
      @jobs = []
    end

    def start_capturing
      @jobs.clear
      capture = self

      queue_mock = Object.new
      queue_mock.define_singleton_method(:fifo?) { false }
      queue_mock.define_singleton_method(:send_message) do |params|
        capture.jobs << {
          queue: params[:queue_name] || :default,
          message_body: params[:message_body],
          delay_seconds: params[:delay_seconds],
          message_attributes: params[:message_attributes]
        }
      end

      Shoryuken::Client.define_singleton_method(:queues) do |queue_name = nil|
        queue_mock.define_singleton_method(:name) { queue_name } if queue_name
        queue_name ? queue_mock : { default: queue_mock }
      end

      Shoryuken.define_singleton_method(:register_worker) { |*| nil }
    end

    def last_job
      @jobs.last
    end

    def job_count
      @jobs.size
    end
  end
end

include IntegrationsHelper # rubocop:disable Style/MixinUsage
