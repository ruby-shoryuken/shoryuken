# frozen_string_literal: true

# This spec tests the body_parser option with :json setting
# Verifies that JSON messages are automatically parsed into Ruby hashes

setup_localstack

queue_name = DT.uuid
create_test_queue(queue_name)
Shoryuken.add_group('default', 1)
Shoryuken.add_queue(queue_name, 1, 'default')

worker_class = Class.new do
  include Shoryuken::Worker

  shoryuken_options body_parser: :json

  def perform(sqs_msg, body)
    DT[:parsed_bodies] << body
    DT[:body_classes] << body.class.name
  end
end

worker_class.get_shoryuken_options['queue'] = queue_name
worker_class.get_shoryuken_options['auto_delete'] = true
Shoryuken.register_worker(queue_name, worker_class)

queue_url = Shoryuken::Client.sqs.get_queue_url(queue_name: queue_name).queue_url

# Send a JSON message
json_body = { 'name' => 'test', 'value' => 42, 'nested' => { 'key' => 'val' } }
Shoryuken::Client.sqs.send_message(
  queue_url: queue_url,
  message_body: JSON.dump(json_body)
)

sleep 1

poll_queues_until { DT[:parsed_bodies].size >= 1 }

assert_equal(1, DT[:parsed_bodies].size)
assert_equal('Hash', DT[:body_classes].first)
assert_equal('test', DT[:parsed_bodies].first['name'])
assert_equal(42, DT[:parsed_bodies].first['value'])
assert_equal('val', DT[:parsed_bodies].first['nested']['key'])
