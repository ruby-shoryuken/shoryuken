# frozen_string_literal: true

# This spec tests enqueueing the same ActiveJob job instance twice, with new
# arguments, on a standard and on a FIFO queue.
#
# The second enqueue sends the current arguments, and on the
# FIFO queue a deduplication id of the current body, so both runs happen with
# their own arguments.
#
# Regression: the second enqueue resent the first send's body and deduplication
# id, so the standard queue ran the old arguments twice and the FIFO queue
# dropped the second message as a duplicate.

setup_sqs
setup_active_job

standard_queue = DT.queue
fifo_queue = "#{DT.uuid}.fifo"
create_test_queue(standard_queue)
create_fifo_queue(fifo_queue)

class ReenqueueJob < ActiveJob::Base
  def perform(queue, value)
    DT[queue] << value
  end
end

Shoryuken.add_group('default', 1)
[standard_queue, fifo_queue].each do |queue|
  Shoryuken.add_queue(queue, 1, 'default')
  Shoryuken.register_worker(queue, Shoryuken::ActiveJob::JobWrapper)

  job = ReenqueueJob.new(queue, 'first')
  job.queue_name = queue
  job.enqueue
  job.arguments = [queue, 'second']
  job.enqueue
end

poll_queues_until(timeout: 15) { DT[standard_queue].size >= 2 && DT[fifo_queue].size >= 2 }

assert_equal(%w[first second], DT[standard_queue].sort)
assert_equal(%w[first second], DT[fifo_queue])

delete_test_queue(standard_queue)
delete_test_queue(fifo_queue)
