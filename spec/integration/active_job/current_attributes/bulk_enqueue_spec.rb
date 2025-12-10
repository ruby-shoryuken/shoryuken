# frozen_string_literal: true

# CurrentAttributes are persisted correctly when using bulk enqueue (perform_all_later)

setup_localstack
setup_active_job

require 'active_support/current_attributes'
require 'shoryuken/active_job/current_attributes'

queue_name = DT.queue
create_test_queue(queue_name)

class TestCurrent < ActiveSupport::CurrentAttributes
  attribute :user_id, :tenant_id
end

Shoryuken::ActiveJob::CurrentAttributes.persist(TestCurrent)

class BulkCurrentAttributesTestJob < ActiveJob::Base
  def perform(index)
    DT[:executions] << {
      index: index,
      user_id: TestCurrent.user_id,
      tenant_id: TestCurrent.tenant_id
    }
  end
end

BulkCurrentAttributesTestJob.queue_as(queue_name)

Shoryuken.add_group('default', 1)
Shoryuken.add_queue(queue_name, 1, 'default')
Shoryuken.register_worker(queue_name, Shoryuken::ActiveJob::JobWrapper)

TestCurrent.user_id = 'bulk-user-123'
TestCurrent.tenant_id = 'bulk-tenant'

jobs = (1..3).map { |i| BulkCurrentAttributesTestJob.new(i) }
ActiveJob.perform_all_later(jobs)

TestCurrent.reset

poll_queues_until(timeout: 30) { DT[:executions].size >= 3 }

assert_equal(3, DT[:executions].size)
DT[:executions].each do |job|
  assert_equal('bulk-user-123', job[:user_id])
  assert_equal('bulk-tenant', job[:tenant_id])
end
