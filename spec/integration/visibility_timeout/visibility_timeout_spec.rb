# frozen_string_literal: true

# This spec tests visibility timeout management including manual visibility
# extension during long processing.

setup_localstack
reset_shoryuken

queue_name = "visibility-test-#{SecureRandom.uuid}"
create_test_queue(queue_name, attributes: { 'VisibilityTimeout' => '5' })
Shoryuken.add_group('default', 1)
Shoryuken.add_queue(queue_name, 1, 'default')

# Create slow worker that extends visibility
worker_class = Class.new do
  include Shoryuken::Worker

  class << self
    attr_accessor :received_messages, :visibility_extended
  end

  def perform(sqs_msg, body)
    # Extend visibility before long processing
    sqs_msg.change_visibility(visibility_timeout: 30)
    self.class.visibility_extended = true

    sleep 2 # Simulate slow processing

    self.class.received_messages ||= []
    self.class.received_messages << body
  end
end

worker_class.get_shoryuken_options['queue'] = queue_name
worker_class.get_shoryuken_options['auto_delete'] = true
worker_class.get_shoryuken_options['batch'] = false
worker_class.received_messages = []
worker_class.visibility_extended = false
Shoryuken.register_worker(queue_name, worker_class)

Shoryuken::Client.queues(queue_name).send_message(message_body: 'extend-test')

poll_queues_until { worker_class.received_messages.size >= 1 }

assert_equal(1, worker_class.received_messages.size)
assert(worker_class.visibility_extended, "Expected visibility to be extended")

delete_test_queue(queue_name)
