# frozen_string_literal: true

# This spec tests the instrumentation system integration.
# It verifies that events are published during message processing.

setup_localstack

queue_name = DT.queue
create_test_queue(queue_name)
Shoryuken.add_group('default', 1)
Shoryuken.add_queue(queue_name, 1, 'default')

# Reset monitor to ensure clean state
Shoryuken.reset_monitor!

# Collect events
events_received = []
Shoryuken.monitor.subscribe do |event|
  events_received << { name: event.name, payload: event.payload.dup, time: event.time }
end

# Worker for testing
worker_class = Class.new do
  include Shoryuken::Worker

  shoryuken_options auto_delete: true, batch: false

  def perform(sqs_msg, body)
    DT[:processed] << { message_id: sqs_msg.message_id, body: body }
  end
end

worker_class.get_shoryuken_options['queue'] = queue_name
Shoryuken.register_worker(queue_name, worker_class)

# Send test messages
2.times { |i| Shoryuken::Client.queues(queue_name).send_message(message_body: "instrumentation-test-#{i}") }

sleep 1

poll_queues_until { DT[:processed].size >= 2 }

# Verify messages were processed
assert_equal(2, DT[:processed].size)

# Verify instrumentation events were captured
processed_events = events_received.select { |e| e[:name] == 'message.processed' }
assert(processed_events.size >= 2, "Should have at least 2 message.processed events, got #{processed_events.size}")

# Verify event payloads contain expected data
processed_events.each do |event|
  assert_equal(queue_name, event[:payload][:queue], 'Event should include queue name')
  assert(event[:payload][:message_id], 'Event should include message_id')
  assert(event[:payload][:duration], 'Event should include duration')
  assert(event[:payload][:duration] >= 0, 'Duration should be non-negative')
end

# Cleanup
Shoryuken.reset_monitor!
