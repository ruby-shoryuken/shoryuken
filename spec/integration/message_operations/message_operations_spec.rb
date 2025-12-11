# frozen_string_literal: true

# This spec tests message operations from within a worker:
# - sqs_msg.delete - manually delete a message
# - sqs_msg.change_visibility - change visibility with options

setup_localstack

queue_name = DT.queue
create_test_queue(queue_name, attributes: { 'VisibilityTimeout' => '5' })
Shoryuken.add_group('default', 1)
Shoryuken.add_queue(queue_name, 1, 'default')

# Worker that tests message operations
message_ops_worker = Class.new do
  include Shoryuken::Worker

  shoryuken_options auto_delete: false

  def perform(sqs_msg, body)
    DT[:processed] << { message_id: sqs_msg.message_id, body: body }

    # Test sqs_msg.change_visibility method
    sqs_msg.change_visibility(visibility_timeout: 60)
    DT[:extended] << sqs_msg.message_id

    # Manually delete the message
    sqs_msg.delete
    DT[:deleted] << sqs_msg.message_id
  end
end

message_ops_worker.get_shoryuken_options['queue'] = queue_name
Shoryuken.register_worker(queue_name, message_ops_worker)

queue_url = Shoryuken::Client.sqs.get_queue_url(queue_name: queue_name).queue_url

# Test: Message operations - change_visibility and delete
Shoryuken::Client.sqs.send_message(
  queue_url: queue_url,
  message_body: 'message ops test'
)

sleep 1
poll_queues_until { DT[:deleted].size >= 1 }

# Verify message was processed
assert_equal(1, DT[:processed].size)
assert_equal('message ops test', DT[:processed].first[:body])

# Verify visibility was extended
assert_equal(1, DT[:extended].size, "Visibility should have been extended")

# Verify message was deleted
assert_equal(1, DT[:deleted].size, "Message should have been deleted")

# Verify message was deleted - should not be reprocessed
sleep 2
assert_equal(1, DT[:processed].size, "Deleted message should only be processed once")
