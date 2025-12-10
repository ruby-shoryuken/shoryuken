#!/usr/bin/env ruby
# frozen_string_literal: true

# Scheduled ActiveJob integration test
# Tests jobs scheduled with set(wait:) are delivered after the delay

require 'shoryuken'
require 'active_job'
require 'active_job/queue_adapters/shoryuken_adapter'
require 'active_job/extensions'

setup_localstack
reset_shoryuken

queue_name = "test-scheduled-#{SecureRandom.uuid}"
create_test_queue(queue_name)

# Configure ActiveJob adapter
ActiveJob::Base.queue_adapter = :shoryuken

# Track job executions with timestamps
$scheduled_job_executions = Concurrent::Array.new
$enqueue_timestamps = Concurrent::Hash.new

# Define test job
class ScheduledTestJob < ActiveJob::Base
  def perform(label)
    $scheduled_job_executions << {
      label: label,
      job_id: job_id,
      executed_at: Time.now
    }
  end
end

# Configure the job to use our test queue
ScheduledTestJob.queue_as(queue_name)

# Register with Shoryuken
Shoryuken.add_group('default', 1)
Shoryuken.add_queue(queue_name, 1, 'default')
Shoryuken.register_worker(queue_name, Shoryuken::ActiveJob::JobWrapper)

# Enqueue an immediate job
immediate_enqueue_time = Time.now
ScheduledTestJob.perform_later('immediate')
$enqueue_timestamps['immediate'] = immediate_enqueue_time

# Enqueue a job with 3 second delay
delayed_enqueue_time = Time.now
ScheduledTestJob.set(wait: 3.seconds).perform_later('delayed_3s')
$enqueue_timestamps['delayed_3s'] = delayed_enqueue_time

# Enqueue a job with 5 second delay
delayed_5s_enqueue_time = Time.now
ScheduledTestJob.set(wait: 5.seconds).perform_later('delayed_5s')
$enqueue_timestamps['delayed_5s'] = delayed_5s_enqueue_time

# Wait for all jobs to be processed
poll_queues_until(timeout: 30) do
  $scheduled_job_executions.size >= 3
end

# Verify all jobs executed
assert_equal(3, $scheduled_job_executions.size, "Expected 3 job executions")

# Find each job's execution
immediate_job = $scheduled_job_executions.find { |e| e[:label] == 'immediate' }
delayed_3s_job = $scheduled_job_executions.find { |e| e[:label] == 'delayed_3s' }
delayed_5s_job = $scheduled_job_executions.find { |e| e[:label] == 'delayed_5s' }

assert(immediate_job, "Immediate job should have executed")
assert(delayed_3s_job, "3s delayed job should have executed")
assert(delayed_5s_job, "5s delayed job should have executed")

# Verify immediate job executed quickly (within 5 seconds of enqueue)
immediate_delay = immediate_job[:executed_at] - $enqueue_timestamps['immediate']
assert(immediate_delay < 10, "Immediate job should execute within 10 seconds, took #{immediate_delay}s")

# Verify delayed jobs executed after their delay
# Using 2 seconds tolerance for SQS delivery variation
delayed_3s_actual_delay = delayed_3s_job[:executed_at] - $enqueue_timestamps['delayed_3s']
assert(delayed_3s_actual_delay >= 2, "3s delayed job should execute after at least 2s, took #{delayed_3s_actual_delay}s")

delayed_5s_actual_delay = delayed_5s_job[:executed_at] - $enqueue_timestamps['delayed_5s']
assert(delayed_5s_actual_delay >= 4, "5s delayed job should execute after at least 4s, took #{delayed_5s_actual_delay}s")

# Verify ordering: immediate should execute before delayed jobs
assert(immediate_job[:executed_at] <= delayed_3s_job[:executed_at],
       "Immediate job should execute before 3s delayed job")
assert(delayed_3s_job[:executed_at] <= delayed_5s_job[:executed_at],
       "3s delayed job should execute before 5s delayed job")

delete_test_queue(queue_name)
