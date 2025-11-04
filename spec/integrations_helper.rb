# frozen_string_literal: true

# Integration test helper for Karafka-style process-isolated testing
# This file provides common utilities for integration tests without RSpec overhead

require 'timeout'
require 'json'
require 'aws-sdk-sqs'

module IntegrationsHelper
  # Test utilities
  class TestFailure < StandardError; end

  # Simple assertion methods
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

  def assert_raises(exception_class, message = nil)
    begin
      yield
      raise TestFailure, message || "Expected #{exception_class} to be raised, but nothing was raised"
    rescue exception_class
      # Expected exception was raised
    end
  end

  def refute(condition, message = "Refutation failed")
    assert(!condition, message)
  end

  # Mock SQS for testing
  def setup_mock_sqs
    # Configure AWS SDK to use stubbed responses
    Aws.config.update(
      stub_responses: true,
      region: 'us-east-1',
      access_key_id: 'test',
      secret_access_key: 'test'
    )

    # Create mock SQS client
    sqs = Aws::SQS::Client.new
    allow_sqs_operations(sqs)
    sqs
  end

  def allow_sqs_operations(sqs)
    # Mock common SQS operations
    sqs.stub_responses(:send_message, message_id: 'test-message-id')
    sqs.stub_responses(:send_message_batch, { successful: [], failed: [] })
    sqs.stub_responses(:get_queue_url, queue_url: 'https://sqs.us-east-1.amazonaws.com/123456789/test-queue')
    sqs.stub_responses(:get_queue_attributes, attributes: { 'FifoQueue' => 'false' })
  end

  # Reset Shoryuken state between tests
  def reset_shoryuken
    # Only reset if Shoryuken is fully loaded
    if defined?(Shoryuken) && Shoryuken.respond_to?(:groups)
      Shoryuken.groups.clear
    end

    if defined?(Shoryuken) && Shoryuken.respond_to?(:worker_registry)
      Shoryuken.worker_registry.clear
    end

    # Reset configuration if available
    if defined?(Shoryuken) && Shoryuken.respond_to?(:options)
      Shoryuken.options[:concurrency] = 25
      Shoryuken.options[:delay] = 0
      Shoryuken.options[:timeout] = 8
    end
  end

  # Setup ActiveJob with Shoryuken
  def setup_activejob
    require 'active_job'
    require 'active_job/queue_adapters/shoryuken_adapter'
    require 'active_job/extensions'

    ActiveJob::Base.queue_adapter = :shoryuken

    # Reset ActiveJob state
    ActiveJob::Base.logger = Logger.new('/dev/null') if ActiveJob::Base.respond_to?(:logger=)
  end

  # Simple test runner
  def run_test(description, &block)
    begin
      # Setup
      reset_shoryuken
      setup_mock_sqs

      # Run test
      instance_eval(&block)
    rescue TestFailure => e
      raise
    rescue => e
      raise TestFailure, "#{e.class}: #{e.message}"
    end
  end

  # Test suite runner
  def run_test_suite(name, &block)
    instance_eval(&block)
  end

  # Capture enqueued jobs
  class JobCapture
    attr_reader :jobs

    def initialize
      @jobs = []
      @original_send_message = nil
    end

    def start_capturing
      @jobs.clear
      capture_instance = self

      # Create a simple queue mock
      queue_mock = Object.new
      queue_mock.define_singleton_method(:fifo?) { false }
      queue_mock.define_singleton_method(:send_message) do |params|
        capture_instance.instance_variable_get(:@jobs) << {
          queue: params[:queue_name] || :default,
          message_body: params[:message_body],
          delay_seconds: params[:delay_seconds],
          message_attributes: params[:message_attributes],
          message_group_id: params[:message_group_id],
          message_deduplication_id: params[:message_deduplication_id]
        }
      end

      # Mock Shoryuken::Client.queues
      Shoryuken::Client.define_singleton_method(:queues) do |queue_name = nil|
        if queue_name
          queue_mock.define_singleton_method(:name) { queue_name }
          queue_mock
        else
          { default: queue_mock }
        end
      end

      # Mock register_worker
      Shoryuken.define_singleton_method(:register_worker) { |*args| nil }
    end

    def stop_capturing
      @jobs = []
    end

    def last_job
      @jobs.last
    end

    def job_count
      @jobs.size
    end

    def jobs_for_queue(queue_name)
      @jobs.select { |job| job[:queue] == queue_name }
    end
  end

  # Mock helpers
  def allow(target)
    MockExpectation.new(target)
  end

  def double(name)
    MockDouble.new(name)
  end

  class MockExpectation
    def initialize(target)
      @target = target
    end

    def to(matcher)
      if matcher.is_a?(MockMatcher)
        matcher.apply_to(@target)
      end
    end
  end

  class MockMatcher
    def initialize(method_name)
      @method_name = method_name
    end

    def apply_to(target)
      # Simple mock implementation
      target.define_singleton_method(@method_name) do |*args, &block|
        block&.call(*args)
      end
    end
  end

  class MockDouble
    def initialize(name)
      @name = name
    end

    def method_missing(method_name, *args, &block)
      # Return self to allow method chaining
      if block_given?
        instance_eval(&block)
      else
        self
      end
    end

    def respond_to_missing?(method_name, include_private = false)
      true
    end
  end

  def receive(method_name)
    MockMatcher.new(method_name)
  end
end

# Global test context
include IntegrationsHelper
