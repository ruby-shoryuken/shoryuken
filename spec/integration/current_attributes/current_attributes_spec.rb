# frozen_string_literal: true

require 'active_job'
require 'active_job/queue_adapters/shoryuken_adapter'
require 'active_job/extensions'
require 'active_support/current_attributes'
require 'shoryuken/active_job/current_attributes'

# CurrentAttributes integration test
# Tests that CurrentAttributes flow from enqueue to job execution

setup_localstack
reset_shoryuken

queue_name = DT.queue
create_test_queue(queue_name)

# Configure ActiveJob adapter
ActiveJob::Base.queue_adapter = :shoryuken

# Define CurrentAttributes class
class TestCurrent < ActiveSupport::CurrentAttributes
  attribute :user_id, :tenant_id, :request_id
end

# Register CurrentAttributes for persistence
Shoryuken::ActiveJob::CurrentAttributes.persist(TestCurrent)

# Define test job that captures current attributes
class CurrentAttributesTestJob < ActiveJob::Base
  def perform(label)
    DT[:executions] << {
      label: label,
      user_id: TestCurrent.user_id,
      tenant_id: TestCurrent.tenant_id,
      request_id: TestCurrent.request_id,
      job_id: job_id
    }
  end
end

# Configure the job to use our test queue
CurrentAttributesTestJob.queue_as(queue_name)

# Register with Shoryuken
Shoryuken.add_group('default', 1)
Shoryuken.add_queue(queue_name, 1, 'default')
Shoryuken.register_worker(queue_name, Shoryuken::ActiveJob::JobWrapper)

# Set current attributes and enqueue job
TestCurrent.user_id = 42
TestCurrent.tenant_id = 'acme-corp'
TestCurrent.request_id = 'req-123-abc'

CurrentAttributesTestJob.perform_later('with_context')

# Clear current attributes to prove they're restored from job payload
TestCurrent.reset

# Enqueue another job without context
CurrentAttributesTestJob.perform_later('without_context')

# Wait for jobs to be processed
poll_queues_until(timeout: 30) do
  DT[:executions].size >= 2
end

# Verify both jobs executed
assert_equal(2, DT[:executions].size, "Expected 2 job executions")

# Find each job's execution
with_context = DT[:executions].find { |e| e[:label] == 'with_context' }
without_context = DT[:executions].find { |e| e[:label] == 'without_context' }

assert(with_context, "Job with context should have executed")
assert(without_context, "Job without context should have executed")

# Verify CurrentAttributes were persisted for the first job
assert_equal(42, with_context[:user_id], "user_id should be persisted")
assert_equal('acme-corp', with_context[:tenant_id], "tenant_id should be persisted")
assert_equal('req-123-abc', with_context[:request_id], "request_id should be persisted")

# Verify second job has nil attributes (was enqueued after reset)
assert(without_context[:user_id].nil?, "user_id should be nil for job without context")
assert(without_context[:tenant_id].nil?, "tenant_id should be nil for job without context")
assert(without_context[:request_id].nil?, "request_id should be nil for job without context")

# Verify CurrentAttributes were reset after job execution
assert(TestCurrent.user_id.nil?, "CurrentAttributes should be reset after execution")

delete_test_queue(queue_name)
