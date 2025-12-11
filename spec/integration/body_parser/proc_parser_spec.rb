# frozen_string_literal: true

# This spec tests the body_parser option with a custom Proc
# Verifies that custom parsing logic can be applied to messages

setup_localstack

queue_name = DT.uuid
create_test_queue(queue_name)
Shoryuken.add_group('default', 1)
Shoryuken.add_queue(queue_name, 1, 'default')

# Custom parser that uppercases the body and adds metadata
custom_parser = proc do |sqs_msg|
  {
    original: sqs_msg.body,
    transformed: sqs_msg.body.upcase,
    message_id: sqs_msg.message_id
  }
end

worker_class = Class.new do
  include Shoryuken::Worker

  def perform(sqs_msg, body)
    DT[:parsed_bodies] << body
    DT[:body_classes] << body.class.name
  end
end

worker_class.get_shoryuken_options['queue'] = queue_name
worker_class.get_shoryuken_options['auto_delete'] = true
worker_class.get_shoryuken_options['body_parser'] = custom_parser
Shoryuken.register_worker(queue_name, worker_class)

queue_url = Shoryuken::Client.sqs.get_queue_url(queue_name: queue_name).queue_url

# Send a message to be processed by custom parser
Shoryuken::Client.sqs.send_message(
  queue_url: queue_url,
  message_body: 'hello world'
)

sleep 1

poll_queues_until { DT[:parsed_bodies].size >= 1 }

assert_equal(1, DT[:parsed_bodies].size)
assert_equal('Hash', DT[:body_classes].first)

parsed = DT[:parsed_bodies].first
assert_equal('hello world', parsed[:original])
assert_equal('HELLO WORLD', parsed[:transformed])
assert(parsed[:message_id], "Should include message_id from sqs_msg")
