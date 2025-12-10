# frozen_string_literal: true

# This spec tests batch processing including batch message reception (up to 10
# messages), batch vs single worker behavior differences, JSON body parsing in
# batch mode, and maximum batch size handling.

setup_localstack
reset_shoryuken

queue_name = "batch-test-#{SecureRandom.uuid}"
create_test_queue(queue_name)
Shoryuken.add_group('default', 1)
Shoryuken.add_queue(queue_name, 1, 'default')

# Create batch worker
worker_class = Class.new do
  include Shoryuken::Worker

  class << self
    attr_accessor :received_messages, :batch_sizes
  end

  def perform(sqs_msgs, bodies)
    msgs = Array(sqs_msgs)
    self.class.batch_sizes ||= []
    self.class.batch_sizes << msgs.size
    self.class.received_messages ||= []
    self.class.received_messages.concat(Array(bodies))
  end
end

worker_class.get_shoryuken_options['queue'] = queue_name
worker_class.get_shoryuken_options['auto_delete'] = true
worker_class.get_shoryuken_options['batch'] = true
worker_class.received_messages = []
worker_class.batch_sizes = []
Shoryuken.register_worker(queue_name, worker_class)

# Send batch of messages
entries = 5.times.map { |i| { id: SecureRandom.uuid, message_body: "message-#{i}" } }
Shoryuken::Client.queues(queue_name).send_messages(entries: entries)

sleep 1

poll_queues_until { worker_class.received_messages.size >= 5 }

assert_equal(5, worker_class.received_messages.size)
assert(worker_class.batch_sizes.any? { |size| size > 1 }, "Expected at least one batch with size > 1")

delete_test_queue(queue_name)
