# frozen_string_literal: true

# CurrentAttributes with complex data types (hashes, arrays, symbols) are serialized and restored

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

class ComplexTypesTestJob < ActiveJob::Base
  def perform
    DT[:executions] << {
      user_id: TestCurrent.user_id,
      tenant_id: TestCurrent.tenant_id
    }
  end
end

ComplexTypesTestJob.queue_as(queue_name)

Shoryuken.add_group('default', 1)
Shoryuken.add_queue(queue_name, 1, 'default')
Shoryuken.register_worker(queue_name, Shoryuken::ActiveJob::JobWrapper)

TestCurrent.user_id = { role: :admin, permissions: [:read, :write, :delete] }
TestCurrent.tenant_id = [:tenant_a, :tenant_b]

ComplexTypesTestJob.perform_later

TestCurrent.reset

poll_queues_until(timeout: 30) { DT[:executions].size >= 1 }

result = DT[:executions].first

user_data = result[:user_id]
assert(user_data.is_a?(Hash))
role = user_data['role'] || user_data[:role]
assert_equal('admin', role.to_s)
permissions = user_data['permissions'] || user_data[:permissions]
assert_equal(3, permissions.size)

tenant_data = result[:tenant_id]
assert(tenant_data.is_a?(Array))
assert_equal(2, tenant_data.size)
