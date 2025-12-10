# frozen_string_literal: true

# This spec tests FIFO queue ordering guarantees including message ordering
# within the same message group.


setup_localstack
reset_shoryuken

queue_name = "fifo-test-#{SecureRandom.uuid[0..7]}.fifo"
create_fifo_queue(queue_name)
Shoryuken.add_group('default', 1)
Shoryuken.add_queue(queue_name, 1, 'default')

# Create FIFO worker
worker_class = Class.new do
  include Shoryuken::Worker

  class << self
    attr_accessor :received_messages
  end

  def perform(sqs_msg, body)
    self.class.received_messages ||= []
    self.class.received_messages << body
  end
end

worker_class.get_shoryuken_options['queue'] = queue_name
worker_class.get_shoryuken_options['auto_delete'] = true
worker_class.get_shoryuken_options['batch'] = false
worker_class.received_messages = []
Shoryuken.register_worker(queue_name, worker_class)

queue_url = Shoryuken::Client.sqs.get_queue_url(queue_name: queue_name).queue_url

# Send ordered messages with same group
5.times do |i|
  Shoryuken::Client.sqs.send_message(
    queue_url: queue_url,
    message_body: "msg-#{i}",
    message_group_id: 'group-a',
    message_deduplication_id: SecureRandom.uuid
  )
end

sleep 1

poll_queues_until { worker_class.received_messages.size >= 5 }

assert_equal(5, worker_class.received_messages.size)

# Verify ordering is maintained
expected = (0..4).map { |i| "msg-#{i}" }
assert_equal(expected, worker_class.received_messages)

delete_test_queue(queue_name)
