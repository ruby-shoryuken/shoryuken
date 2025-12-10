# frozen_string_literal: true

# This spec tests worker lifecycle including worker registration and discovery.

setup_localstack

queue_name = DT.queue
create_test_queue(queue_name)
Shoryuken.add_group('default', 1)
Shoryuken.add_queue(queue_name, 1, 'default')

# Create simple worker
worker_class = Class.new do
  include Shoryuken::Worker

  def perform(sqs_msg, body)
    DT[:messages] << body
  end
end

worker_class.get_shoryuken_options['queue'] = queue_name
worker_class.get_shoryuken_options['auto_delete'] = true
worker_class.get_shoryuken_options['batch'] = false
Shoryuken.register_worker(queue_name, worker_class)

# Verify worker is registered
registered = Shoryuken.worker_registry.workers(queue_name)
assert_includes(registered, worker_class)

# Send and process a message
Shoryuken::Client.queues(queue_name).send_message(message_body: 'lifecycle-test')

poll_queues_until { DT[:messages].size >= 1 }

assert_equal(1, DT[:messages].size)
assert_equal('lifecycle-test', DT[:messages].first)
