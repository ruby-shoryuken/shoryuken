# frozen_string_literal: true

# This spec tests SQS message attributes including String, Number, and Binary
# attribute types, system attributes (ApproximateReceiveCount, SentTimestamp),
# and custom type suffixes.

setup_localstack

queue_name = DT.queue
create_test_queue(queue_name)
Shoryuken.add_group('default', 1)
Shoryuken.add_queue(queue_name, 1, 'default')

# Create worker that captures message attributes
worker_class = Class.new do
  include Shoryuken::Worker

  shoryuken_options auto_delete: true, batch: false

  def perform(sqs_msg, body)
    DT[:attributes] << sqs_msg.message_attributes
  end
end

worker_class.get_shoryuken_options['queue'] = queue_name
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

poll_queues_until { DT[:attributes].size >= 1 }

attrs = DT[:attributes].first
assert_equal(3, attrs.keys.size)
assert_equal('hello-world', attrs['StringAttr']&.string_value)
assert_equal('42', attrs['NumberAttr']&.string_value)
assert_equal('binary-data'.b, attrs['BinaryAttr']&.binary_value)
