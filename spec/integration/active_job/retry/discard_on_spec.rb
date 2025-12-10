# frozen_string_literal: true

# ActiveJob discard_on discards jobs that raise specific errors without retry

setup_localstack
setup_active_job

queue_name = DT.queue
create_test_queue(queue_name)

class DiscardOnTestJob < ActiveJob::Base
  discard_on ArgumentError

  def perform(should_fail)
    DT[:attempts] << { job_id: job_id, should_fail: should_fail }

    if should_fail
      raise ArgumentError, "This should be discarded"
    end

    DT[:successes] << { job_id: job_id }
  end
end

DiscardOnTestJob.queue_as(queue_name)

Shoryuken.add_group('default', 1)
Shoryuken.add_queue(queue_name, 1, 'default')
Shoryuken.register_worker(queue_name, Shoryuken::ActiveJob::JobWrapper)

failing_job = DiscardOnTestJob.perform_later(true)
success_job = DiscardOnTestJob.perform_later(false)

poll_queues_until(timeout: 30) { DT[:attempts].size >= 2 }

failing_attempts = DT[:attempts].select { |a| a[:job_id] == failing_job.job_id }
assert_equal(1, failing_attempts.size, "Discarded job should only attempt once")

failing_successes = DT[:successes].select { |s| s[:job_id] == failing_job.job_id }
assert_equal(0, failing_successes.size, "Discarded job should not succeed")

success_successes = DT[:successes].select { |s| s[:job_id] == success_job.job_id }
assert_equal(1, success_successes.size, "Non-failing job should succeed")
