#!/usr/bin/env ruby
# frozen_string_literal: true

# This spec tests worker lifecycle including worker registration and discovery.

require 'shoryuken'

setup_localstack
reset_shoryuken

queue_name = "lifecycle-test-#{SecureRandom.uuid}"
create_test_queue(queue_name)
Shoryuken.add_group('default', 1)
Shoryuken.add_queue(queue_name, 1, 'default')

# Create simple worker
worker_class = Class.new do
  include Shoryuken::Worker

  class << self
    attr_accessor :received_messages
  end

  def perform(sqs_msg, body)
    self.class.received_messages ||= []
    self.class.received_messages << body
  end
end

worker_class.get_shoryuken_options['queue'] = queue_name
worker_class.get_shoryuken_options['auto_delete'] = true
worker_class.get_shoryuken_options['batch'] = false
worker_class.received_messages = []
Shoryuken.register_worker(queue_name, worker_class)

# Verify worker is registered
registered = Shoryuken.worker_registry.workers(queue_name)
assert_includes(registered, worker_class)

# Send and process a message
Shoryuken::Client.queues(queue_name).send_message(message_body: 'lifecycle-test')

poll_queues_until { worker_class.received_messages.size >= 1 }

assert_equal(1, worker_class.received_messages.size)
assert_equal('lifecycle-test', worker_class.received_messages.first)

delete_test_queue(queue_name)
teardown_localstack
