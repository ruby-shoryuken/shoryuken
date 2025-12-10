# frozen_string_literal: true

# Integration test helper for process-isolated testing

require 'timeout'
require 'json'
require 'securerandom'
require 'aws-sdk-sqs'
require 'shoryuken'

module IntegrationsHelper
  class TestFailure < StandardError; end

  # Assertions
  def assert(condition, message = "Assertion failed")
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

  def refute(condition, message = "Refutation failed")
    assert(!condition, message)
  end

  # Reset Shoryuken state
  def reset_shoryuken
    Shoryuken.groups.clear if defined?(Shoryuken) && Shoryuken.respond_to?(:groups)
    Shoryuken.worker_registry.clear if defined?(Shoryuken) && Shoryuken.respond_to?(:worker_registry)

    if defined?(Shoryuken) && Shoryuken.respond_to?(:options)
      Shoryuken.options[:concurrency] = 25
      Shoryuken.options[:delay] = 0
      Shoryuken.options[:timeout] = 8
    end
  end

  # LocalStack setup
  def setup_localstack
    Aws.config[:stub_responses] = false

    sqs_client = Aws::SQS::Client.new(
      region: 'us-east-1',
      endpoint: 'http://localhost:4566',
      access_key_id: 'fake',
      secret_access_key: 'fake'
    )

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

  def create_fifo_queue(queue_name)
    create_test_queue(queue_name, attributes: {
      'FifoQueue' => 'true',
      'ContentBasedDeduplication' => 'true'
    })
  end

  # Poll until condition met
  def poll_queues_until(timeout: 15)
    launcher = Shoryuken::Launcher.new
    launcher.start
    Timeout.timeout(timeout) { sleep 0.5 until yield }
  ensure
    launcher.stop
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

include IntegrationsHelper
