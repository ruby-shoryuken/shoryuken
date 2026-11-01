# frozen_string_literal: true

# This spec tests ActiveJob `set(wait_until:)` with a time in the past, on a
# standard and on a FIFO queue.
#
# The job is sent with `delay_seconds: 0` and runs at once.
#
# Regression: the adapter sent a negative `DelaySeconds`, which SQS rejects, so
# `perform_later` raised `Aws::SQS::Errors::InvalidParameterValue`.

setup_sqs
setup_active_job

standard_queue = DT.queue
fifo_queue = "#{DT.uuid}.fifo"
create_test_queue(standard_queue)
create_fifo_queue(fifo_queue)

class PastWaitUntilJob < ActiveJob::Base
  def perform(label)
    DT[:performed] << label
  end
end

Shoryuken.add_group('default', 1)
[standard_queue, fifo_queue].each do |queue|
  Shoryuken.add_queue(queue, 1, 'default')
  Shoryuken.register_worker(queue, Shoryuken::ActiveJob::JobWrapper)
end

PastWaitUntilJob.set(queue: standard_queue, wait_until: 30.seconds.ago).perform_later('standard')
PastWaitUntilJob.set(queue: fifo_queue, wait_until: 30.seconds.ago).perform_later('fifo')

poll_queues_until(timeout: 15) { DT[:performed].size >= 2 }

assert_equal(%w[fifo standard], DT[:performed].sort)

delete_test_queue(standard_queue)
delete_test_queue(fifo_queue)
