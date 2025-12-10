#!/usr/bin/env ruby
# frozen_string_literal: true

# This spec tests error handling including retry configuration,
# discard configuration, and job processing through JobWrapper.

require 'active_job'
require 'shoryuken'

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

# Test enqueuing job with retry configuration
job_capture = JobCapture.new
job_capture.start_capturing

RetryableJob.perform_later(false)

assert_equal(1, job_capture.job_count)
job = job_capture.last_job
message_body = job[:message_body]
assert_equal('RetryableJob', message_body['job_class'])
assert_equal([false], message_body['arguments'])

# Test enqueuing job with discard configuration
job_capture2 = JobCapture.new
job_capture2.start_capturing

DiscardableJob.perform_later(false)

assert_equal(1, job_capture2.job_count)
job2 = job_capture2.last_job
message_body2 = job2[:message_body]
assert_equal('DiscardableJob', message_body2['job_class'])

# Test JobWrapper configuration
wrapper_class = Shoryuken::ActiveJob::JobWrapper
options = wrapper_class.get_shoryuken_options

assert_equal(:json, options['body_parser'])
assert_equal(true, options['auto_delete'])
