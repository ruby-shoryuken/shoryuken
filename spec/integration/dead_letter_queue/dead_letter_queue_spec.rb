# frozen_string_literal: true

# This spec tests dead letter queue (DLQ) functionality.
# When a message exceeds maxReceiveCount, it should be moved to the DLQ.
# Note: This test doesn't use poll_queues_until because messages should fail
# and be moved to DLQ rather than being successfully processed.

setup_localstack

main_queue_name = DT.queues[0]
dlq_name = DT.queues[1]

# Create the dead letter queue first
create_test_queue(dlq_name)

dlq_url = Shoryuken::Client.sqs.get_queue_url(queue_name: dlq_name).queue_url
dlq_arn = Shoryuken::Client.sqs.get_queue_attributes(
  queue_url: dlq_url,
  attribute_names: ['QueueArn']
).attributes['QueueArn']

# Create main queue with redrive policy - move to DLQ after 2 receives
redrive_policy = { maxReceiveCount: 2, deadLetterTargetArn: dlq_arn }.to_json
create_test_queue(main_queue_name, attributes: {
  'VisibilityTimeout' => '1',
  'RedrivePolicy' => redrive_policy
})

main_queue_url = Shoryuken::Client.sqs.get_queue_url(queue_name: main_queue_name).queue_url

# Send a message
Shoryuken::Client.sqs.send_message(
  queue_url: main_queue_url,
  message_body: 'dlq test message'
)

# Manually receive the message multiple times to trigger DLQ
# maxReceiveCount = 2, so after 2 receives without deletion, it goes to DLQ
3.times do |i|
  msgs = Shoryuken::Client.sqs.receive_message(
    queue_url: main_queue_url,
    max_number_of_messages: 1,
    wait_time_seconds: 3,
    attribute_names: ['ApproximateReceiveCount']
  ).messages

  if msgs.any?
    receive_count = msgs.first.attributes['ApproximateReceiveCount'].to_i
    DT[:receives] << { attempt: i + 1, receive_count: receive_count }
    # Don't delete - let visibility timeout expire
    sleep 2
  else
    DT[:receives] << { attempt: i + 1, no_message: true }
    break
  end
end

# Verify message was received at least twice
actual_receives = DT[:receives].reject { |r| r[:no_message] }
assert(actual_receives.size >= 2, "Message should have been received at least twice (was #{actual_receives.size})")

# Wait for message to be moved to DLQ
sleep 3

# Check that message is now in the DLQ
dlq_messages = Shoryuken::Client.sqs.receive_message(
  queue_url: dlq_url,
  max_number_of_messages: 10,
  wait_time_seconds: 5,
  attribute_names: ['All']
).messages

assert(dlq_messages.size >= 1, 'Message should have been moved to DLQ')
assert_equal('dlq test message', dlq_messages.first.body)

# Verify message is no longer in main queue
main_attrs = Shoryuken::Client.sqs.get_queue_attributes(
  queue_url: main_queue_url,
  attribute_names: %w[ApproximateNumberOfMessages ApproximateNumberOfMessagesNotVisible]
).attributes
main_count = main_attrs['ApproximateNumberOfMessages'].to_i +
             main_attrs['ApproximateNumberOfMessagesNotVisible'].to_i
assert_equal(0, main_count, 'Main queue should be empty after DLQ move')

# Clean up DLQ message
dlq_messages.each do |msg|
  Shoryuken::Client.sqs.delete_message(
    queue_url: dlq_url,
    receipt_handle: msg.receipt_handle
  )
end
