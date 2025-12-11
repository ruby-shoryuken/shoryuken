# frozen_string_literal: true

# This spec tests Shoryuken::Queue operations including:
# - Queue initialization (by name, URL, and ARN)
# - Visibility timeout retrieval
# - FIFO queue detection
# - Batch message sending
# - Batch message deletion

setup_localstack

# Test 1: Queue initialization by name
queue_name = DT.uuid
create_test_queue(queue_name)

queue = Shoryuken::Queue.new(Shoryuken::Client.sqs, queue_name)
assert_equal(queue_name, queue.name)
assert(queue.url.include?(queue_name), "URL should contain queue name")
refute(queue.fifo?, "Standard queue should not be FIFO")

# Test 2: Queue initialization by URL
queue_url = queue.url
queue_by_url = Shoryuken::Queue.new(Shoryuken::Client.sqs, queue_url)
assert_equal(queue_name, queue_by_url.name)
assert_equal(queue_url, queue_by_url.url)

# Test 3: Visibility timeout retrieval
visibility_timeout = queue.visibility_timeout
assert(visibility_timeout.is_a?(Integer), "Visibility timeout should be an integer")
assert(visibility_timeout >= 0, "Visibility timeout should be non-negative")

# Test 4: FIFO queue detection
fifo_queue_name = "#{DT.uuid}.fifo"
create_fifo_queue(fifo_queue_name)

fifo_queue = Shoryuken::Queue.new(Shoryuken::Client.sqs, fifo_queue_name)
assert_equal(fifo_queue_name, fifo_queue.name)
assert(fifo_queue.fifo?, "FIFO queue should be detected as FIFO")

# Test 5: Send single message
send_result = queue.send_message(message_body: 'test message 1')
assert(send_result.message_id, "Send result should have message_id")

# Test 6: Send message with hash body (auto JSON serialization)
hash_body = { key: 'value', number: 42 }
send_result2 = queue.send_message(message_body: hash_body)
assert(send_result2.message_id, "Send result should have message_id for hash body")

# Test 7: Batch message sending
batch_result = queue.send_messages([
  { message_body: 'batch msg 1' },
  { message_body: 'batch msg 2' },
  { message_body: 'batch msg 3' }
])
assert_equal(3, batch_result.successful.size, "All 3 batch messages should succeed")

# Test 8: Receive messages
sleep 1 # Allow messages to become visible
received = queue.receive_messages(max_number_of_messages: 10)
assert(received.size > 0, "Should receive at least one message")
assert(received.first.is_a?(Shoryuken::Message), "Received items should be Message objects")

# Test 9: Batch message deletion
entries = received.map.with_index do |msg, idx|
  { id: idx.to_s, receipt_handle: msg.receipt_handle }
end
delete_result = queue.delete_messages(entries: entries)
refute(delete_result, "Delete should succeed without failures")

# Test 10: FIFO queue message sending with auto-generated attributes
fifo_send_result = fifo_queue.send_message(message_body: 'fifo test message')
assert(fifo_send_result.message_id, "FIFO send should have message_id")
assert(fifo_send_result.sequence_number, "FIFO send should have sequence_number")

# Test 11: Send message with delay
delayed_result = queue.send_message(
  message_body: 'delayed message',
  delay_seconds: 5
)
assert(delayed_result.message_id, "Delayed message should have message_id")

# Cleanup
delete_test_queue(queue_name)
delete_test_queue(fifo_queue_name)
