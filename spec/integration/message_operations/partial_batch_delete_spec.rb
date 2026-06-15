# frozen_string_literal: true

# This spec exercises Queue#delete_messages against a real partial batch-delete
# failure (one valid receipt handle plus one invalid one).
#
# It confirms the end-to-end contract the NonRetryableException and AutoDelete
# middlewares rely on: delete_messages returns a plain boolean true when any
# entry fails, and a partial failure does not abort the rest of the batch (the
# valid entry is still deleted).
#
# Note: the underlying bug (only the first failure was logged, and the truthy
# return relied on Logger#error returning true) is only observable with a logger
# that returns falsey, so it is reproduced in the unit specs. With the default
# logger this path returns true either way - this spec guards the real-SQS
# behavior of the rewritten method.

require 'timeout'

setup_sqs

DT.clear

queue_name = DT.queue
create_test_queue(queue_name)
queue_url = Shoryuken::Client.sqs.get_queue_url(queue_name: queue_name).queue_url

# Send and receive a message so we hold a valid receipt handle.
Shoryuken::Client.sqs.send_message(queue_url: queue_url, message_body: 'keep')

received = []
Timeout.timeout(15) do
  loop do
    received = Shoryuken::Client.sqs.receive_message(
      queue_url: queue_url, max_number_of_messages: 1, wait_time_seconds: 1
    ).messages
    break if received.any?
  end
end
valid_handle = received.first.receipt_handle

# Batch-delete one valid handle and one bogus handle: a partial failure.
queue = Shoryuken::Client.queues(queue_name)
result = queue.delete_messages(
  entries: [
    { id: '0', receipt_handle: valid_handle },
    { id: '1', receipt_handle: 'bogus-receipt-handle' }
  ]
)

assert_equal(true, result, 'delete_messages should return true when any entry fails to delete')

# The valid entry was still deleted; the partial failure did not abort the batch.
remaining = nil
Timeout.timeout(10) do
  loop do
    attrs = Shoryuken::Client.sqs.get_queue_attributes(
      queue_url: queue_url,
      attribute_names: %w[ApproximateNumberOfMessages ApproximateNumberOfMessagesNotVisible]
    ).attributes
    remaining = attrs['ApproximateNumberOfMessages'].to_i + attrs['ApproximateNumberOfMessagesNotVisible'].to_i
    break if remaining.zero?

    sleep 0.3
  end
end

assert_equal(0, remaining, 'the successfully-deleted message should be gone after the partial failure')
