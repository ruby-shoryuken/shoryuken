# frozen_string_literal: true

# CurrentAttributes without any values set result in nil attributes during job execution

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

class EmptyContextTestJob < ActiveJob::Base
  def perform
    DT[:executions] << {
      user_id: TestCurrent.user_id,
      tenant_id: TestCurrent.tenant_id
    }
  end
end

EmptyContextTestJob.queue_as(queue_name)

Shoryuken.add_group('default', 1)
Shoryuken.add_queue(queue_name, 1, 'default')
Shoryuken.register_worker(queue_name, Shoryuken::ActiveJob::JobWrapper)

EmptyContextTestJob.perform_later

poll_queues_until(timeout: 30) { DT[:executions].size >= 1 }

result = DT[:executions].first
assert(result[:user_id].nil?)
assert(result[:tenant_id].nil?)
