# frozen_string_literal: true

# ActiveJob retry_on re-enqueues failed jobs until they succeed or exhaust attempts

setup_localstack
setup_active_job

queue_name = DT.queue
create_test_queue(queue_name, attributes: { 'VisibilityTimeout' => '2' })

class RetryOnTestJob < ActiveJob::Base
  retry_on StandardError, wait: 0, attempts: 3

  def perform
    DT[:attempts] << { job_id: job_id, attempt: executions + 1, time: Time.now }

    if DT[:attempts].count { |a| a[:job_id] == job_id } < 3
      raise StandardError, "Simulated failure"
    end

    DT[:successes] << { job_id: job_id, final_attempt: executions + 1 }
  end
end

RetryOnTestJob.queue_as(queue_name)

Shoryuken.add_group('default', 1)
Shoryuken.add_queue(queue_name, 1, 'default')
Shoryuken.register_worker(queue_name, Shoryuken::ActiveJob::JobWrapper)

RetryOnTestJob.perform_later

poll_queues_until(timeout: 30) { DT[:successes].size >= 1 }

assert(DT[:attempts].size >= 2, "Expected at least 2 retry attempts, got #{DT[:attempts].size}")
assert_equal(1, DT[:successes].size)
