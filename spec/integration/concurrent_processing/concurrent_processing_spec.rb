# frozen_string_literal: true

# This spec tests concurrent message processing with multiple processors.

require 'concurrent'

setup_localstack

queue_name = DT.queue
create_test_queue(queue_name)
Shoryuken.add_group('concurrent', 5) # 5 concurrent processors
Shoryuken.add_queue(queue_name, 1, 'concurrent')

# Atomic counters for tracking concurrency
concurrent_count = Concurrent::AtomicFixnum.new(0)
max_concurrent = Concurrent::AtomicFixnum.new(0)

worker_class = Class.new do
  include Shoryuken::Worker

  shoryuken_options auto_delete: true, batch: false

  define_method(:perform) do |sqs_msg, body|
    concurrent_count.increment
    current = concurrent_count.value
    max_concurrent.update { |max| [max, current].max }

    sleep 0.5 # Simulate work

    DT[:processing_times] << Time.now

    concurrent_count.decrement
  end
end

worker_class.get_shoryuken_options['queue'] = queue_name
Shoryuken.register_worker(queue_name, worker_class)

10.times { |i| Shoryuken::Client.queues(queue_name).send_message(message_body: "msg-#{i}") }

poll_queues_until(timeout: 20) { DT[:processing_times].size >= 10 }

assert_equal(10, DT[:processing_times].size)
# With multiple processors, we should see concurrency > 1
assert(max_concurrent.value > 1, "Expected concurrency > 1, got #{max_concurrent.value}")
