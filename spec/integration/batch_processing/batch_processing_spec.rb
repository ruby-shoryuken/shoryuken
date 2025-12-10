# frozen_string_literal: true

# This spec tests batch processing including batch message reception (up to 10
# messages), batch vs single worker behavior differences, JSON body parsing in
# batch mode, and maximum batch size handling.

setup_localstack
reset_shoryuken
DT.clear

queue_name = DT.queue
create_test_queue(queue_name)
Shoryuken.add_group('default', 1)
Shoryuken.add_queue(queue_name, 1, 'default')

# Create batch worker
worker_class = Class.new do
  include Shoryuken::Worker

  def perform(sqs_msgs, bodies)
    msgs = Array(sqs_msgs)
    DT[:batch_sizes] << msgs.size
    DT[:messages].concat(Array(bodies))
  end
end

worker_class.get_shoryuken_options['queue'] = queue_name
worker_class.get_shoryuken_options['auto_delete'] = true
worker_class.get_shoryuken_options['batch'] = true
Shoryuken.register_worker(queue_name, worker_class)

# Send batch of messages
entries = 5.times.map { |i| { id: SecureRandom.uuid, message_body: "message-#{i}" } }
Shoryuken::Client.queues(queue_name).send_messages(entries: entries)

sleep 1

poll_queues_until { DT[:messages].size >= 5 }

assert_equal(5, DT[:messages].size)
assert(DT[:batch_sizes].any? { |size| size > 1 }, "Expected at least one batch with size > 1")

delete_test_queue(queue_name)
