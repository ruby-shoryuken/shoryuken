# frozen_string_literal: true

# This spec tests the auto_delete middleware functionality.
# When auto_delete: true, messages should be automatically deleted after successful processing.

setup_localstack

queue_name = DT.queue
create_test_queue(queue_name)
Shoryuken.add_group('default', 1)
Shoryuken.add_queue(queue_name, 1, 'default')

auto_delete_worker = Class.new do
  include Shoryuken::Worker

  shoryuken_options auto_delete: true

  def perform(sqs_msg, body)
    DT[:auto_delete_processed] << { message_id: sqs_msg.message_id, body: body }
  end
end

auto_delete_worker.get_shoryuken_options['queue'] = queue_name
Shoryuken.register_worker(queue_name, auto_delete_worker)

queue_url = Shoryuken::Client.sqs.get_queue_url(queue_name: queue_name).queue_url

# Send a message
Shoryuken::Client.sqs.send_message(
  queue_url: queue_url,
  message_body: 'auto delete test'
)

sleep 1

# Process the message
poll_queues_until { DT[:auto_delete_processed].size >= 1 }

assert_equal(1, DT[:auto_delete_processed].size)
assert_equal('auto delete test', DT[:auto_delete_processed].first[:body])

# Wait a moment for deletion to complete
sleep 2

# Verify message was deleted - queue should be empty
attributes = Shoryuken::Client.sqs.get_queue_attributes(
  queue_url: queue_url,
  attribute_names: ['ApproximateNumberOfMessages', 'ApproximateNumberOfMessagesNotVisible']
).attributes

total_messages = attributes['ApproximateNumberOfMessages'].to_i +
                 attributes['ApproximateNumberOfMessagesNotVisible'].to_i
assert_equal(0, total_messages, "Message should be deleted when auto_delete: true")
