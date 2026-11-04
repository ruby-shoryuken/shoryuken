# frozen_string_literal: true

# This spec tests concurrent message processing with multiple processors.

setup_sqs

queue_name = DT.queue
create_test_queue(queue_name)
Shoryuken.add_group('concurrent', 5) # 5 concurrent processors
Shoryuken.add_queue(queue_name, 1, 'concurrent')

# Atomic counter for tracking concurrency
concurrent_count = Shoryuken::Helpers::AtomicCounter.new(0)

worker_class = Class.new do
  include Shoryuken::Worker

  shoryuken_options auto_delete: true, batch: false

  define_method(:perform) do |_sqs_msg, _body|
    DT[:concurrency] << concurrent_count.increment

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
assert(DT[:concurrency].max > 1, "Expected concurrency > 1, got #{DT[:concurrency].max}")
