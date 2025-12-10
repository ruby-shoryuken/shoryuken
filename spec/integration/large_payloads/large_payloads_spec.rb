# frozen_string_literal: true

# This spec tests large payload handling including payloads near the 256KB SQS limit.

setup_localstack

queue_name = DT.queue
create_test_queue(queue_name)
Shoryuken.add_group('default', 1)
Shoryuken.add_queue(queue_name, 1, 'default')

# Create worker that captures message bodies
worker_class = Class.new do
  include Shoryuken::Worker

  def perform(sqs_msg, body)
    DT[:bodies] << body
  end
end

worker_class.get_shoryuken_options['queue'] = queue_name
worker_class.get_shoryuken_options['auto_delete'] = true
worker_class.get_shoryuken_options['batch'] = false
Shoryuken.register_worker(queue_name, worker_class)

# Send large payload (250KB, near SQS limit)
payload = 'x' * (250 * 1024)
Shoryuken::Client.queues(queue_name).send_message(message_body: payload)

poll_queues_until { DT[:bodies].size >= 1 }

assert_equal(250 * 1024, DT[:bodies].first.size)
