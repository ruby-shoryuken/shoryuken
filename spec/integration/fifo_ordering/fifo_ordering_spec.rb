#!/usr/bin/env ruby
# frozen_string_literal: true

# This spec tests FIFO queue ordering guarantees including message ordering
# within the same message group, processing across multiple message groups,
# deduplication within the 5-minute window, and batch processing on FIFO queues.

require 'shoryuken'

def create_fifo_worker(queue)
  worker_class = Class.new do
    include Shoryuken::Worker

    class << self
      attr_accessor :received_messages, :processing_order, :groups_seen, :messages_by_group
    end

    def perform(sqs_msg, body)
      self.class.received_messages ||= []
      self.class.received_messages << body

      self.class.processing_order ||= []
      self.class.processing_order << Time.now

      # Extract group from message attributes if available
      group = sqs_msg.message_attributes&.dig('message_group_id', 'string_value')
      group ||= body.split('-')[0..1].join('-') if body.include?('-')

      self.class.groups_seen ||= []
      self.class.groups_seen << group if group

      self.class.messages_by_group ||= {}
      if group
        self.class.messages_by_group[group] ||= []
        self.class.messages_by_group[group] << body
      end
    end
  end

  # Set options before registering to avoid default queue conflicts
  worker_class.get_shoryuken_options['queue'] = queue
  worker_class.get_shoryuken_options['auto_delete'] = true
  worker_class.get_shoryuken_options['batch'] = false
  worker_class.received_messages = []
  worker_class.processing_order = []
  worker_class.groups_seen = []
  worker_class.messages_by_group = {}
  Shoryuken.register_worker(queue, worker_class)
  worker_class
end

def create_fifo_batch_worker(queue)
  worker_class = Class.new do
    include Shoryuken::Worker

    class << self
      attr_accessor :received_messages, :batch_sizes
    end

    def perform(sqs_msgs, bodies)
      self.class.batch_sizes ||= []
      self.class.batch_sizes << Array(bodies).size

      self.class.received_messages ||= []
      self.class.received_messages.concat(Array(bodies))
    end
  end

  # Set options before registering to avoid default queue conflicts
  worker_class.get_shoryuken_options['queue'] = queue
  worker_class.get_shoryuken_options['auto_delete'] = true
  worker_class.get_shoryuken_options['batch'] = true
  worker_class.received_messages = []
  worker_class.batch_sizes = []
  Shoryuken.register_worker(queue, worker_class)
  worker_class
end

run_test_suite "FIFO Queue Ordering Integration" do
  run_test "maintains order for messages in same group" do
    setup_localstack
    reset_shoryuken

    queue_name = "fifo-test-#{SecureRandom.uuid[0..7]}.fifo"
    create_fifo_queue(queue_name)
    Shoryuken.add_group('default', 1)
    Shoryuken.add_queue(queue_name, 1, 'default')

    begin
      worker = create_fifo_worker(queue_name)
      worker.received_messages = []
      worker.processing_order = []

      queue_url = Shoryuken::Client.sqs.get_queue_url(queue_name: queue_name).queue_url

      # Send ordered messages with same group
      5.times do |i|
        Shoryuken::Client.sqs.send_message(
          queue_url: queue_url,
          message_body: "msg-#{i}",
          message_group_id: 'group-a',
          message_deduplication_id: SecureRandom.uuid
        )
      end

      sleep 1

      poll_queues_until { worker.received_messages.size >= 5 }

      assert_equal(5, worker.received_messages.size)

      # Verify ordering
      expected = (0..4).map { |i| "msg-#{i}" }
      assert_equal(expected, worker.received_messages)
    ensure
      delete_test_queue(queue_name)
      teardown_localstack
    end
  end

  run_test "processes messages from different groups" do
    setup_localstack
    reset_shoryuken

    queue_name = "fifo-test-#{SecureRandom.uuid[0..7]}.fifo"
    create_fifo_queue(queue_name)
    Shoryuken.add_group('default', 1)
    Shoryuken.add_queue(queue_name, 1, 'default')

    begin
      worker = create_fifo_worker(queue_name)
      worker.received_messages = []
      worker.groups_seen = []

      queue_url = Shoryuken::Client.sqs.get_queue_url(queue_name: queue_name).queue_url

      # Send messages to different groups
      %w[group-a group-b group-c].each do |group|
        2.times do |i|
          Shoryuken::Client.sqs.send_message(
            queue_url: queue_url,
            message_body: "#{group}-msg-#{i}",
            message_group_id: group,
            message_deduplication_id: SecureRandom.uuid
          )
        end
      end

      sleep 1

      poll_queues_until(timeout: 20) { worker.received_messages.size >= 6 }

      assert_equal(6, worker.received_messages.size)
      assert_equal(3, worker.groups_seen.uniq.size)
    ensure
      delete_test_queue(queue_name)
      teardown_localstack
    end
  end

  run_test "maintains order within each group" do
    setup_localstack
    reset_shoryuken

    queue_name = "fifo-test-#{SecureRandom.uuid[0..7]}.fifo"
    create_fifo_queue(queue_name)
    Shoryuken.add_group('default', 1)
    Shoryuken.add_queue(queue_name, 1, 'default')

    begin
      worker = create_fifo_worker(queue_name)
      worker.received_messages = []
      worker.messages_by_group = {}

      queue_url = Shoryuken::Client.sqs.get_queue_url(queue_name: queue_name).queue_url

      # Send ordered messages to multiple groups
      %w[group-x group-y].each do |group|
        3.times do |i|
          Shoryuken::Client.sqs.send_message(
            queue_url: queue_url,
            message_body: "#{group}-#{i}",
            message_group_id: group,
            message_deduplication_id: SecureRandom.uuid
          )
        end
      end

      sleep 1

      poll_queues_until(timeout: 20) { worker.received_messages.size >= 6 }

      # Check order within each group
      group_x_messages = worker.messages_by_group['group-x'] || []
      group_y_messages = worker.messages_by_group['group-y'] || []

      assert_equal(%w[group-x-0 group-x-1 group-x-2], group_x_messages)
      assert_equal(%w[group-y-0 group-y-1 group-y-2], group_y_messages)
    ensure
      delete_test_queue(queue_name)
      teardown_localstack
    end
  end

  run_test "deduplicates messages with same deduplication ID" do
    setup_localstack
    reset_shoryuken

    queue_name = "fifo-test-#{SecureRandom.uuid[0..7]}.fifo"
    create_fifo_queue(queue_name)
    Shoryuken.add_group('default', 1)
    Shoryuken.add_queue(queue_name, 1, 'default')

    begin
      worker = create_fifo_worker(queue_name)
      worker.received_messages = []

      queue_url = Shoryuken::Client.sqs.get_queue_url(queue_name: queue_name).queue_url
      dedup_id = SecureRandom.uuid

      # Send same message multiple times with same deduplication ID
      3.times do
        Shoryuken::Client.sqs.send_message(
          queue_url: queue_url,
          message_body: 'duplicate-msg',
          message_group_id: 'dedup-group',
          message_deduplication_id: dedup_id
        )
      end

      sleep 2

      poll_queues_until(timeout: 10) { worker.received_messages.size >= 1 }

      # Wait a bit more to ensure no more messages come through
      sleep 2

      # Should only receive one message due to deduplication
      assert_equal(1, worker.received_messages.size)
    ensure
      delete_test_queue(queue_name)
      teardown_localstack
    end
  end

  run_test "allows batch processing on FIFO queues" do
    setup_localstack
    reset_shoryuken

    queue_name = "fifo-test-#{SecureRandom.uuid[0..7]}.fifo"
    create_fifo_queue(queue_name)
    Shoryuken.add_group('default', 1)
    Shoryuken.add_queue(queue_name, 1, 'default')

    begin
      worker = create_fifo_batch_worker(queue_name)
      worker.received_messages = []
      worker.batch_sizes = []

      queue_url = Shoryuken::Client.sqs.get_queue_url(queue_name: queue_name).queue_url

      # Send messages
      5.times do |i|
        Shoryuken::Client.sqs.send_message(
          queue_url: queue_url,
          message_body: "batch-fifo-#{i}",
          message_group_id: 'batch-group',
          message_deduplication_id: SecureRandom.uuid
        )
      end

      sleep 1

      poll_queues_until { worker.received_messages.size >= 5 }

      assert_equal(5, worker.received_messages.size)
    ensure
      delete_test_queue(queue_name)
      teardown_localstack
    end
  end
end
