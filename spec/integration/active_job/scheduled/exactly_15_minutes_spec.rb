# frozen_string_literal: true

# This spec tests ActiveJob `set(wait:)` with a delay of exactly 15 minutes,
# the SQS maximum, through `perform_later` and `perform_all_later`.
#
# Both jobs are sent with `delay_seconds: 900`, so the queue holds two delayed
# messages and none visible.

setup_sqs
setup_active_job

queue_name = DT.queue
create_test_queue(queue_name)

class ExactlyFifteenMinutesJob < ActiveJob::Base
  def perform; end
end

ExactlyFifteenMinutesJob.set(queue: queue_name, wait: 15.minutes).perform_later
ActiveJob.perform_all_later(ExactlyFifteenMinutesJob.new.set(queue: queue_name, wait: 15.minutes))

counts = queue_counts(queue_name, delayed: true)

assert_equal(2, counts[:delayed], 'Both jobs should be delayed')
assert_equal(0, counts[:visible], 'No job should be visible yet')

delete_test_queue(queue_name)
