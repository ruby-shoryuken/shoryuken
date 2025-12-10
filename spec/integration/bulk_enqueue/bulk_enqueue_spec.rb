# frozen_string_literal: true

# Bulk enqueue integration test
# Tests perform_all_later with the new enqueue_all method using SQS batch API

setup_localstack
setup_active_job

queue_name = DT.queue
create_test_queue(queue_name)

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

BulkTestJob.queue_as(queue_name)

Shoryuken.add_group('default', 1)
Shoryuken.add_queue(queue_name, 1, 'default')
Shoryuken.register_worker(queue_name, Shoryuken::ActiveJob::JobWrapper)

jobs = (1..15).map { |i| BulkTestJob.new(i, "payload_#{i}") }

# Use perform_all_later which should call enqueue_all
ActiveJob.perform_all_later(jobs)

successfully_enqueued_count = jobs.count(&:successfully_enqueued?)
assert_equal(15, successfully_enqueued_count, "Expected all 15 jobs to be marked as successfully enqueued")

poll_queues_until(timeout: 45) do
  DT[:executions].size >= 15
end

assert_equal(15, DT[:executions].size, "Expected 15 job executions, got #{DT[:executions].size}")

executed_indices = DT[:executions].map { |e| e[:index] }.sort
expected_indices = (1..15).to_a
assert_equal(expected_indices, executed_indices, "All job indices should be present")

DT[:executions].each do |execution|
  expected_data = "payload_#{execution[:index]}"
  assert_equal(expected_data, execution[:data], "Job #{execution[:index]} should have correct data")
end

job_ids = DT[:executions].map { |e| e[:job_id] }
assert_equal(15, job_ids.uniq.size, "All job IDs should be unique")
