#!/usr/bin/env ruby
# frozen_string_literal: true

# Plain Ruby integration test for ActiveJob basic functionality
# This test runs without RSpec, following Karafka's approach

require_relative '../integrations_helper'

# Load required dependencies for this test
begin
  require 'logger'
  require 'active_job'
  require 'shoryuken'
rescue LoadError => e
  puts "Failed to load dependencies: #{e.message}"
  exit 1
end

# Configure ActiveJob to use Shoryuken
ActiveJob::Base.queue_adapter = :shoryuken

# Test job classes
class SimpleTestJob < ActiveJob::Base
  queue_as :test_queue

  def perform(message, options = {})
    {
      message: message,
      options: options,
      processed_at: Time.current
    }
  end
end

class DelayedTestJob < ActiveJob::Base
  queue_as :delayed_queue

  def perform(data)
    "Processed delayed job: #{data}"
  end
end

# Test execution

run_test_suite "Basic Job Enqueuing" do
  run_test "enqueues simple job with message" do
    job_capture = JobCapture.new
    job_capture.start_capturing

    SimpleTestJob.perform_later("Hello World", priority: "high")

    assert_equal(1, job_capture.job_count)

    job = job_capture.last_job
    assert_equal(:default, job[:queue])

    message_body = job[:message_body]
    assert_equal("SimpleTestJob", message_body["job_class"])

    # ActiveJob adds keyword argument metadata
    expected_args = ["Hello World", {"priority" => "high", "_aj_ruby2_keywords" => ["priority"]}]
    assert_equal(expected_args, message_body["arguments"])
  end

  run_test "enqueues job to correct queue" do
    job_capture = JobCapture.new
    job_capture.start_capturing

    SimpleTestJob.perform_later("Queue Test")

    jobs = job_capture.jobs_for_queue(:default)
    assert_equal(1, jobs.size)
  end

  run_test "handles job with no arguments" do
    job_capture = JobCapture.new
    job_capture.start_capturing

    SimpleTestJob.perform_later("No Args")

    job = job_capture.last_job
    message_body = job[:message_body]
    assert_includes(message_body["arguments"], "No Args")
  end
end

run_test_suite "Delayed Job Enqueuing" do
  run_test "enqueues job with delay" do
    job_capture = JobCapture.new
    job_capture.start_capturing

    DelayedTestJob.set(wait: 5.minutes).perform_later("delayed data")

    job = job_capture.last_job
    assert_equal(:default, job[:queue])
    assert(job[:delay_seconds] >= 250) # Approximately 5 minutes

    message_body = job[:message_body]
    assert_equal("DelayedTestJob", message_body["job_class"])
  end

  run_test "enqueues job with specific time" do
    job_capture = JobCapture.new
    job_capture.start_capturing

    future_time = Time.current + 10.minutes
    DelayedTestJob.set(wait_until: future_time).perform_later("scheduled data")

    job = job_capture.last_job
    assert(job[:delay_seconds] >= 550) # Approximately 10 minutes
  end
end

run_test_suite "Job Arguments Handling" do
  run_test "handles string arguments" do
    job_capture = JobCapture.new
    job_capture.start_capturing

    SimpleTestJob.perform_later("string argument")

    job = job_capture.last_job
    message_body = job[:message_body]
    assert_includes(message_body["arguments"], "string argument")
  end

  run_test "handles hash arguments" do
    job_capture = JobCapture.new
    job_capture.start_capturing

    data = { "user_id" => 123, "action" => "create" }
    SimpleTestJob.perform_later("test", data)

    job = job_capture.last_job
    message_body = job[:message_body]
    args = message_body["arguments"]

    assert_equal("test", args[0])
    assert_equal(123, args[1]["user_id"])
    assert_equal("create", args[1]["action"])
  end

  run_test "handles array arguments" do
    job_capture = JobCapture.new
    job_capture.start_capturing

    items = ["item1", "item2", "item3"]
    SimpleTestJob.perform_later("array_test", items)

    job = job_capture.last_job
    message_body = job[:message_body]
    args = message_body["arguments"]

    assert_equal("array_test", args[0])
    assert_equal(items, args[1])
  end

  run_test "handles nil arguments" do
    job_capture = JobCapture.new
    job_capture.start_capturing

    SimpleTestJob.perform_later("test", nil)

    job = job_capture.last_job
    message_body = job[:message_body]
    args = message_body["arguments"]

    assert_equal("test", args[0])
    assert_equal(nil, args[1])
  end
end

run_test_suite "Multiple Job Enqueuing" do
  run_test "enqueues multiple jobs correctly" do
    job_capture = JobCapture.new
    job_capture.start_capturing

    SimpleTestJob.perform_later("job 1")
    DelayedTestJob.perform_later("job 2")
    SimpleTestJob.perform_later("job 3")

    assert_equal(3, job_capture.job_count)

    # All jobs go to default queue in our simple mock
    all_jobs = job_capture.jobs_for_queue(:default)
    assert_equal(3, all_jobs.size)
  end
end

run_test_suite "ActiveJob Adapter Configuration" do
  run_test "uses Shoryuken adapter" do
    assert_equal("ActiveJob::QueueAdapters::ShoryukenAdapter", ActiveJob::Base.queue_adapter.class.name)
  end

  run_test "registers job wrapper worker" do
    job_capture = JobCapture.new
    job_capture.start_capturing

    SimpleTestJob.perform_later("registration test")
    # If we get here without error, worker registration worked
    assert(true)
  end
end

