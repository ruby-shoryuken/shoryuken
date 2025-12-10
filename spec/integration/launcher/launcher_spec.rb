#!/usr/bin/env ruby
# frozen_string_literal: true

# This spec tests the Launcher's ability to consume messages from SQS queues,
# including single message consumption, batch consumption, and command workers.

require 'shoryuken'

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

  def self.received_messages=(received_messages)
    @@received_messages = received_messages
  end
end

run_test_suite "Launcher Message Consumption" do
  run_test "consumes as a command worker" do
    setup_localstack
    reset_shoryuken

    StandardWorker.received_messages = 0
    queue = "shoryuken-travis-#{StandardWorker}-#{SecureRandom.uuid}"

    create_test_queue(queue)
    Shoryuken.add_group('default', 1)
    Shoryuken.add_queue(queue, 1, 'default')
    StandardWorker.get_shoryuken_options['queue'] = queue
    Shoryuken.register_worker(queue, StandardWorker)

    begin
      StandardWorker.perform_async('Yo')
      poll_queues_until { StandardWorker.received_messages > 0 }
      assert_equal(1, StandardWorker.received_messages)
    ensure
      delete_test_queue(queue)
      teardown_localstack
    end
  end

  run_test "consumes a single message" do
    setup_localstack
    reset_shoryuken

    StandardWorker.received_messages = 0
    queue = "shoryuken-travis-#{StandardWorker}-#{SecureRandom.uuid}"

    create_test_queue(queue)
    Shoryuken.add_group('default', 1)
    Shoryuken.add_queue(queue, 1, 'default')
    StandardWorker.get_shoryuken_options['queue'] = queue
    StandardWorker.get_shoryuken_options['batch'] = false
    Shoryuken.register_worker(queue, StandardWorker)

    begin
      Shoryuken::Client.queues(queue).send_message(message_body: 'Yo')
      poll_queues_until { StandardWorker.received_messages > 0 }
      assert_equal(1, StandardWorker.received_messages)
    ensure
      delete_test_queue(queue)
      teardown_localstack
    end
  end

  run_test "consumes a batch" do
    setup_localstack
    reset_shoryuken

    StandardWorker.received_messages = 0
    queue = "shoryuken-travis-#{StandardWorker}-#{SecureRandom.uuid}"

    create_test_queue(queue)
    Shoryuken.add_group('default', 1)
    Shoryuken.add_queue(queue, 1, 'default')
    StandardWorker.get_shoryuken_options['queue'] = queue
    StandardWorker.get_shoryuken_options['batch'] = true
    Shoryuken.register_worker(queue, StandardWorker)

    begin
      entries = 10.times.map { |i| { id: SecureRandom.uuid, message_body: i.to_s } }
      Shoryuken::Client.queues(queue).send_messages(entries: entries)

      # Give the messages a chance to hit the queue so they are all available at the same time
      sleep 2

      poll_queues_until { StandardWorker.received_messages > 0 }
      assert(StandardWorker.received_messages > 1, "Expected more than 1 message in batch, got #{StandardWorker.received_messages}")
    ensure
      delete_test_queue(queue)
      teardown_localstack
    end
  end
end
