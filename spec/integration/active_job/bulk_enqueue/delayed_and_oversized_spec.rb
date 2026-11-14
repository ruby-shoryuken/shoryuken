# frozen_string_literal: true

# This spec tests ActiveJob `perform_all_later` with delayed jobs and with jobs
# whose total size is over the 1 MiB SQS batch limit.
#
# A job set with `wait:` is delayed, one with a time in the past runs at once,
# a delay over 15 minutes or a delay on a FIFO queue raises before anything is
# sent, and jobs over 1 MiB in total are sent in more batches.
#
# It used to send every job at once, without its delay, and to send 10 large
# jobs in one batch, which SQS rejects as too long.

setup_sqs
setup_active_job

queue_name = DT.queue
fifo_queue = "#{DT.uuid}.fifo"
create_test_queue(queue_name)
create_fifo_queue(fifo_queue)

class BulkDelayedJob < ActiveJob::Base
  def perform(label, payload)
    DT[:performed] << { label: label, size: payload.bytesize, at: Time.now }
  end
end

BulkDelayedJob.queue_as(queue_name)

Shoryuken.add_group('default', 4)
Shoryuken.add_queue(queue_name, 1, 'default')
Shoryuken.register_worker(queue_name, Shoryuken::ActiveJob::JobWrapper)

started_at = Time.now
jobs = [
  BulkDelayedJob.new('now', ''),
  BulkDelayedJob.new('past', '').set(wait_until: 30.seconds.ago),
  BulkDelayedJob.new('delayed', '').set(wait: 5.seconds)
]
large_jobs = Array.new(10) { |i| BulkDelayedJob.new("large_#{i}", 'a' * 200_000) }

ActiveJob.perform_all_later(jobs + large_jobs)

assert_equal(13, (jobs + large_jobs).count(&:successfully_enqueued?), 'All jobs should be marked as enqueued')

poll_queues_until(timeout: 30) { DT[:performed].size >= 13 }

performed = DT[:performed].to_h { |execution| [execution[:label], execution] }

assert_equal(13, performed.size)
assert(performed['now'][:at] - started_at < 4, 'An undelayed job should run at once')
assert(performed['past'][:at] - started_at < 4, 'A job scheduled in the past should run at once')
assert(performed['delayed'][:at] - started_at >= 5, 'A job set with wait: 5.seconds should run after 5 seconds')
10.times { |i| assert_equal(200_000, performed["large_#{i}"][:size]) }

too_long = raised_error(Shoryuken::Errors::InvalidDelayError) do
  ActiveJob.perform_all_later(
    [
      BulkDelayedJob.new('not_sent', ''),
      BulkDelayedJob.new('not_sent', '').set(wait: 16.minutes)
    ]
  )
end
assert(too_long, 'A delay over 15 minutes should raise InvalidDelayError')

fifo_delay = raised_error(Shoryuken::Errors::FifoDelayNotSupportedError) do
  ActiveJob.perform_all_later(
    [
      BulkDelayedJob.new('not_sent', '').set(queue: fifo_queue),
      BulkDelayedJob.new('not_sent', '').set(queue: fifo_queue, wait: 10.seconds)
    ]
  )
end
assert(fifo_delay, 'A delay on a FIFO queue should raise FifoDelayNotSupportedError')

assert_equal(0, queue_size(queue_name, delayed: true), 'Nothing should be sent after the errors')
assert_equal(0, queue_size(fifo_queue, delayed: true), 'Nothing should be sent to the FIFO queue')

delete_test_queue(queue_name)
delete_test_queue(fifo_queue)
