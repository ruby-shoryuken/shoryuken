# frozen_string_literal: true

# This spec tests that auto_delete does not delete a message whose worker
# raises, for single and batch workers.
#
# Expected behavior: a worker with `auto_delete: true` that raises leaves its
# message on the queue, so it comes back after the visibility timeout and is
# deleted only once a later perform succeeds. A batch worker that raises keeps
# the whole batch: every message of that batch comes back.
#
# Regression: #135 - data loss when exceptions are raised while using auto
# delete.

setup_sqs

single_queue = DT.uuid
batch_queue = DT.uuid
create_test_queue(single_queue, attributes: { 'VisibilityTimeout' => '2' })
create_test_queue(batch_queue, attributes: { 'VisibilityTimeout' => '2' })
Shoryuken.add_group('default', 1)
Shoryuken.add_queue(single_queue, 1, 'default')
Shoryuken.add_queue(batch_queue, 1, 'default')

Class.new do
  include Shoryuken::Worker

  shoryuken_options queue: single_queue, auto_delete: true

  def perform(sqs_msg, body)
    receive_count = sqs_msg.attributes['ApproximateReceiveCount'].to_i
    DT[:single] << [sqs_msg.message_id, body, receive_count]

    raise 'single worker failure' if receive_count == 1
  end
end

Class.new do
  include Shoryuken::Worker

  shoryuken_options queue: batch_queue, auto_delete: true, batch: true

  def perform(_sqs_msgs, bodies)
    DT[:batches] << bodies

    raise 'batch worker failure' if DT[:batches].size == 1
  end
end

Shoryuken::Client.queues(single_queue).send_message(message_body: 'single')
batch_bodies = %w[batch-1 batch-2 batch-3]
Shoryuken::Client.queues(batch_queue).send_messages(
  entries: batch_bodies.map { |body| { id: SecureRandom.uuid, message_body: body } }
)

sleep 1

poll_queues_until(timeout: 20) do
  DT[:single].size >= 2 && DT[:batches].size >= 2 && queue_size(single_queue).zero? && queue_size(batch_queue).zero?
end

# --- Single worker ---
first, second = DT[:single]
assert_equal(['single', 1], first.drop(1))
assert_equal([first[0], 'single', 2], second, 'the failed message must come back after the visibility timeout')

# --- Batch worker ---
failed_batch = DT[:batches].first
assert(failed_batch.size > 1, "the failed batch must hold more than one message, got #{failed_batch.inspect}")
assert_equal(batch_bodies, DT[:batches].drop(1).flatten.sort,
             'every message must come back after the failed batch and be deleted after one successful perform')

delete_test_queue(single_queue)
delete_test_queue(batch_queue)
