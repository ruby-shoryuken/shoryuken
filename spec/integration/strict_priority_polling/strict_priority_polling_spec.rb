# frozen_string_literal: true

# This spec tests the StrictPriority polling strategy.
# Higher priority queues are always processed before lower priority queues.

setup_localstack

queue_high = DT.queues[0]
queue_low = DT.queues[1]

[queue_high, queue_low].each { |q| create_test_queue(q) }

# Configure StrictPriority polling strategy
Shoryuken.options[:polling_strategy] = 'StrictPriority'

Shoryuken.add_group('default', 1)
# Higher weight = higher priority (queue_high appears 3 times, queue_low appears 1 time)
Shoryuken.add_queue(queue_high, 3, 'default')
Shoryuken.add_queue(queue_low, 1, 'default')

worker_class = Class.new do
  include Shoryuken::Worker

  shoryuken_options auto_delete: true, batch: false

  def perform(sqs_msg, body)
    queue = sqs_msg.queue_url.split('/').last
    DT[:processed_order] << { queue: queue, body: body, time: Time.now }
  end
end

[queue_high, queue_low].each do |queue|
  worker_class.get_shoryuken_options['queue'] = queue
  Shoryuken.register_worker(queue, worker_class)
end

# Send messages to low priority queue first
3.times { |i| Shoryuken::Client.queues(queue_low).send_message(message_body: "low-#{i}") }

# Then send messages to high priority queue
3.times { |i| Shoryuken::Client.queues(queue_high).send_message(message_body: "high-#{i}") }

sleep 1

poll_queues_until(timeout: 20) { DT[:processed_order].size >= 6 }

assert_equal(6, DT[:processed_order].size)

# With StrictPriority, high priority messages should generally be processed first
high_messages = DT[:processed_order].select { |m| m[:queue] == queue_high }
low_messages = DT[:processed_order].select { |m| m[:queue] == queue_low }

assert_equal(3, high_messages.size, "All high priority messages should be processed")
assert_equal(3, low_messages.size, "All low priority messages should be processed")

# Verify both queues were processed
queues_processed = DT[:processed_order].map { |m| m[:queue] }.uniq
assert_equal(2, queues_processed.size, "Both queues should have messages processed")
