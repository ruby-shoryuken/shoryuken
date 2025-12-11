# frozen_string_literal: true

# This spec tests the auto_visibility_timeout middleware functionality.
# When auto_visibility_timeout: true, the message visibility timeout should be
# automatically extended during long-running job processing to prevent re-delivery.

setup_localstack

queue_name = DT.uuid

# Create queue with short visibility timeout (10 seconds)
create_test_queue(queue_name, attributes: { 'VisibilityTimeout' => '10' })
Shoryuken.add_group('default', 1)
Shoryuken.add_queue(queue_name, 1, 'default')

# Worker with auto_visibility_timeout enabled that takes longer than visibility timeout
auto_visibility_worker = Class.new do
  include Shoryuken::Worker

  shoryuken_options auto_visibility_timeout: true, auto_delete: true

  def perform(sqs_msg, body)
    DT[:processing_started] << Time.now
    # Sleep longer than the queue's visibility timeout (10s)
    # The middleware should extend visibility before it expires
    sleep 12
    DT[:processing_completed] << Time.now
    DT[:processed_messages] << { message_id: sqs_msg.message_id, body: body }
  end
end

auto_visibility_worker.get_shoryuken_options['queue'] = queue_name
Shoryuken.register_worker(queue_name, auto_visibility_worker)

queue_url = Shoryuken::Client.sqs.get_queue_url(queue_name: queue_name).queue_url

# Send a message
Shoryuken::Client.sqs.send_message(
  queue_url: queue_url,
  message_body: 'long running job'
)

sleep 1

# Process the message - this should take ~12 seconds but not fail
poll_queues_until(timeout: 30) { DT[:processed_messages].size >= 1 }

# Verify message was processed exactly once (visibility was extended, not re-delivered)
assert_equal(1, DT[:processed_messages].size, "Message should be processed exactly once")
assert_equal('long running job', DT[:processed_messages].first[:body])

# Verify processing took longer than the visibility timeout
processing_time = DT[:processing_completed].first - DT[:processing_started].first
assert(processing_time >= 12, "Processing should have taken at least 12 seconds")

# Cleanup
delete_test_queue(queue_name)
