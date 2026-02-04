# frozen_string_literal: true

# Integration test for ActiveJob keyword arguments support
# Regression test for: https://github.com/ruby-shoryuken/shoryuken/issues/961
#
# In Shoryuken 7.0, the SQSSendMessageParametersSupport module's initialize method
# breaks keyword argument passing to ActiveJob jobs because it lacks ruby2_keywords.

setup_localstack
setup_active_job

queue_name = DT.queue
create_test_queue(queue_name)

# Job that accepts keyword arguments - this was broken in Shoryuken 7.0
class KeywordArgumentsTestJob < ActiveJob::Base
  def perform(name:, count:, enabled: false)
    DT[:executions] << {
      name: name,
      count: count,
      enabled: enabled,
      job_id: job_id
    }
  end
end

KeywordArgumentsTestJob.queue_as(queue_name)

Shoryuken.add_group('default', 1)
Shoryuken.add_queue(queue_name, 1, 'default')
Shoryuken.register_worker(queue_name, Shoryuken::ActiveJob::JobWrapper)

# Enqueue jobs with keyword arguments
# This is where the bug manifests - the job instantiation fails
KeywordArgumentsTestJob.perform_later(name: 'first', count: 1)
KeywordArgumentsTestJob.perform_later(name: 'second', count: 2, enabled: true)

poll_queues_until(timeout: 30) do
  DT[:executions].size >= 2
end

assert_equal(2, DT[:executions].size, "Expected 2 job executions, got #{DT[:executions].size}")

# Find the executions by name
first_exec = DT[:executions].find { |e| e[:name] == 'first' }
second_exec = DT[:executions].find { |e| e[:name] == 'second' }

assert(first_exec, "Expected to find 'first' job execution")
assert(second_exec, "Expected to find 'second' job execution")

# Verify keyword arguments were passed correctly
assert_equal('first', first_exec[:name])
assert_equal(1, first_exec[:count])
assert_equal(false, first_exec[:enabled])

assert_equal('second', second_exec[:name])
assert_equal(2, second_exec[:count])
assert_equal(true, second_exec[:enabled])

# Verify job IDs
job_ids = DT[:executions].map { |e| e[:job_id] }
assert(job_ids.all? { |id| id && !id.empty? }, "All jobs should have job IDs")
assert_equal(2, job_ids.uniq.size, "All job IDs should be unique")
