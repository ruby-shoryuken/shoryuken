#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative '../integrations_helper'

begin
  require 'active_job'
  require 'shoryuken'
rescue LoadError => e
  puts "Failed to load dependencies: #{e.message}"
  exit 1
end

ActiveJob::Base.queue_adapter = :shoryuken

class ModernJob < ActiveJob::Base
  queue_as :modern
  retry_on StandardError, wait: :polynomially_longer, attempts: 5
  discard_on ArgumentError

  def perform(data)
    case data['action']
    when 'succeed'
      "Processed: #{data['payload']}"
    when 'fail'
      raise StandardError, 'Test error'
    end
  end
end

class TransactionJob < ActiveJob::Base
  queue_as :transactions

  def perform(operation_id)
    "Executed operation: #{operation_id}"
  end
end

class ConfigurableJob < ActiveJob::Base
  def self.queue_name_prefix
    'myapp'
  end

  queue_as :development_default

  def perform(data)
    "Processed: #{data}"
  end
end

run_test_suite "Rails 7+ Features" do
  run_test "serializes jobs with retry configuration" do
    job_capture = JobCapture.new
    job_capture.start_capturing

    ModernJob.perform_later({ 'action' => 'succeed', 'payload' => 'test data' })

    assert_equal(1, job_capture.job_count)
    job = job_capture.last_job
    message_body = job[:message_body]
    assert_equal('ModernJob', message_body['job_class'])
    assert(message_body['arguments'].is_a?(Array))
  end
end

run_test_suite "Transaction Support" do
  run_test "supports enqueue_after_transaction_commit" do
    adapter = ActiveJob::QueueAdapters::ShoryukenAdapter.new
    assert_equal(true, adapter.enqueue_after_transaction_commit?)
  end

  run_test "handles transaction-aware enqueueing" do
    job_capture = JobCapture.new
    job_capture.start_capturing

    TransactionJob.perform_later('transaction-op-123')

    job = job_capture.last_job
    message_body = job[:message_body]
    assert_equal('TransactionJob', message_body['job_class'])
    assert_equal(['transaction-op-123'], message_body['arguments'])
  end
end

run_test_suite "Queue Configuration" do
  run_test "handles dynamic queue name resolution" do
    job_capture = JobCapture.new
    job_capture.start_capturing

    ConfigurableJob.perform_later('test data')

    job = job_capture.last_job
    message_body = job[:message_body]
    assert_equal('myapp_development_default', message_body['queue_name'])
  end
end

run_test_suite "Serialization Compatibility" do
  run_test "maintains serialization format compatibility" do
    job = ModernJob.new({ 'action' => 'succeed', 'payload' => 'test' })
    serialized = job.serialize

    assert(serialized.include?('job_class'))
    assert(serialized.include?('job_id'))
    assert(serialized.include?('queue_name'))
    assert(serialized.include?('arguments'))

    assert_equal(String, JSON.generate(serialized).class)
  end
end

run_test_suite "Performance" do
  run_test "handles multiple job enqueueing" do
    job_capture = JobCapture.new
    job_capture.start_capturing

    5.times do |i|
      ModernJob.perform_later({ 'action' => 'succeed', 'payload' => "job-#{i}" })
    end

    assert_equal(5, job_capture.job_count)
  end

  run_test "maintains job data integrity" do
    job_data = { 'action' => 'succeed', 'payload' => 'integrity-test' }

    job_capture = JobCapture.new
    job_capture.start_capturing

    ModernJob.perform_later(job_data)

    job = job_capture.last_job
    message_body = job[:message_body]

    args_data = message_body['arguments'].first
    assert_equal('succeed', args_data['action'])
    assert_equal('integrity-test', args_data['payload'])

    assert(message_body['job_id'].match?(/\A[0-9a-f-]{36}\z/))

    enqueued_time = Time.parse(message_body['enqueued_at'])
    assert(enqueued_time > Time.current - 60)
  end
end
