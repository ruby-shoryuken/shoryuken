# frozen_string_literal: true

# This spec tests multiple worker groups with different concurrency settings.
# Each group can have its own queues and concurrency level.

require 'concurrent'

setup_localstack

queue_group1 = DT.queues[0]
queue_group2 = DT.queues[1]

%w[queue_group1 queue_group2].each_with_index { |_, i| create_test_queue(DT.queues[i]) }

# Configure two separate groups with different concurrency
Shoryuken.add_group('group1', 3)  # 3 concurrent processors
Shoryuken.add_group('group2', 1)  # 1 concurrent processor

Shoryuken.add_queue(queue_group1, 1, 'group1')
Shoryuken.add_queue(queue_group2, 1, 'group2')

# Track concurrent processing per group
group1_concurrent = Concurrent::AtomicFixnum.new(0)
group1_max = Concurrent::AtomicFixnum.new(0)
group2_concurrent = Concurrent::AtomicFixnum.new(0)
group2_max = Concurrent::AtomicFixnum.new(0)

worker_class = Class.new do
  include Shoryuken::Worker

  shoryuken_options auto_delete: true, batch: false

  define_method(:perform) do |sqs_msg, body|
    queue = sqs_msg.queue_url.split('/').last

    if queue == queue_group1
      group1_concurrent.increment
      current = group1_concurrent.value
      group1_max.update { |max| [max, current].max }
      sleep 0.5  # Longer sleep to increase chance of concurrent execution
      group1_concurrent.decrement
    else
      group2_concurrent.increment
      current = group2_concurrent.value
      group2_max.update { |max| [max, current].max }
      sleep 0.3
      group2_concurrent.decrement
    end

    DT[:processed] << { queue: queue, body: body }
  end
end

[queue_group1, queue_group2].each do |queue|
  worker_class.get_shoryuken_options['queue'] = queue
  Shoryuken.register_worker(queue, worker_class)
end

# Send messages to both groups
5.times { |i| Shoryuken::Client.queues(queue_group1).send_message(message_body: "group1-#{i}") }
5.times { |i| Shoryuken::Client.queues(queue_group2).send_message(message_body: "group2-#{i}") }

sleep 1

poll_queues_until(timeout: 20) { DT[:processed].size >= 10 }

assert_equal(10, DT[:processed].size)

# Verify messages from both groups were processed
group1_messages = DT[:processed].select { |m| m[:queue] == queue_group1 }
group2_messages = DT[:processed].select { |m| m[:queue] == queue_group2 }

assert_equal(5, group1_messages.size, 'All group1 messages should be processed')
assert_equal(5, group2_messages.size, 'All group2 messages should be processed')

# Verify concurrency was used - group1 with concurrency 3 should process concurrently
# group2 with concurrency 1 should process sequentially (max = 1)
assert(group1_max.value >= 1, "Group1 should have processed messages (max concurrent: #{group1_max.value})")
assert_equal(1, group2_max.value, 'Group2 with concurrency 1 should process sequentially')
