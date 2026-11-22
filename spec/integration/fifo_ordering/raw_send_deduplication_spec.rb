# frozen_string_literal: true

# This spec tests the message_deduplication_id that raw sends to a FIFO queue
# (Worker.perform_async and Queue#send_messages) get.
#
# By default it is the SHA256 of the body, so two sends of an identical body
# within SQS's 5-minute window deliver one message. An explicit
# message_deduplication_id always wins. With
# Shoryuken.fifo_message_deduplication = false no id is generated, so each send
# needs an explicit one. The queues have ContentBasedDeduplication off, so only
# the id Shoryuken sends decides deduplication.

setup_sqs

class DedupWorker
  include Shoryuken::Worker

  def perform(sqs_msg, body); end
end

def with_fifo_queue
  with_queue_and_dir(fifo: true, attributes: { 'ContentBasedDeduplication' => 'false' }) do |queue, _dir|
    yield queue
  end
end

# --- default: identical bodies are deduplicated ---

with_fifo_queue do |queue|
  2.times { DedupWorker.perform_async('same-body', queue: queue) }

  assert_equal(1, queue_size(queue), 'two perform_async calls with an identical body deliver 1 message')
end

with_fifo_queue do |queue|
  Shoryuken::Client.queues(queue).send_messages(%w[same-body same-body])

  assert_equal(1, queue_size(queue), 'a batch with an identical body twice delivers 1 message')
end

# --- an explicit message_deduplication_id wins over the body digest ---

with_fifo_queue do |queue|
  DedupWorker.perform_async('same-body', queue: queue, message_deduplication_id: 'id-a')
  DedupWorker.perform_async('same-body', queue: queue, message_deduplication_id: 'id-b')

  assert_equal(2, queue_size(queue), 'distinct explicit ids deliver both perform_async messages')
end

with_fifo_queue do |queue|
  DedupWorker.perform_async('body-a', queue: queue, message_deduplication_id: 'same-id')
  DedupWorker.perform_async('body-b', queue: queue, message_deduplication_id: 'same-id')

  assert_equal(1, queue_size(queue), 'an explicit id deduplicates distinct perform_async bodies')
end

with_fifo_queue do |queue|
  Shoryuken::Client.queues(queue).send_messages(
    [
      { message_body: 'same-body', message_deduplication_id: 'id-a' },
      { message_body: 'same-body', message_deduplication_id: 'id-b' }
    ]
  )

  assert_equal(2, queue_size(queue), 'distinct explicit ids deliver both batch messages')
end

with_fifo_queue do |queue|
  Shoryuken::Client.queues(queue).send_messages(
    [
      { message_body: 'body-a', message_deduplication_id: 'same-id' },
      { message_body: 'body-b', message_deduplication_id: 'same-id' }
    ]
  )

  assert_equal(1, queue_size(queue), 'an explicit id deduplicates distinct batch bodies')
end

# --- fifo_message_deduplication = false: no id is generated ---

begin
  Shoryuken.fifo_message_deduplication = false

  with_fifo_queue do |queue|
    DedupWorker.perform_async('same-body', queue: queue, message_deduplication_id: 'id-a')
    DedupWorker.perform_async('same-body', queue: queue, message_deduplication_id: 'id-b')

    assert_equal(2, queue_size(queue), 'with the opt-out, distinct explicit ids deliver both perform_async messages')

    error = raised_error(Aws::SQS::Errors::InvalidParameterValue) do
      DedupWorker.perform_async('same-body', queue: queue)
    end

    assert(error, 'with the opt-out, perform_async without an explicit id sends no message_deduplication_id')
  end

  with_fifo_queue do |queue|
    Shoryuken::Client.queues(queue).send_messages(
      [
        { message_body: 'same-body', message_deduplication_id: 'id-a' },
        { message_body: 'same-body', message_deduplication_id: 'id-b' }
      ]
    )

    assert_equal(2, queue_size(queue), 'with the opt-out, distinct explicit ids deliver both batch messages')

    response = Shoryuken::Client.queues(queue).send_messages(%w[same-body same-body])

    assert_equal(2, response.failed.size, 'with the opt-out, batch entries without an explicit id are rejected')
    assert_equal(2, queue_size(queue))
  end
ensure
  Shoryuken.fifo_message_deduplication = true
end
