#!/usr/bin/env ruby
# frozen_string_literal: true

# This spec tests concurrent message processing with multiple processors.

require 'shoryuken'
require 'concurrent'

setup_localstack
reset_shoryuken

queue_name = "concurrent-test-#{SecureRandom.uuid}"
create_test_queue(queue_name)
Shoryuken.add_group('concurrent', 5) # 5 concurrent processors
Shoryuken.add_queue(queue_name, 1, 'concurrent')

# Create tracking worker with atomic counters
worker_class = Class.new do
  include Shoryuken::Worker

  class << self
    attr_accessor :processing_times, :concurrent_count, :max_concurrent
  end

  shoryuken_options auto_delete: true, batch: false

  def perform(sqs_msg, body)
    self.class.concurrent_count.increment
    current = self.class.concurrent_count.value
    self.class.max_concurrent.update { |max| [max, current].max }

    sleep 0.5 # Simulate work

    self.class.processing_times ||= []
    self.class.processing_times << Time.now

    self.class.concurrent_count.decrement
  end
end

worker_class.get_shoryuken_options['queue'] = queue_name
worker_class.processing_times = []
worker_class.concurrent_count = Concurrent::AtomicFixnum.new(0)
worker_class.max_concurrent = Concurrent::AtomicFixnum.new(0)
Shoryuken.register_worker(queue_name, worker_class)

# Send multiple messages
10.times { |i| Shoryuken::Client.queues(queue_name).send_message(message_body: "msg-#{i}") }

poll_queues_until(timeout: 20) { worker_class.processing_times.size >= 10 }

assert_equal(10, worker_class.processing_times.size)
# With multiple processors, we should see concurrency > 1
assert(worker_class.max_concurrent.value > 1, "Expected concurrency > 1, got #{worker_class.max_concurrent.value}")

delete_test_queue(queue_name)
