# frozen_string_literal: true

# This spec tests visibility timeout management including manual visibility
# extension during long processing.

setup_localstack

queue_name = DT.queue
create_test_queue(queue_name, attributes: { 'VisibilityTimeout' => '5' })
Shoryuken.add_group('default', 1)
Shoryuken.add_queue(queue_name, 1, 'default')

# Create slow worker that extends visibility
worker_class = Class.new do
  include Shoryuken::Worker

  def perform(sqs_msg, body)
    # Extend visibility before long processing
    sqs_msg.change_visibility(visibility_timeout: 30)
    DT[:visibility_extended] << true

    sleep 2 # Simulate slow processing

    DT[:messages] << body
  end
end

worker_class.get_shoryuken_options['queue'] = queue_name
worker_class.get_shoryuken_options['auto_delete'] = true
worker_class.get_shoryuken_options['batch'] = false
Shoryuken.register_worker(queue_name, worker_class)

Shoryuken::Client.queues(queue_name).send_message(message_body: 'extend-test')

poll_queues_until { DT[:messages].size >= 1 }

assert_equal(1, DT[:messages].size)
assert(DT[:visibility_extended].any?, "Expected visibility to be extended")
