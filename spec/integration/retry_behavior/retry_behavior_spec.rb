# frozen_string_literal: true

# This spec tests retry behavior including ApproximateReceiveCount tracking
# across message redeliveries.

require 'concurrent'

setup_localstack
reset_shoryuken
DT.clear

queue_name = DT.queue
# Create queue with short visibility timeout for faster retries
create_test_queue(queue_name, attributes: { 'VisibilityTimeout' => '2' })
Shoryuken.add_group('default', 1)
Shoryuken.add_queue(queue_name, 1, 'default')

# Atomic counter for fail tracking
fail_counter = Concurrent::AtomicFixnum.new(2)

# Create worker that fails twice then succeeds
worker_class = Class.new do
  include Shoryuken::Worker

  shoryuken_options auto_delete: false, batch: false

  define_method(:perform) do |sqs_msg, body|
    receive_count = sqs_msg.attributes['ApproximateReceiveCount'].to_i
    DT[:receive_counts] << receive_count

    if fail_counter.value > 0
      fail_counter.decrement
      raise "Simulated failure"
    else
      sqs_msg.delete
    end
  end
end

worker_class.get_shoryuken_options['queue'] = queue_name
Shoryuken.register_worker(queue_name, worker_class)

Shoryuken::Client.queues(queue_name).send_message(message_body: 'retry-count-test')

# Wait for multiple redeliveries
poll_queues_until(timeout: 20) { DT[:receive_counts].size >= 3 }

assert(DT[:receive_counts].size >= 3)
assert_equal(DT[:receive_counts], DT[:receive_counts].sort, "Receive counts should be increasing")
assert_equal(1, DT[:receive_counts].first)

delete_test_queue(queue_name)
