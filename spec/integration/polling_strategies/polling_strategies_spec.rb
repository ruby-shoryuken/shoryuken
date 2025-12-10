# frozen_string_literal: true

# This spec tests polling strategies including WeightedRoundRobin (default)
# with multi-queue worker message distribution.

setup_localstack

queue_high = DT.queues[0]
queue_medium = DT.queues[1]
queue_low = DT.queues[2]

[queue_high, queue_medium, queue_low].each { |q| create_test_queue(q) }

Shoryuken.add_group('default', 1)
# Higher weight = higher priority
Shoryuken.add_queue(queue_high, 3, 'default')
Shoryuken.add_queue(queue_medium, 2, 'default')
Shoryuken.add_queue(queue_low, 1, 'default')

# Create multi-queue worker
worker_class = Class.new do
  include Shoryuken::Worker

  shoryuken_options auto_delete: true, batch: false

  def perform(sqs_msg, body)
    queue = sqs_msg.queue_url.split('/').last
    DT[:by_queue] << { queue: queue, body: body }
  end
end

[queue_high, queue_medium, queue_low].each do |queue|
  worker_class.get_shoryuken_options['queue'] = queue
  Shoryuken.register_worker(queue, worker_class)
end

# Send messages to all queues
Shoryuken::Client.queues(queue_high).send_message(message_body: 'high-msg')
Shoryuken::Client.queues(queue_medium).send_message(message_body: 'medium-msg')
Shoryuken::Client.queues(queue_low).send_message(message_body: 'low-msg')

sleep 1

poll_queues_until { DT[:by_queue].size >= 3 }

queues_with_messages = DT[:by_queue].map { |m| m[:queue] }.uniq
assert_equal(3, queues_with_messages.size)
assert_equal(3, DT[:by_queue].size)

[queue_high, queue_medium, queue_low].each { |q| delete_test_queue(q) }
