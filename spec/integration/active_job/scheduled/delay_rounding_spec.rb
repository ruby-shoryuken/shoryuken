# frozen_string_literal: true

# This spec tests that ActiveJob `set(wait:)` and a raw worker `perform_in`
# turn the same delay into the same `delay_seconds`, rounded up.
#
# A delay of 0.3 seconds on a FIFO queue raises
# `Shoryuken::Errors::FifoDelayNotSupportedError` and a delay of 900.4 seconds
# raises `Shoryuken::Errors::InvalidDelayError` on both paths, before anything
# is sent. A delay of exactly 900 seconds is sent on both paths.
#
# It used to round the ActiveJob delay to the nearest second, so ActiveJob sent
# both delays that a raw worker rejected.

setup_sqs
setup_active_job

queue_name = DT.uuid
fifo_queue_name = "#{DT.uuid}.fifo"
create_test_queue(queue_name)
create_fifo_queue(fifo_queue_name)

class DelayRoundingJob < ActiveJob::Base
  def perform; end
end

class DelayRoundingWorker
  include Shoryuken::Worker

  def perform(sqs_msg, body); end
end

DelayRoundingWorker.get_shoryuken_options['queue'] = queue_name
Shoryuken.register_worker(queue_name, DelayRoundingWorker)

# --- 0.3 seconds on a FIFO queue ---

job_error = raised_error(Shoryuken::Errors::FifoDelayNotSupportedError) do
  DelayRoundingJob.set(queue: fifo_queue_name, wait: 0.3).perform_later
end
worker_error = raised_error(Shoryuken::Errors::FifoDelayNotSupportedError) do
  DelayRoundingWorker.perform_in(0.3, 'body', queue: fifo_queue_name)
end

assert(job_error, 'set(wait: 0.3) on a FIFO queue should raise FifoDelayNotSupportedError')
assert(worker_error, 'perform_in(0.3) on a FIFO queue should raise FifoDelayNotSupportedError')
assert_equal(0, queue_size(fifo_queue_name, delayed: true), 'Nothing should be sent to the FIFO queue')

# --- 900.4 seconds on a standard queue ---

job_error = raised_error(Shoryuken::Errors::InvalidDelayError) do
  DelayRoundingJob.set(queue: queue_name, wait: 900.4).perform_later
end
worker_error = raised_error(Shoryuken::Errors::InvalidDelayError) do
  DelayRoundingWorker.perform_in(900.4, 'body')
end

assert(job_error, 'set(wait: 900.4) should raise InvalidDelayError')
assert(worker_error, 'perform_in(900.4) should raise InvalidDelayError')
assert_equal(0, queue_size(queue_name, delayed: true), 'Nothing should be sent to the standard queue')

# --- exactly 900 seconds on a standard queue ---

DelayRoundingJob.set(queue: queue_name, wait: 900).perform_later
DelayRoundingWorker.perform_in(900, 'body')

counts = queue_counts(queue_name, delayed: true)

assert_equal(2, counts[:delayed], 'Both messages should be delayed')
assert_equal(0, counts[:visible], 'No message should be visible yet')

delete_test_queue(queue_name)
delete_test_queue(fifo_queue_name)
