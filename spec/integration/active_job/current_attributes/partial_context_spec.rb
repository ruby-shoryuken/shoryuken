# frozen_string_literal: true

# CurrentAttributes with partial values set preserve only set attributes during job execution

setup_localstack
setup_active_job

require 'active_support/current_attributes'
require 'shoryuken/active_job/current_attributes'

queue_name = DT.queue
create_test_queue(queue_name)

class TestCurrent < ActiveSupport::CurrentAttributes
  attribute :user_id, :tenant_id, :request_id
end

class RequestContext < ActiveSupport::CurrentAttributes
  attribute :locale, :timezone
end

Shoryuken::ActiveJob::CurrentAttributes.persist(TestCurrent, RequestContext)

class PartialContextTestJob < ActiveJob::Base
  def perform
    DT[:executions] << {
      user_id: TestCurrent.user_id,
      tenant_id: TestCurrent.tenant_id,
      request_id: TestCurrent.request_id,
      locale: RequestContext.locale,
      timezone: RequestContext.timezone
    }
  end
end

PartialContextTestJob.queue_as(queue_name)

Shoryuken.add_group('default', 1)
Shoryuken.add_queue(queue_name, 1, 'default')
Shoryuken.register_worker(queue_name, Shoryuken::ActiveJob::JobWrapper)

TestCurrent.user_id = 99
RequestContext.locale = 'fr-FR'

PartialContextTestJob.perform_later

TestCurrent.reset
RequestContext.reset

poll_queues_until(timeout: 30) { DT[:executions].size >= 1 }

result = DT[:executions].first
assert_equal(99, result[:user_id])
assert(result[:tenant_id].nil?)
assert(result[:request_id].nil?)
assert_equal('fr-FR', result[:locale])
assert(result[:timezone].nil?)
