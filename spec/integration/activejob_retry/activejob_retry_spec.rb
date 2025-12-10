# frozen_string_literal: true

# ActiveJob retry/discard integration test
# Tests that ActiveJob retry_on and discard_on work correctly with real SQS

setup_localstack
setup_active_job

queue_name = DT.queue
# Short visibility timeout for faster retries
create_test_queue(queue_name, attributes: { 'VisibilityTimeout' => '2' })

# Job that fails N times then succeeds
class RetryTestJob < ActiveJob::Base
  retry_on StandardError, wait: 0, attempts: 3

  def perform(fail_count_key)
    DT[:attempts] << { job_id: job_id, attempt: executions + 1, time: Time.now }

    # Fail until we've reached the expected number of failures
    if DT[:attempts].count { |a| a[:job_id] == job_id } < 3
      raise StandardError, "Simulated failure"
    end

    DT[:successes] << { job_id: job_id, final_attempt: executions + 1 }
  end
end

# Job that should be discarded on specific error
class DiscardTestJob < ActiveJob::Base
  discard_on ArgumentError

  def perform(should_fail)
    DT[:discard_attempts] << { job_id: job_id, time: Time.now }

    if should_fail
      raise ArgumentError, "This should be discarded"
    end

    DT[:discard_successes] << { job_id: job_id }
  end
end

RetryTestJob.queue_as(queue_name)
DiscardTestJob.queue_as(queue_name)

Shoryuken.add_group('default', 1)
Shoryuken.add_queue(queue_name, 1, 'default')
Shoryuken.register_worker(queue_name, Shoryuken::ActiveJob::JobWrapper)

# Test 1: Job that retries and eventually succeeds
retry_job = RetryTestJob.perform_later('test_retry')

# Test 2: Job that should be discarded
discard_job = DiscardTestJob.perform_later(true)

# Test 3: Job that succeeds without discard
success_job = DiscardTestJob.perform_later(false)

# Wait for processing
poll_queues_until(timeout: 30) do
  DT[:successes].size >= 1 &&
    DT[:discard_attempts].size >= 1 &&
    DT[:discard_successes].size >= 1
end

# Verify retry job attempted multiple times and eventually succeeded
assert(DT[:attempts].size >= 2, "Expected at least 2 retry attempts, got #{DT[:attempts].size}")
assert_equal(1, DT[:successes].size, "Expected 1 successful retry completion")

# Verify discard job was attempted once and discarded (no success recorded)
discard_job_attempts = DT[:discard_attempts].select { |a| a[:job_id] == discard_job.job_id }
assert_equal(1, discard_job_attempts.size, "Discarded job should only attempt once")
discard_job_successes = DT[:discard_successes].select { |s| s[:job_id] == discard_job.job_id }
assert_equal(0, discard_job_successes.size, "Discarded job should not succeed")

# Verify non-failing job succeeded
success_job_successes = DT[:discard_successes].select { |s| s[:job_id] == success_job.job_id }
assert_equal(1, success_job_successes.size, "Non-failing job should succeed")
