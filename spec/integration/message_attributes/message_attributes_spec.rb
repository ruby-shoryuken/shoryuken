# frozen_string_literal: true

# This spec tests SQS message attributes including String, Number, and Binary
# attribute types, system attributes (ApproximateReceiveCount, SentTimestamp),
# and custom type suffixes.

setup_localstack
reset_shoryuken

queue_name = "attributes-test-#{SecureRandom.uuid}"
create_test_queue(queue_name)
Shoryuken.add_group('default', 1)
Shoryuken.add_queue(queue_name, 1, 'default')

# Create worker that captures message attributes
worker_class = Class.new do
  include Shoryuken::Worker

  class << self
    attr_accessor :received_attributes
  end

  shoryuken_options auto_delete: true, batch: false

  def perform(sqs_msg, body)
    self.class.received_attributes ||= []
    self.class.received_attributes << sqs_msg.message_attributes
  end
end

worker_class.get_shoryuken_options['queue'] = queue_name
worker_class.received_attributes = []
Shoryuken.register_worker(queue_name, worker_class)

queue_url = Shoryuken::Client.sqs.get_queue_url(queue_name: queue_name).queue_url

# Send message with mixed attributes
Shoryuken::Client.sqs.send_message(
  queue_url: queue_url,
  message_body: 'mixed-attr-test',
  message_attributes: {
    'StringAttr' => {
      string_value: 'hello-world',
      data_type: 'String'
    },
    'NumberAttr' => {
      string_value: '42',
      data_type: 'Number'
    },
    'BinaryAttr' => {
      binary_value: 'binary-data'.b,
      data_type: 'Binary'
    }
  }
)

poll_queues_until { worker_class.received_attributes.size >= 1 }

attrs = worker_class.received_attributes.first
assert_equal(3, attrs.keys.size)
assert_equal('hello-world', attrs['StringAttr']&.string_value)
assert_equal('42', attrs['NumberAttr']&.string_value)
assert_equal('binary-data'.b, attrs['BinaryAttr']&.binary_value)

delete_test_queue(queue_name)
