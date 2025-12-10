#!/usr/bin/env ruby
# frozen_string_literal: true

# This spec tests batch processing including batch message reception (up to 10
# messages), batch vs single worker behavior differences, JSON body parsing in
# batch mode, and maximum batch size handling.

require 'shoryuken'

def create_batch_worker(queue)
  worker_class = Class.new do
    include Shoryuken::Worker

    class << self
      attr_accessor :received_messages, :batch_sizes
    end

    def perform(sqs_msgs, bodies)
      msgs = Array(sqs_msgs)
      self.class.batch_sizes ||= []
      self.class.batch_sizes << msgs.size
      self.class.received_messages ||= []
      self.class.received_messages.concat(Array(bodies))
    end
  end

  worker_class.get_shoryuken_options['queue'] = queue
  worker_class.get_shoryuken_options['auto_delete'] = true
  worker_class.get_shoryuken_options['batch'] = true
  worker_class.received_messages = []
  worker_class.batch_sizes = []
  Shoryuken.register_worker(queue, worker_class)
  worker_class
end

def create_single_worker(queue)
  worker_class = Class.new do
    include Shoryuken::Worker

    class << self
      attr_accessor :received_messages, :batch_sizes
    end

    def perform(sqs_msg, body)
      self.class.batch_sizes ||= []
      self.class.batch_sizes << 1
      self.class.received_messages ||= []
      self.class.received_messages << body
    end
  end

  worker_class.get_shoryuken_options['queue'] = queue
  worker_class.get_shoryuken_options['auto_delete'] = true
  worker_class.get_shoryuken_options['batch'] = false
  worker_class.received_messages = []
  worker_class.batch_sizes = []
  Shoryuken.register_worker(queue, worker_class)
  worker_class
end

def create_json_batch_worker(queue)
  worker_class = Class.new do
    include Shoryuken::Worker

    class << self
      attr_accessor :received_messages
    end

    def perform(sqs_msgs, bodies)
      self.class.received_messages ||= []
      self.class.received_messages.concat(Array(bodies))
    end
  end

  worker_class.get_shoryuken_options['queue'] = queue
  worker_class.get_shoryuken_options['auto_delete'] = true
  worker_class.get_shoryuken_options['batch'] = true
  worker_class.get_shoryuken_options['body_parser'] = :json
  worker_class.received_messages = []
  Shoryuken.register_worker(queue, worker_class)
  worker_class
end

run_test_suite "Batch Processing Integration" do
  run_test "receives multiple messages in batch mode" do
    setup_localstack
    reset_shoryuken

    queue_name = "batch-test-#{SecureRandom.uuid}"
    create_test_queue(queue_name)
    Shoryuken.add_group('default', 1)
    Shoryuken.add_queue(queue_name, 1, 'default')

    begin
      worker = create_batch_worker(queue_name)
      worker.received_messages = []

      entries = 5.times.map { |i| { id: SecureRandom.uuid, message_body: "message-#{i}" } }
      Shoryuken::Client.queues(queue_name).send_messages(entries: entries)

      sleep 1 # Let messages settle

      poll_queues_until { worker.received_messages.size >= 5 }

      assert_equal(5, worker.received_messages.size)
      assert(worker.batch_sizes.any? { |size| size > 1 }, "Expected at least one batch with size > 1")
    ensure
      delete_test_queue(queue_name)
      teardown_localstack
    end
  end

  run_test "receives single message in non-batch mode" do
    setup_localstack
    reset_shoryuken

    queue_name = "batch-test-#{SecureRandom.uuid}"
    create_test_queue(queue_name)
    Shoryuken.add_group('default', 1)
    Shoryuken.add_queue(queue_name, 1, 'default')

    begin
      worker = create_single_worker(queue_name)
      worker.received_messages = []

      entries = 3.times.map { |i| { id: SecureRandom.uuid, message_body: "single-#{i}" } }
      Shoryuken::Client.queues(queue_name).send_messages(entries: entries)

      sleep 1

      poll_queues_until { worker.received_messages.size >= 3 }

      assert_equal(3, worker.received_messages.size)
      assert(worker.batch_sizes.all? { |size| size == 1 }, "Expected all batch sizes to be 1")
    ensure
      delete_test_queue(queue_name)
      teardown_localstack
    end
  end

  run_test "parses JSON bodies in batch mode" do
    setup_localstack
    reset_shoryuken

    queue_name = "batch-test-#{SecureRandom.uuid}"
    create_test_queue(queue_name)
    Shoryuken.add_group('default', 1)
    Shoryuken.add_queue(queue_name, 1, 'default')

    begin
      worker = create_json_batch_worker(queue_name)
      worker.received_messages = []

      entries = 3.times.map do |i|
        { id: SecureRandom.uuid, message_body: { index: i, data: "test-#{i}" }.to_json }
      end
      Shoryuken::Client.queues(queue_name).send_messages(entries: entries)

      sleep 1

      poll_queues_until { worker.received_messages.size >= 3 }

      assert_equal(3, worker.received_messages.size)
      worker.received_messages.each do |msg|
        assert(msg.is_a?(Hash), "Expected message to be a Hash, got #{msg.class}")
        assert(msg.key?('index'), "Expected message to have 'index' key")
      end
    ensure
      delete_test_queue(queue_name)
      teardown_localstack
    end
  end
end
