# frozen_string_literal: true

# CurrentAttributes with full context are persisted and restored during job execution

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
  attribute :locale, :timezone, :trace_id
end

Shoryuken::ActiveJob::CurrentAttributes.persist(TestCurrent, RequestContext)

class FullContextTestJob < ActiveJob::Base
  def perform
    DT[:executions] << {
      user_id: TestCurrent.user_id,
      tenant_id: TestCurrent.tenant_id,
      request_id: TestCurrent.request_id,
      locale: RequestContext.locale,
      timezone: RequestContext.timezone,
      trace_id: RequestContext.trace_id
    }
  end
end

FullContextTestJob.queue_as(queue_name)

Shoryuken.add_group('default', 1)
Shoryuken.add_queue(queue_name, 1, 'default')
Shoryuken.register_worker(queue_name, Shoryuken::ActiveJob::JobWrapper)

TestCurrent.user_id = 42
TestCurrent.tenant_id = 'acme-corp'
TestCurrent.request_id = 'req-123-abc'
RequestContext.locale = 'en-US'
RequestContext.timezone = 'America/New_York'
RequestContext.trace_id = 'trace-xyz-789'

FullContextTestJob.perform_later

TestCurrent.reset
RequestContext.reset

poll_queues_until(timeout: 30) { DT[:executions].size >= 1 }

result = DT[:executions].first
assert_equal(42, result[:user_id])
assert_equal('acme-corp', result[:tenant_id])
assert_equal('req-123-abc', result[:request_id])
assert_equal('en-US', result[:locale])
assert_equal('America/New_York', result[:timezone])
assert_equal('trace-xyz-789', result[:trace_id])
