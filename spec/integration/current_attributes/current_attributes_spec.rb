# frozen_string_literal: true

# CurrentAttributes integration tests
# Tests that CurrentAttributes flow from enqueue to job execution

setup_localstack
setup_active_job

require 'active_support/current_attributes'
require 'shoryuken/active_job/current_attributes'

queue_name = DT.queue
create_test_queue(queue_name)

# Define first CurrentAttributes class
class TestCurrent < ActiveSupport::CurrentAttributes
  attribute :user_id, :tenant_id, :request_id
end

# Define second CurrentAttributes class for multi-class testing
class RequestContext < ActiveSupport::CurrentAttributes
  attribute :locale, :timezone, :trace_id
end

# Register both CurrentAttributes classes for persistence
Shoryuken::ActiveJob::CurrentAttributes.persist(TestCurrent, RequestContext)

# Define test job that captures current attributes
class CurrentAttributesTestJob < ActiveJob::Base
  def perform(label)
    DT[:executions] << {
      label: label,
      user_id: TestCurrent.user_id,
      tenant_id: TestCurrent.tenant_id,
      request_id: TestCurrent.request_id,
      locale: RequestContext.locale,
      timezone: RequestContext.timezone,
      trace_id: RequestContext.trace_id,
      job_id: job_id
    }
  end
end

# Define job that tests complex data types
class ComplexDataJob < ActiveJob::Base
  def perform(label)
    DT[:complex_executions] << {
      label: label,
      user_id: TestCurrent.user_id,
      tenant_id: TestCurrent.tenant_id,
      job_id: job_id
    }
  end
end

# Define job that raises an error
class ErrorJob < ActiveJob::Base
  def perform(label)
    DT[:error_executions] << {
      label: label,
      user_id: TestCurrent.user_id,
      job_id: job_id
    }
    raise StandardError, "Intentional error for testing"
  end
end

# Configure jobs to use our test queue
CurrentAttributesTestJob.queue_as(queue_name)
ComplexDataJob.queue_as(queue_name)
ErrorJob.queue_as(queue_name)

# Register with Shoryuken
Shoryuken.add_group('default', 1)
Shoryuken.add_queue(queue_name, 1, 'default')
Shoryuken.register_worker(queue_name, Shoryuken::ActiveJob::JobWrapper)

# ============================================================================
# Test 1: Basic CurrentAttributes persistence
# ============================================================================

TestCurrent.user_id = 42
TestCurrent.tenant_id = 'acme-corp'
TestCurrent.request_id = 'req-123-abc'
RequestContext.locale = 'en-US'
RequestContext.timezone = 'America/New_York'
RequestContext.trace_id = 'trace-xyz-789'

CurrentAttributesTestJob.perform_later('with_full_context')

# Clear to prove they're restored from job payload
TestCurrent.reset
RequestContext.reset

# ============================================================================
# Test 2: Job without context (empty CurrentAttributes)
# ============================================================================

CurrentAttributesTestJob.perform_later('without_context')

# ============================================================================
# Test 3: Partial context (only some attributes set)
# ============================================================================

TestCurrent.user_id = 99
# tenant_id and request_id are nil
RequestContext.locale = 'fr-FR'
# timezone and trace_id are nil

CurrentAttributesTestJob.perform_later('partial_context')

TestCurrent.reset
RequestContext.reset

# ============================================================================
# Test 4: Complex data types (symbols, arrays, hashes)
# ============================================================================

TestCurrent.user_id = { role: :admin, permissions: [:read, :write, :delete] }
TestCurrent.tenant_id = [:tenant_a, :tenant_b]

ComplexDataJob.perform_later('complex_types')

TestCurrent.reset

# ============================================================================
# Test 5: Bulk enqueue with CurrentAttributes
# ============================================================================

TestCurrent.user_id = 'bulk-user-123'
TestCurrent.tenant_id = 'bulk-tenant'

jobs = (1..3).map { |i| CurrentAttributesTestJob.new("bulk_#{i}") }
ActiveJob.perform_all_later(jobs)

TestCurrent.reset

# ============================================================================
# Wait for all jobs to be processed
# ============================================================================

poll_queues_until(timeout: 45) do
  DT[:executions].size >= 6 && DT[:complex_executions].size >= 1
end

# ============================================================================
# Assertions
# ============================================================================

# Test 1: Full context preserved
full_context = DT[:executions].find { |e| e[:label] == 'with_full_context' }
assert(full_context, "Job with full context should have executed")
assert_equal(42, full_context[:user_id], "user_id should be persisted")
assert_equal('acme-corp', full_context[:tenant_id], "tenant_id should be persisted")
assert_equal('req-123-abc', full_context[:request_id], "request_id should be persisted")
assert_equal('en-US', full_context[:locale], "locale should be persisted from second CurrentAttributes")
assert_equal('America/New_York', full_context[:timezone], "timezone should be persisted")
assert_equal('trace-xyz-789', full_context[:trace_id], "trace_id should be persisted")

# Test 2: No context (nil attributes)
no_context = DT[:executions].find { |e| e[:label] == 'without_context' }
assert(no_context, "Job without context should have executed")
assert(no_context[:user_id].nil?, "user_id should be nil")
assert(no_context[:tenant_id].nil?, "tenant_id should be nil")
assert(no_context[:locale].nil?, "locale should be nil")

# Test 3: Partial context
partial = DT[:executions].find { |e| e[:label] == 'partial_context' }
assert(partial, "Job with partial context should have executed")
assert_equal(99, partial[:user_id], "user_id should be persisted")
assert(partial[:tenant_id].nil?, "tenant_id should be nil (not set)")
assert_equal('fr-FR', partial[:locale], "locale should be persisted")
assert(partial[:timezone].nil?, "timezone should be nil (not set)")

# Test 4: Complex data types
complex = DT[:complex_executions].find { |e| e[:label] == 'complex_types' }
assert(complex, "Job with complex types should have executed")
# ActiveJob serialization converts symbol keys to strings
user_data = complex[:user_id]
assert(user_data.is_a?(Hash), "user_id should be a hash")
role = user_data['role'] || user_data[:role]
assert_equal('admin', role.to_s, "role should be admin")
permissions = user_data['permissions'] || user_data[:permissions]
assert_equal(3, permissions.size, "should have 3 permissions")
tenant_data = complex[:tenant_id]
assert(tenant_data.is_a?(Array), "tenant_id should be an array")
assert_equal(2, tenant_data.size, "should have 2 tenants")

# Test 5: Bulk enqueue
bulk_jobs = DT[:executions].select { |e| e[:label].to_s.start_with?('bulk_') }
assert_equal(3, bulk_jobs.size, "All 3 bulk jobs should have executed")
bulk_jobs.each do |job|
  assert_equal('bulk-user-123', job[:user_id], "Bulk job should have user_id")
  assert_equal('bulk-tenant', job[:tenant_id], "Bulk job should have tenant_id")
end

# Verify CurrentAttributes were reset after all job executions
assert(TestCurrent.user_id.nil?, "CurrentAttributes should be reset after execution")
assert(RequestContext.locale.nil?, "RequestContext should be reset after execution")
