# frozen_string_literal: true

require 'active_job'
require 'active_job/queue_adapters/shoryuken_adapter'
require 'active_job/extensions'

# Bulk enqueue integration test
# Tests perform_all_later with the new enqueue_all method using SQS batch API

setup_localstack
reset_shoryuken

queue_name = DT.queue
create_test_queue(queue_name)

# Configure ActiveJob adapter
ActiveJob::Base.queue_adapter = :shoryuken

# Define test job
class BulkTestJob < ActiveJob::Base
  def perform(index, data)
    DT[:executions] << {
      index: index,
      data: data,
      job_id: job_id,
      executed_at: Time.now
    }
  end
end

# Configure the job to use our test queue
BulkTestJob.queue_as(queue_name)

# Register with Shoryuken
Shoryuken.add_group('default', 1)
Shoryuken.add_queue(queue_name, 1, 'default')
Shoryuken.register_worker(queue_name, Shoryuken::ActiveJob::JobWrapper)

# Create multiple jobs for bulk enqueue
jobs = (1..15).map { |i| BulkTestJob.new(i, "payload_#{i}") }

# Use perform_all_later which should call enqueue_all
ActiveJob.perform_all_later(jobs)

# Verify jobs were marked as successfully enqueued
successfully_enqueued_count = jobs.count(&:successfully_enqueued?)
assert_equal(15, successfully_enqueued_count, "Expected all 15 jobs to be marked as successfully enqueued")

# Wait for all jobs to be processed
poll_queues_until(timeout: 45) do
  DT[:executions].size >= 15
end

# Verify all jobs executed
assert_equal(15, DT[:executions].size, "Expected 15 job executions, got #{DT[:executions].size}")

# Verify all indices were received
executed_indices = DT[:executions].map { |e| e[:index] }.sort
expected_indices = (1..15).to_a
assert_equal(expected_indices, executed_indices, "All job indices should be present")

# Verify data payloads
DT[:executions].each do |execution|
  expected_data = "payload_#{execution[:index]}"
  assert_equal(expected_data, execution[:data], "Job #{execution[:index]} should have correct data")
end

# Verify unique job IDs
job_ids = DT[:executions].map { |e| e[:job_id] }
assert_equal(15, job_ids.uniq.size, "All job IDs should be unique")

delete_test_queue(queue_name)
