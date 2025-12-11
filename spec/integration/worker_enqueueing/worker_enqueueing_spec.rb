# frozen_string_literal: true

# This spec tests the worker enqueueing methods:
# - perform_async - enqueue a job for immediate processing
# - perform_in - enqueue a job with a delay

setup_localstack

queue_name = DT.queue
create_test_queue(queue_name)
Shoryuken.add_group('default', 1)
Shoryuken.add_queue(queue_name, 1, 'default')

# Worker for testing enqueueing methods
enqueueing_worker = Class.new do
  include Shoryuken::Worker

  shoryuken_options auto_delete: true

  def perform(sqs_msg, body)
    DT[:processed_messages] << {
      message_id: sqs_msg.message_id,
      body: body,
      processed_at: Time.now
    }
  end
end

enqueueing_worker.get_shoryuken_options['queue'] = queue_name
Shoryuken.register_worker(queue_name, enqueueing_worker)

# Test 1: perform_async - immediate enqueueing with string body
enqueueing_worker.perform_async('async string message')

# Test 2: perform_async with hash body
enqueueing_worker.perform_async('action' => 'test', 'data' => [1, 2, 3])

# Test 3: perform_in - delayed enqueueing (use short 1 second delay)
enqueueing_worker.perform_in(1, 'delayed message')

sleep 1

# Poll for all 3 messages
poll_queues_until(timeout: 15) { DT[:processed_messages].size >= 3 }

assert_equal(3, DT[:processed_messages].size)

# Verify string message was processed
string_msg = DT[:processed_messages].find { |m| m[:body] == 'async string message' }
assert(string_msg, 'String message should have been processed')

# Verify hash message was processed (bodies might be stringified depending on serialization)
hash_msg = DT[:processed_messages].find do |m|
  m[:body].is_a?(Hash) || (m[:body].is_a?(String) && m[:body].include?('action'))
end
assert(hash_msg, 'Hash message should have been processed')

# Verify delayed message was processed
delayed_msg = DT[:processed_messages].find { |m| m[:body] == 'delayed message' }
assert(delayed_msg, 'Delayed message should have been processed')
