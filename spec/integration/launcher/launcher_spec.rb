#!/usr/bin/env ruby
# frozen_string_literal: true

# This spec tests the Launcher's ability to consume messages from SQS queues,
# including single message consumption, batch consumption, and command workers.

require 'shoryuken'

setup_localstack
reset_shoryuken

class StandardWorker
  include Shoryuken::Worker

  @@received_messages = 0

  shoryuken_options auto_delete: true

  def perform(sqs_msg, _body)
    @@received_messages += Array(sqs_msg).size
  end

  def self.received_messages
    @@received_messages
  end

  def self.received_messages=(val)
    @@received_messages = val
  end
end

queue = "shoryuken-launcher-#{SecureRandom.uuid}"

create_test_queue(queue)
Shoryuken.add_group('default', 1)
Shoryuken.add_queue(queue, 1, 'default')
StandardWorker.get_shoryuken_options['queue'] = queue
StandardWorker.get_shoryuken_options['batch'] = true
Shoryuken.register_worker(queue, StandardWorker)

# Send batch of messages
entries = 10.times.map { |i| { id: SecureRandom.uuid, message_body: i.to_s } }
Shoryuken::Client.queues(queue).send_messages(entries: entries)

# Give the messages a chance to hit the queue
sleep 2

poll_queues_until { StandardWorker.received_messages > 0 }

assert(StandardWorker.received_messages > 1, "Expected more than 1 message in batch, got #{StandardWorker.received_messages}")

delete_test_queue(queue)
