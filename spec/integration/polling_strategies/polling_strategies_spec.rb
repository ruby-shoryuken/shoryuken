# frozen_string_literal: true

# This spec tests polling strategies including WeightedRoundRobin (default)
# with multi-queue worker message distribution.

setup_localstack
reset_shoryuken

queue_prefix = "polling-#{SecureRandom.uuid[0..7]}"
queue_high = "#{queue_prefix}-high"
queue_medium = "#{queue_prefix}-medium"
queue_low = "#{queue_prefix}-low"

[queue_high, queue_medium, queue_low].each { |q| create_test_queue(q) }

Shoryuken.add_group('default', 1)
# Higher weight = higher priority
Shoryuken.add_queue(queue_high, 3, 'default')
Shoryuken.add_queue(queue_medium, 2, 'default')
Shoryuken.add_queue(queue_low, 1, 'default')

# Create multi-queue worker
worker_class = Class.new do
  include Shoryuken::Worker

  class << self
    attr_accessor :messages_by_queue
  end

  shoryuken_options auto_delete: true, batch: false

  def perform(sqs_msg, body)
    queue = sqs_msg.queue_url.split('/').last
    self.class.messages_by_queue ||= {}
    self.class.messages_by_queue[queue] ||= []
    self.class.messages_by_queue[queue] << body
  end

  def self.total_messages
    (messages_by_queue || {}).values.flatten.size
  end
end

[queue_high, queue_medium, queue_low].each do |queue|
  worker_class.get_shoryuken_options['queue'] = queue
  Shoryuken.register_worker(queue, worker_class)
end

worker_class.messages_by_queue = {}

# Send messages to all queues
Shoryuken::Client.queues(queue_high).send_message(message_body: 'high-msg')
Shoryuken::Client.queues(queue_medium).send_message(message_body: 'medium-msg')
Shoryuken::Client.queues(queue_low).send_message(message_body: 'low-msg')

sleep 1

poll_queues_until { worker_class.total_messages >= 3 }

assert_equal(3, worker_class.messages_by_queue.keys.size)
assert_equal(3, worker_class.total_messages)

[queue_high, queue_medium, queue_low].each { |q| delete_test_queue(q) }
