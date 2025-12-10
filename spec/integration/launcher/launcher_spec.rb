# frozen_string_literal: true

# This spec tests the Launcher's ability to consume messages from SQS queues,
# including single message consumption, batch consumption, and command workers.

require 'concurrent'

setup_localstack

# Use atomic counter for thread-safe message counting
message_counter = Concurrent::AtomicFixnum.new(0)

worker_class = Class.new do
  include Shoryuken::Worker

  shoryuken_options auto_delete: true

  define_method(:perform) do |sqs_msg, _body|
    message_counter.increment(Array(sqs_msg).size)
  end
end

queue_name = DT.queue

create_test_queue(queue_name)
Shoryuken.add_group('default', 1)
Shoryuken.add_queue(queue_name, 1, 'default')
worker_class.get_shoryuken_options['queue'] = queue_name
worker_class.get_shoryuken_options['batch'] = true
Shoryuken.register_worker(queue_name, worker_class)

# Send batch of messages
entries = 10.times.map { |i| { id: SecureRandom.uuid, message_body: i.to_s } }
Shoryuken::Client.queues(queue_name).send_messages(entries: entries)

# Give the messages a chance to hit the queue
sleep 2

poll_queues_until { message_counter.value > 0 }

assert(message_counter.value > 1, "Expected more than 1 message in batch, got #{message_counter.value}")
