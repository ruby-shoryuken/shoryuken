# frozen_string_literal: true

# This spec tests ActiveJob `retry_on` with a non-zero `wait`, which re-enqueues
# the job through the adapter's `enqueue_at`.
#
# - `wait: 2.seconds` sends the retry as a new message delayed by 2 seconds. The
#   queue's visibility timeout is 30 seconds, so the retry is not a redelivery.
# - `wait: 16.minutes` is over the 15 minute SQS maximum, so the retry's enqueue
#   raises `Shoryuken::Errors::InvalidDelayError` inside the worker. The message
#   is not deleted and comes back after each visibility timeout with the same
#   `retry_on` attempt count, so the attempts never run out and the `retry_on`
#   block never runs. Exception handlers get `InvalidDelayError` with the job's
#   error as its `cause`.

setup_sqs
setup_active_job

short_queue, long_queue = DT.uuids(2)
create_test_queue(short_queue, attributes: { 'VisibilityTimeout' => '30' })
create_test_queue(long_queue, attributes: { 'VisibilityTimeout' => '1' })

class RetryOnWaitError < StandardError; end

Shoryuken.exception_handlers = [
  lambda do |error, queue, sqs_msg|
    DT[queue] << {
      error: error,
      message_id: sqs_msg.message_id,
      receive_count: sqs_msg.attributes['ApproximateReceiveCount'].to_i
    }
  end
]

class ShortWaitJob < ActiveJob::Base
  retry_on RetryOnWaitError, wait: 2.seconds, jitter: 0, attempts: 3

  def perform
    DT[:short] << { executions: executions, time: Time.now }
    raise RetryOnWaitError, 'first attempt fails' if executions == 1
  end
end

class LongWaitJob < ActiveJob::Base
  retry_on(RetryOnWaitError, wait: 16.minutes, jitter: 0, attempts: 3) { |_job, error| DT[:block_called] << error }

  def perform
    DT[:long] << executions
    raise RetryOnWaitError, 'always fails'
  end
end

Shoryuken.add_group('default', 1)
jobs = { ShortWaitJob => short_queue, LongWaitJob => long_queue }
jobs.each do |job, queue|
  job.queue_as(queue)
  Shoryuken.add_queue(queue, 1, 'default')
  Shoryuken.register_worker(queue, Shoryuken::ActiveJob::JobWrapper)
end

ShortWaitJob.perform_later
LongWaitJob.perform_later

poll_queues_until(timeout: 30) do
  DT[:short].size >= 2 && DT[long_queue].size >= 4
end

# --- wait: 2.seconds ---
failure, retry_run = DT[:short]
retry_delay = retry_run[:time] - failure[:time]
assert_equal([1, 2], DT[:short].map { |run| run[:executions] })
assert(retry_delay >= 1.5, "the retry must wait about 2 seconds, it came after #{retry_delay}s")
assert(retry_delay < 6, "the retry must come about 2 seconds after the failure, it came after #{retry_delay}s")
assert_equal(0, DT[short_queue].size, 'the error must not reach the exception handlers')
assert_equal(0, queue_size(short_queue), 'both messages must be deleted')

# --- wait: 16.minutes ---
reports = DT[long_queue]
assert_equal(1, reports.map { |report| report[:message_id] }.uniq.size, 'the original message must come back')
assert_equal(
  (1..reports.size).to_a, reports.map { |report| report[:receive_count] },
  'the message must come back after each visibility timeout'
)
reports.each do |report|
  assert_equal(Shoryuken::Errors::InvalidDelayError, report[:error].class)
  assert_equal('The maximum allowed delay is 15 minutes', report[:error].message)
  assert_equal(RetryOnWaitError, report[:error].cause.class)
  assert_equal('always fails', report[:error].cause.message)
end
assert_equal([], DT[:block_called], 'the retry_on block must not run, even after more receives than attempts')
assert_equal(1, queue_size(long_queue), 'the message must stay in the queue')

delete_test_queue(short_queue)
delete_test_queue(long_queue)
