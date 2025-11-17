#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative '../../integrations_helper'

begin
  require 'active_job'
  require 'shoryuken'
rescue LoadError => e
  puts "Failed to load dependencies: #{e.message}"
  exit 1
end

ActiveJob::Base.queue_adapter = :shoryuken

class RetryableJob < ActiveJob::Base
  queue_as :default
  retry_on StandardError, wait: 1.second, attempts: 3

  def perform(should_fail = true)
    raise StandardError, 'Job failed!' if should_fail
    'Job succeeded!'
  end
end

class DiscardableJob < ActiveJob::Base
  queue_as :default
  discard_on ArgumentError

  def perform(should_fail = false)
    raise ArgumentError, 'Invalid argument' if should_fail
    'Job succeeded!'
  end
end

class LargePayloadJob < ActiveJob::Base
  queue_as :default

  def perform(data)
    "Processed #{data.length} bytes"
  end
end

run_test_suite "Error Handling" do
  run_test "enqueues jobs with retry configuration" do
    job_capture = JobCapture.new
    job_capture.start_capturing

    RetryableJob.perform_later(false)

    assert_equal(1, job_capture.job_count)
    job = job_capture.last_job
    message_body = job[:message_body]
    assert_equal('RetryableJob', message_body['job_class'])
    assert_equal([false], message_body['arguments'])
  end

  run_test "enqueues jobs with discard configuration" do
    job_capture = JobCapture.new
    job_capture.start_capturing

    DiscardableJob.perform_later(false)

    assert_equal(1, job_capture.job_count)
    job = job_capture.last_job
    message_body = job[:message_body]
    assert_equal('DiscardableJob', message_body['job_class'])
  end
end

run_test_suite "Job Processing" do
  run_test "processes jobs through JobWrapper" do
    sqs_msg = Object.new
    sqs_msg.define_singleton_method(:attributes) { { 'ApproximateReceiveCount' => '1' } }
    sqs_msg.define_singleton_method(:message_id) { 'test-message-id' }

    job_data = {
      'job_class' => 'RetryableJob',
      'job_id' => 'test-job-id',
      'queue_name' => 'default',
      'arguments' => [false],
      'executions' => 0,
      'enqueued_at' => Time.current.iso8601
    }

    wrapper = Shoryuken::ActiveJob::JobWrapper.new

    # Mock ActiveJob::Base.execute
    executed_job_data = nil
    ActiveJob::Base.define_singleton_method(:execute) do |job_data_arg|
      executed_job_data = job_data_arg
    end

    wrapper.perform(sqs_msg, job_data)

    assert_equal(job_data.merge({ 'executions' => 0 }), executed_job_data)
  end

  run_test "handles retry attempts correctly" do
    sqs_msg_with_retries = Object.new
    sqs_msg_with_retries.define_singleton_method(:attributes) { { 'ApproximateReceiveCount' => '3' } }
    sqs_msg_with_retries.define_singleton_method(:message_id) { 'test-message-id' }

    job_data = {
      'job_class' => 'RetryableJob',
      'job_id' => 'test-job-id',
      'queue_name' => 'default',
      'arguments' => [true],
      'executions' => 2,
      'enqueued_at' => Time.current.iso8601
    }

    wrapper = Shoryuken::ActiveJob::JobWrapper.new

    executed_job_data = nil
    ActiveJob::Base.define_singleton_method(:execute) do |job_data_arg|
      executed_job_data = job_data_arg
    end

    wrapper.perform(sqs_msg_with_retries, job_data)

    # Executions should be calculated from receive count - 1
    assert_equal(2, executed_job_data['executions'])
  end
end

run_test_suite "Message Size Limits" do
  run_test "handles normal sized payloads" do
    job_capture = JobCapture.new
    job_capture.start_capturing

    normal_data = 'x' * 1000  # 1KB
    LargePayloadJob.perform_later(normal_data)

    assert_equal(1, job_capture.job_count)
    job = job_capture.last_job
    message_body = job[:message_body]
    assert_equal('LargePayloadJob', message_body['job_class'])
  end

  run_test "handles medium sized payloads" do
    job_capture = JobCapture.new
    job_capture.start_capturing

    medium_data = 'x' * 100_000  # 100KB
    LargePayloadJob.perform_later(medium_data)

    assert_equal(1, job_capture.job_count)
    job = job_capture.last_job
    message_body = job[:message_body]
    args_data = message_body['arguments'].first
    assert_equal(100_000, args_data.length)
  end
end

run_test_suite "Adapter Lifecycle" do
  run_test "maintains consistent adapter instance" do
    adapter1 = ActiveJob::QueueAdapters::ShoryukenAdapter.instance
    adapter2 = ActiveJob::QueueAdapters::ShoryukenAdapter.instance

    assert_equal(adapter1.object_id, adapter2.object_id)
    assert_equal("ActiveJob::QueueAdapters::ShoryukenAdapter", adapter1.class.name)
  end

  run_test "supports both class and instance methods" do
    # Test class methods
    assert(ActiveJob::QueueAdapters::ShoryukenAdapter.respond_to?(:enqueue))
    assert(ActiveJob::QueueAdapters::ShoryukenAdapter.respond_to?(:enqueue_at))

    # Test instance methods
    adapter = ActiveJob::QueueAdapters::ShoryukenAdapter.new
    assert(adapter.respond_to?(:enqueue))
    assert(adapter.respond_to?(:enqueue_at))
    assert(adapter.respond_to?(:enqueue_after_transaction_commit?))
  end
end

run_test_suite "Worker Registration" do
  run_test "registers JobWrapper for each queue" do
    registered_workers = []

    Shoryuken.define_singleton_method(:register_worker) do |queue_name, worker_class|
      registered_workers << [queue_name, worker_class]
    end

    # Mock queue
    queue_mock = Object.new
    queue_mock.define_singleton_method(:fifo?) { false }
    queue_mock.define_singleton_method(:send_message) { |params| nil }

    Shoryuken::Client.define_singleton_method(:queues) do |queue_name = nil|
      queue_mock
    end

    RetryableJob.perform_later(false)

    assert_equal(1, registered_workers.length)
    queue_name, worker_class = registered_workers.first
    assert_equal('default', queue_name)
    assert_equal(Shoryuken::ActiveJob::JobWrapper, worker_class)
  end

  run_test "configures JobWrapper with correct options" do
    wrapper_class = Shoryuken::ActiveJob::JobWrapper
    options = wrapper_class.get_shoryuken_options

    assert_equal(:json, options['body_parser'])
    assert_equal(true, options['auto_delete'])
  end
end