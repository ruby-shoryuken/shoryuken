# frozen_string_literal: true

# This spec tests ActiveJob delays on a FIFO queue: `set(wait:)`,
# `set(wait_until:)` in the future and `retry_on wait: 0`.
#
# Expected behavior: `set(wait:)` and `set(wait_until:)` raise
# `Shoryuken::Errors::FifoDelayNotSupportedError` before anything is sent.
# `retry_on wait: 0` re-enqueues the failed job without a delay, so it runs
# again until it succeeds.
#
# Regression: #924 - `retry_on` on a FIFO queue sent `DelaySeconds`, which SQS
# rejects with `Aws::SQS::Errors::InvalidParameterValue`.
# Regression: #948 - the FIFO delay check raised a plain `ArgumentError`.

setup_sqs
setup_active_job

queue_name = "#{DT.uuid}.fifo"
create_fifo_queue(queue_name)

class FifoDelayJob < ActiveJob::Base
  def perform; end
end

class FifoRetryJob < ActiveJob::Base
  retry_on StandardError, wait: 0, attempts: 3

  def perform
    DT[:attempts] << executions
    raise StandardError, 'Simulated failure' if executions < 3

    DT[:successes] << executions
  end
end

[FifoDelayJob, FifoRetryJob].each { |job_class| job_class.queue_as(queue_name) }

Shoryuken.add_group('default', 1)
Shoryuken.add_queue(queue_name, 1, 'default')
Shoryuken.register_worker(queue_name, Shoryuken::ActiveJob::JobWrapper)

wait_error = raised_error(Shoryuken::Errors::FifoDelayNotSupportedError) do
  FifoDelayJob.set(wait: 5.seconds).perform_later
end
wait_until_error = raised_error(Shoryuken::Errors::FifoDelayNotSupportedError) do
  FifoDelayJob.set(wait_until: 1.minute.from_now).perform_later
end

assert(wait_error, 'set(wait:) should raise FifoDelayNotSupportedError')
assert(wait_until_error, 'set(wait_until:) should raise FifoDelayNotSupportedError')
assert_includes(wait_error.message, "FIFO queue '#{queue_name}' does not support per-message delays")
assert_includes(wait_error.message, 'set `wait: 0`')
assert_equal(0, queue_size(queue_name, delayed: true), 'Nothing should be sent')

FifoRetryJob.perform_later

poll_queues_until(timeout: 30) { DT[:successes].size >= 1 }

assert_equal([1, 2, 3], DT[:attempts])
assert_equal([3], DT[:successes])
assert_equal(0, queue_size(queue_name))

delete_test_queue(queue_name)
