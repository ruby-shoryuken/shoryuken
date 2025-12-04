#!/usr/bin/env ruby
# frozen_string_literal: true

# ActiveJob adapter integration tests for Rails 8.0
# Tests basic ActiveJob functionality with Shoryuken adapter

begin
  require 'active_job'
  require 'shoryuken'
rescue LoadError => e
  puts "Failed to load dependencies: #{e.message}"
  exit 1
end

ActiveJob::Base.queue_adapter = :shoryuken

class EmailJob < ActiveJob::Base
  queue_as :default

  def perform(user_id, message)
    { user_id: user_id, message: message, sent_at: Time.current }
  end
end

class DataProcessingJob < ActiveJob::Base
  queue_as :high_priority

  def perform(data_file)
    "Processed: #{data_file}"
  end
end

class SerializationJob < ActiveJob::Base
  queue_as :default

  def perform(complex_data)
    complex_data.transform_values(&:upcase)
  end
end

class NoArgJob < ActiveJob::Base
  queue_as :default
  def perform; end
end

run_test_suite "ActiveJob Adapter Integration (Rails 8.0)" do
  run_test "sets up adapter correctly" do
    adapter = ActiveJob::Base.queue_adapter
    assert_equal("ActiveJob::QueueAdapters::ShoryukenAdapter", adapter.class.name)
  end

  run_test "maintains adapter singleton" do
    instance1 = ActiveJob::QueueAdapters::ShoryukenAdapter.instance
    instance2 = ActiveJob::QueueAdapters::ShoryukenAdapter.instance
    assert_equal(instance1.object_id, instance2.object_id)
  end

  run_test "supports transaction commit hook" do
    adapter = ActiveJob::QueueAdapters::ShoryukenAdapter.new
    assert(adapter.respond_to?(:enqueue_after_transaction_commit?))
    assert_equal(true, adapter.enqueue_after_transaction_commit?)
  end
end

run_test_suite "Job Enqueuing" do
  run_test "enqueues simple job" do
    job_capture = JobCapture.new
    job_capture.start_capturing

    EmailJob.perform_later(1, 'Hello World')

    assert_equal(1, job_capture.job_count)
    job = job_capture.last_job
    message_body = job[:message_body]
    assert_equal('EmailJob', message_body['job_class'])
    assert_equal([1, 'Hello World'], message_body['arguments'])
    assert_equal('default', message_body['queue_name'])
  end

  run_test "enqueues to different queues" do
    job_capture = JobCapture.new
    job_capture.start_capturing

    DataProcessingJob.perform_later('large_dataset.csv')

    assert_equal(1, job_capture.job_count)
    job = job_capture.last_job
    message_body = job[:message_body]
    assert_equal('DataProcessingJob', message_body['job_class'])
    assert_equal('high_priority', message_body['queue_name'])
  end

  run_test "schedules jobs for future execution" do
    job_capture = JobCapture.new
    job_capture.start_capturing

    EmailJob.set(wait: 5.minutes).perform_later('cleanup')

    job = job_capture.last_job
    message_body = job[:message_body]
    assert_equal('EmailJob', message_body['job_class'])
    assert(job[:delay_seconds] > 0)
    assert(job[:delay_seconds] >= 250)
  end

  run_test "handles complex data serialization" do
    complex_data = {
      'user' => { 'name' => 'John', 'age' => 30 },
      'preferences' => ['email', 'sms'],
      'metadata' => { 'created_at' => Time.current.iso8601 }
    }

    job_capture = JobCapture.new
    job_capture.start_capturing

    SerializationJob.perform_later(complex_data)

    job = job_capture.last_job
    message_body = job[:message_body]
    assert_equal('SerializationJob', message_body['job_class'])

    args_data = message_body['arguments'].first
    assert_equal('John', args_data['user']['name'])
    assert_equal(30, args_data['user']['age'])
    assert_equal(['email', 'sms'], args_data['preferences'])
    assert(args_data['metadata']['created_at'].is_a?(String))
  end
end

run_test_suite "Message Attributes" do
  run_test "sets required Shoryuken message attributes" do
    job_capture = JobCapture.new
    job_capture.start_capturing

    EmailJob.perform_later(1, 'Attributes test')

    job = job_capture.last_job
    attributes = job[:message_attributes]
    expected_shoryuken_class = {
      string_value: "Shoryuken::ActiveJob::JobWrapper",
      data_type: 'String'
    }
    assert_equal(expected_shoryuken_class, attributes['shoryuken_class'])
  end
end

run_test_suite "Delay and Scheduling" do
  run_test "calculates delay correctly" do
    job_capture = JobCapture.new
    job_capture.start_capturing

    future_time = Time.current + 5.minutes
    EmailJob.set(wait_until: future_time).perform_later(1, 'Scheduled email')

    job = job_capture.last_job
    assert(job[:delay_seconds] >= 295 && job[:delay_seconds] <= 305)
  end

  run_test "handles immediate scheduling" do
    job_capture = JobCapture.new
    job_capture.start_capturing

    adapter = ActiveJob::QueueAdapters::ShoryukenAdapter.new
    job = EmailJob.new(1, 'Immediate')
    adapter.enqueue_at(job, Time.current.to_f)

    captured_job = job_capture.last_job
    assert_equal(0, captured_job[:delay_seconds])
  end
end

run_test_suite "Edge Cases" do
  run_test "handles jobs with nil arguments" do
    job_capture = JobCapture.new
    job_capture.start_capturing

    EmailJob.perform_later(nil, nil)

    job = job_capture.last_job
    message_body = job[:message_body]
    assert_equal([nil, nil], message_body['arguments'])
  end

  run_test "handles empty argument lists" do
    job_capture = JobCapture.new
    job_capture.start_capturing

    NoArgJob.perform_later

    job = job_capture.last_job
    message_body = job[:message_body]
    assert_equal([], message_body['arguments'])
  end
end

run_test_suite "Serialization" do
  run_test "maintains ActiveJob serialization format" do
    job = EmailJob.new(1, 'Serialization test')
    serialized = job.serialize

    assert_equal('EmailJob', serialized['job_class'])
    assert_equal(job.job_id, serialized['job_id'])
    assert_equal('default', serialized['queue_name'])
    assert_equal([1, 'Serialization test'], serialized['arguments'])
    assert(serialized.key?('enqueued_at'))
  end
end
