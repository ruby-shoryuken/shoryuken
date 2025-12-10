# frozen_string_literal: true

require 'active_job'
require 'active_job/queue_adapters/shoryuken_adapter'
require 'active_job/extensions'

# Full round-trip ActiveJob integration test
# Enqueues a job via ActiveJob → sends to LocalStack SQS → processes via Shoryuken → verifies execution

setup_localstack
reset_shoryuken
DT.clear

queue_name = DT.queue
create_test_queue(queue_name)

# Configure ActiveJob adapter
ActiveJob::Base.queue_adapter = :shoryuken

# Define test job
class RoundtripTestJob < ActiveJob::Base
  def perform(payload)
    DT[:executions] << {
      payload: payload,
      executed_at: Time.now,
      job_id: job_id
    }
  end
end

# Configure the job to use our test queue
RoundtripTestJob.queue_as(queue_name)

# Register with Shoryuken
Shoryuken.add_group('default', 1)
Shoryuken.add_queue(queue_name, 1, 'default')
Shoryuken.register_worker(queue_name, Shoryuken::ActiveJob::JobWrapper)

# Enqueue jobs via ActiveJob
RoundtripTestJob.perform_later('first_payload')
RoundtripTestJob.perform_later('second_payload')
RoundtripTestJob.perform_later({ key: 'complex', data: [1, 2, 3] })

# Wait for jobs to be processed
poll_queues_until(timeout: 30) do
  DT[:executions].size >= 3
end

# Verify all jobs executed
assert_equal(3, DT[:executions].size, "Expected 3 job executions, got #{DT[:executions].size}")

# Verify payloads were received correctly
payloads = DT[:executions].map { |e| e[:payload] }
assert_includes(payloads, 'first_payload')
assert_includes(payloads, 'second_payload')

complex_payload = payloads.find { |p| p.is_a?(Hash) }
assert(complex_payload, "Expected to find complex payload")
# Keys may be strings or symbols depending on serialization
key_value = complex_payload['key'] || complex_payload[:key]
data_value = complex_payload['data'] || complex_payload[:data]
assert_equal('complex', key_value)
assert_equal([1, 2, 3], data_value)

# Verify job IDs are present
job_ids = DT[:executions].map { |e| e[:job_id] }
assert(job_ids.all? { |id| id && !id.empty? }, "All jobs should have job IDs")
assert_equal(3, job_ids.uniq.size, "All job IDs should be unique")

delete_test_queue(queue_name)
