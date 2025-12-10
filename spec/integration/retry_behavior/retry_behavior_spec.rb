#!/usr/bin/env ruby
# frozen_string_literal: true

# This spec tests retry behavior including ApproximateReceiveCount tracking
# across message redeliveries.

require 'shoryuken'

setup_localstack
reset_shoryuken

queue_name = "retry-test-#{SecureRandom.uuid}"
# Create queue with short visibility timeout for faster retries
create_test_queue(queue_name, attributes: { 'VisibilityTimeout' => '2' })
Shoryuken.add_group('default', 1)
Shoryuken.add_queue(queue_name, 1, 'default')

# Create worker that fails twice then succeeds
worker_class = Class.new do
  include Shoryuken::Worker

  class << self
    attr_accessor :receive_counts, :fail_times_remaining
  end

  shoryuken_options auto_delete: false, batch: false

  def perform(sqs_msg, body)
    receive_count = sqs_msg.attributes['ApproximateReceiveCount'].to_i
    self.class.receive_counts ||= []
    self.class.receive_counts << receive_count

    if self.class.fail_times_remaining > 0
      self.class.fail_times_remaining -= 1
      raise "Simulated failure"
    else
      sqs_msg.delete
    end
  end
end

worker_class.get_shoryuken_options['queue'] = queue_name
worker_class.receive_counts = []
worker_class.fail_times_remaining = 2
Shoryuken.register_worker(queue_name, worker_class)

Shoryuken::Client.queues(queue_name).send_message(message_body: 'retry-count-test')

# Wait for multiple redeliveries
poll_queues_until(timeout: 20) { worker_class.receive_counts.size >= 3 }

assert(worker_class.receive_counts.size >= 3)
assert_equal(worker_class.receive_counts, worker_class.receive_counts.sort, "Receive counts should be increasing")
assert_equal(1, worker_class.receive_counts.first)

delete_test_queue(queue_name)
teardown_localstack
