#!/usr/bin/env ruby
# frozen_string_literal: true

# This spec tests polling strategies including WeightedRoundRobin (default),
# StrictPriority, queue pause/unpause behavior on empty queues, and
# multi-queue worker message distribution.

require 'shoryuken'

def create_multi_queue_worker(queues)
  worker_class = Class.new do
    include Shoryuken::Worker

    class << self
      attr_accessor :messages_by_queue, :processing_order
    end

    shoryuken_options auto_delete: true, batch: false

    def perform(sqs_msg, body)
      queue = sqs_msg.queue_url.split('/').last
      self.class.messages_by_queue ||= {}
      self.class.messages_by_queue[queue] ||= []
      self.class.messages_by_queue[queue] << body
      self.class.processing_order ||= []
      self.class.processing_order << queue
    end

    def self.total_messages
      (messages_by_queue || {}).values.flatten.size
    end
  end

  queues.each do |queue|
    worker_class.get_shoryuken_options['queue'] = queue
    Shoryuken.register_worker(queue, worker_class)
  end

  worker_class.messages_by_queue = {}
  worker_class.processing_order = []
  worker_class
end

def create_polling_simple_worker(queue)
  worker_class = Class.new do
    include Shoryuken::Worker

    class << self
      attr_accessor :received_messages
    end

    shoryuken_options auto_delete: true, batch: false

    def perform(sqs_msg, body)
      self.class.received_messages ||= []
      self.class.received_messages << body
    end
  end

  worker_class.get_shoryuken_options['queue'] = queue
  worker_class.received_messages = []
  Shoryuken.register_worker(queue, worker_class)
  worker_class
end

run_test_suite "Polling Strategies Integration" do
  run_test "processes messages from multiple queues (weighted round robin)" do
    setup_localstack
    reset_shoryuken

    queue_prefix = "polling-#{SecureRandom.uuid[0..7]}"
    queue_high = "#{queue_prefix}-high"
    queue_medium = "#{queue_prefix}-medium"
    queue_low = "#{queue_prefix}-low"

    [queue_high, queue_medium, queue_low].each { |q| create_test_queue(q) }

    Shoryuken.add_group('default', 1)
    # Higher weight = higher priority
    Shoryuken.add_queue(queue_high, 3, 'default')
    Shoryuken.add_queue(queue_medium, 2, 'default')
    Shoryuken.add_queue(queue_low, 1, 'default')

    begin
      worker = create_multi_queue_worker([queue_high, queue_medium, queue_low])
      worker.messages_by_queue = {}

      # Send messages to all queues
      Shoryuken::Client.queues(queue_high).send_message(message_body: 'high-msg')
      Shoryuken::Client.queues(queue_medium).send_message(message_body: 'medium-msg')
      Shoryuken::Client.queues(queue_low).send_message(message_body: 'low-msg')

      sleep 1

      poll_queues_until { worker.total_messages >= 3 }

      assert_equal(3, worker.messages_by_queue.keys.size)
      assert_equal(3, worker.total_messages)
    ensure
      [queue_high, queue_medium, queue_low].each { |q| delete_test_queue(q) }
      teardown_localstack
    end
  end

  run_test "favors higher weight queues (weighted round robin)" do
    setup_localstack
    reset_shoryuken

    queue_prefix = "polling-#{SecureRandom.uuid[0..7]}"
    queue_high = "#{queue_prefix}-high"
    queue_medium = "#{queue_prefix}-medium"
    queue_low = "#{queue_prefix}-low"

    [queue_high, queue_medium, queue_low].each { |q| create_test_queue(q) }

    Shoryuken.add_group('default', 1)
    Shoryuken.add_queue(queue_high, 3, 'default')
    Shoryuken.add_queue(queue_medium, 2, 'default')
    Shoryuken.add_queue(queue_low, 1, 'default')

    begin
      worker = create_multi_queue_worker([queue_high, queue_medium, queue_low])
      worker.messages_by_queue = {}
      worker.processing_order = []

      # Send multiple messages to each queue
      3.times { Shoryuken::Client.queues(queue_high).send_message(message_body: 'high') }
      3.times { Shoryuken::Client.queues(queue_medium).send_message(message_body: 'medium') }
      3.times { Shoryuken::Client.queues(queue_low).send_message(message_body: 'low') }

      sleep 1

      poll_queues_until(timeout: 20) { worker.total_messages >= 9 }

      assert_equal(9, worker.total_messages)

      # High priority queue should generally be processed more frequently early on
      first_five = worker.processing_order.first(5)
      high_count = first_five.count { |q| q.include?('high') }
      assert(high_count >= 2, "Expected at least 2 high-priority messages in first 5, got #{high_count}")
    ensure
      [queue_high, queue_medium, queue_low].each { |q| delete_test_queue(q) }
      teardown_localstack
    end
  end

  run_test "processes higher priority queues first (strict priority)" do
    setup_localstack
    reset_shoryuken

    queue_prefix = "polling-#{SecureRandom.uuid[0..7]}"
    queue_high = "#{queue_prefix}-high"
    queue_medium = "#{queue_prefix}-medium"
    queue_low = "#{queue_prefix}-low"

    [queue_high, queue_medium, queue_low].each { |q| create_test_queue(q) }

    Shoryuken.add_group('strict', 1)
    Shoryuken.groups['strict'][:polling_strategy] = Shoryuken::Polling::StrictPriority

    # Order matters for strict priority
    Shoryuken.add_queue(queue_high, 1, 'strict')
    Shoryuken.add_queue(queue_medium, 1, 'strict')
    Shoryuken.add_queue(queue_low, 1, 'strict')

    begin
      worker = create_multi_queue_worker([queue_high, queue_medium, queue_low])
      worker.messages_by_queue = {}
      worker.processing_order = []

      # Send to all queues
      Shoryuken::Client.queues(queue_low).send_message(message_body: 'low')
      Shoryuken::Client.queues(queue_medium).send_message(message_body: 'medium')
      Shoryuken::Client.queues(queue_high).send_message(message_body: 'high')

      sleep 1

      poll_queues_until { worker.total_messages >= 3 }

      assert(worker.processing_order.first.include?('high'), "Expected high-priority queue first")
    ensure
      [queue_high, queue_medium, queue_low].each { |q| delete_test_queue(q) }
      teardown_localstack
    end
  end

  run_test "continues polling after empty queue" do
    setup_localstack
    reset_shoryuken

    queue_high = "polling-#{SecureRandom.uuid[0..7]}-high"
    create_test_queue(queue_high)
    Shoryuken.add_group('default', 1)
    Shoryuken.add_queue(queue_high, 1, 'default')

    begin
      worker = create_polling_simple_worker(queue_high)
      worker.received_messages = []

      # Start with empty queue, then add message after delay
      Thread.new do
        sleep 2
        Shoryuken::Client.queues(queue_high).send_message(message_body: 'delayed-msg')
      end

      poll_queues_until(timeout: 10) { worker.received_messages.size >= 1 }

      assert_equal(1, worker.received_messages.size)
    ensure
      delete_test_queue(queue_high)
      teardown_localstack
    end
  end
end
