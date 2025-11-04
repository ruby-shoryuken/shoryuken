#!/usr/bin/env ruby
# frozen_string_literal: true

# ActiveJob basic functionality integration test for Rails 7.1
# This test runs in complete isolation with its own Gemfile

require_relative '../../integrations_helper'

# Load required dependencies for this test
require 'active_job'
require 'shoryuken'
require 'active_job/queue_adapters/shoryuken_adapter'
require 'active_job/extensions'

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

class Rails71FeatureJob < ActiveJob::Base
  queue_as :rails71_features

  # Rails 7.1 introduced improvements to retry mechanisms
  retry_on StandardError, wait: :polynomially_longer, attempts: 5

  def perform(data)
    "Processed Rails 7.1 job: #{data}"
  end
end

# Test execution

run_test_suite "Basic Job Enqueuing Rails 7.1" do
  run_test "enqueues simple job with message" do
    job_capture = JobCapture.new
    job_capture.start_capturing

    SimpleTestJob.perform_later("Hello Rails 7.1", priority: "high")

    assert_equal(1, job_capture.job_count)

    job = job_capture.last_job
    message_body = job[:message_body]
    assert_equal("SimpleTestJob", message_body["job_class"])

    # Rails 7.1 specific: Check keyword argument serialization improvements
    args = message_body["arguments"]
    assert_equal("Hello Rails 7.1", args[0])
    assert_equal("high", args[1]["priority"])
  end

  run_test "handles Rails 7.1 retry mechanisms" do
    job_capture = JobCapture.new
    job_capture.start_capturing

    # Test Rails 7.1 specific retry configuration
    Rails71FeatureJob.perform_later("retry_test_data")

    job = job_capture.last_job
    message_body = job[:message_body]
    assert_equal("Rails71FeatureJob", message_body["job_class"])
    assert_equal(["retry_test_data"], message_body["arguments"])
  end
end

run_test_suite "Rails 7.1 Specific Features" do
  run_test "works with Rails 7.1 ActiveJob version" do
    # Check that we're running against Rails 7.1
    require 'active_job/version'
    version = ActiveJob::VERSION::STRING
    assert(version.start_with?('7.1'), "Expected Rails 7.1, got #{version}")
  end

  run_test "uses Rails 7.1 polynomially_longer retry strategy" do
    job_capture = JobCapture.new
    job_capture.start_capturing

    Rails71FeatureJob.perform_later("polynomial_retry")

    # Job should enqueue successfully with retry configuration
    assert_equal(1, job_capture.job_count)
  end
end

