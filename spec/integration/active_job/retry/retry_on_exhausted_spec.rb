# frozen_string_literal: true

# This spec tests what happens to an ActiveJob job whose `retry_on` runs out of
# attempts.
#
# `retry_on StandardError, wait: 0, attempts: 3` sends the
# job twice more as new messages, and `executions` reads 1, 2, 3 for the three
# attempts, as in ActiveJob. On the third attempt ActiveJob re-raises the error:
# - Without a block, the error reaches Shoryuken's exception handlers and the
#   message is not deleted. SQS delivers it again after each visibility timeout,
#   and each delivery adds one to `executions`.
# - With a block, the error does not escape, the message is deleted and does not
#   come back.
# - With a redrive policy, the message ends in the dead letter queue.
#
# Regression: `executions` read 1 on every `retry_on` attempt, because
# Shoryuken replaced it with the receive count minus one.

setup_sqs
setup_active_job

plain_queue, block_queue, redrive_queue, dlq = DT.uuids(4)
create_test_queue(plain_queue, attributes: { 'VisibilityTimeout' => '2' })
create_test_queue(block_queue, attributes: { 'VisibilityTimeout' => '2' })
create_queue_with_dlq(redrive_queue, dlq, max_receive_count: 2, attributes: { 'VisibilityTimeout' => '2' })

Shoryuken.exception_handlers = [
  ->(_error, queue, sqs_msg) { DT[queue] << [sqs_msg.message_id, sqs_msg.attributes['ApproximateReceiveCount'].to_i] }
]

class ExhaustedJob < ActiveJob::Base
  retry_on StandardError, wait: 0, attempts: 3

  def perform
    DT[:plain] << executions
    raise StandardError, 'always fails'
  end
end

class ExhaustedWithBlockJob < ActiveJob::Base
  retry_on(StandardError, wait: 0, attempts: 3) { |_job, error| DT[:block_called] << error.message }

  def perform
    DT[:block] << executions
    raise StandardError, 'always fails'
  end
end

class ExhaustedRedriveJob < ActiveJob::Base
  retry_on StandardError, wait: 0, attempts: 3

  def perform
    DT[:redrive] << executions
    raise StandardError, 'always fails'
  end
end

Shoryuken.add_group('default', 1)
jobs = { ExhaustedJob => plain_queue, ExhaustedWithBlockJob => block_queue, ExhaustedRedriveJob => redrive_queue }
jobs.each do |job, queue|
  job.queue_as(queue)
  Shoryuken.add_queue(queue, 1, 'default')
  Shoryuken.register_worker(queue, Shoryuken::ActiveJob::JobWrapper)
end

ExhaustedJob.perform_later
ExhaustedWithBlockJob.perform_later
ExhaustedRedriveJob.perform_later

poll_queues_until(timeout: 30) do
  DT[plain_queue].size >= 3 && DT[:block_called].any? && queue_size(dlq) == 1
end

# --- Without a block ---
message_ids, receive_counts = DT[plain_queue].transpose
assert_equal(1, message_ids.uniq.size, 'the exhausted message must be the one that comes back')
assert_equal((1..receive_counts.size).to_a, receive_counts, 'the message must come back after each visibility timeout')
assert_equal(
  [1, 2, *receive_counts.map { |count| count + 2 }], DT[:plain].first(receive_counts.size + 2),
  'executions must be 1, 2, 3 for the 3 attempts, then grow by one per receive'
)

# --- With a block ---
assert_equal(['always fails'], DT[:block_called])
assert_equal([1, 2, 3], DT[:block])
assert_equal(0, DT[block_queue].size, 'the error must not reach the exception handlers')
assert_equal(0, queue_size(block_queue), 'the message must be deleted')

# --- With a redrive policy ---
assert_equal([1, 2, 3, 4], DT[:redrive])
assert_equal([1, 2], DT[redrive_queue].map(&:last))
assert_equal(0, queue_size(redrive_queue), 'the message must leave the queue')

delete_test_queue(plain_queue)
delete_test_queue(block_queue)
delete_test_queue(redrive_queue)
delete_test_queue(dlq)
