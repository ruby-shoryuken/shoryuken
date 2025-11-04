#!/usr/bin/env ruby
# frozen_string_literal: true

# ActiveJob basic functionality integration test for Rails 7.0
# This test runs in complete isolation with its own Gemfile

require_relative '../../integrations_helper'

# Load required dependencies for this test
begin
  # Rails 7.0 + Ruby 3.4 compatibility: require logger first
  require 'logger'
  require 'active_job'

  # Now load shoryuken - but the adapter might fail due to AbstractAdapter issue
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

run_test_suite "Basic Job Enqueuing Rails 7.0" do
  run_test "enqueues simple job with message" do
    job_capture = JobCapture.new
    job_capture.start_capturing

    SimpleTestJob.perform_later("Hello Rails 7.0", priority: "high")

    assert_equal(1, job_capture.job_count)

    job = job_capture.last_job
    message_body = job[:message_body]
    assert_equal("SimpleTestJob", message_body["job_class"])

    # Rails 7.0 specific: Check keyword argument serialization
    args = message_body["arguments"]
    assert_equal("Hello Rails 7.0", args[0])
    assert_equal("high", args[1]["priority"])
  end

  run_test "handles Rails 7.0 ActiveJob features" do
    job_capture = JobCapture.new
    job_capture.start_capturing

    # Test Rails 7.0 specific features
    DelayedTestJob.set(wait: 2.minutes).perform_later("rails70_data")

    job = job_capture.last_job
    assert(job[:delay_seconds] >= 100) # Approximately 2 minutes

    message_body = job[:message_body]
    assert_equal("DelayedTestJob", message_body["job_class"])
  end
end

run_test_suite "Rails 7.0 Specific Features" do
  run_test "works with Rails 7.0 ActiveJob version" do
    # Check that we're running against Rails 7.0
    require 'active_job/version'
    version = ActiveJob::VERSION::STRING
    assert(version.start_with?('7.0'), "Expected Rails 7.0, got #{version}")
  end

  run_test "adapter configuration for Rails 7.0" do
    adapter = ActiveJob::Base.queue_adapter
    assert_equal("ActiveJob::QueueAdapters::ShoryukenAdapter", adapter.class.name)
  end
end

