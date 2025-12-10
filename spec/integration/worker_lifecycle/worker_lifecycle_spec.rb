#!/usr/bin/env ruby
# frozen_string_literal: true

# This spec tests worker lifecycle including graceful shutdown with in-flight
# messages, worker registration and discovery, worker inheritance behavior,
# dynamic queue names (callable), and concurrent workers on the same queue.

require 'shoryuken'

def create_lifecycle_slow_worker(queue, processing_time:)
  worker_class = Class.new do
    include Shoryuken::Worker

    class << self
      attr_accessor :received_messages, :completed_messages, :start_times, :processing_time
    end

    def perform(sqs_msg, body)
      self.class.start_times ||= []
      self.class.start_times << Time.now

      self.class.received_messages ||= []
      self.class.received_messages << body

      sleep self.class.processing_time

      self.class.completed_messages ||= []
      self.class.completed_messages << body
    end
  end

  # Set options before registering to avoid default queue conflicts
  worker_class.get_shoryuken_options['queue'] = queue
  worker_class.get_shoryuken_options['auto_delete'] = true
  worker_class.get_shoryuken_options['batch'] = false
  worker_class.processing_time = processing_time
  worker_class.received_messages = []
  worker_class.completed_messages = []
  worker_class.start_times = []
  Shoryuken.register_worker(queue, worker_class)
  worker_class
end

def create_lifecycle_simple_worker(queue)
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

  # Set options before registering to avoid default queue conflicts
  worker_class.get_shoryuken_options['queue'] = queue
  worker_class.get_shoryuken_options['auto_delete'] = true
  worker_class.get_shoryuken_options['batch'] = false
  worker_class.received_messages = []
  Shoryuken.register_worker(queue, worker_class)
  worker_class
end

run_test_suite "Worker Lifecycle Integration" do
  run_test "completes in-flight messages before shutdown" do
    setup_localstack
    reset_shoryuken

    queue_name = "lifecycle-test-#{SecureRandom.uuid}"
    create_test_queue(queue_name)
    Shoryuken.add_group('default', 1)
    Shoryuken.add_queue(queue_name, 1, 'default')

    begin
      worker = create_lifecycle_slow_worker(queue_name, processing_time: 2)
      worker.received_messages = []
      worker.completed_messages = []

      Shoryuken::Client.queues(queue_name).send_message(message_body: 'shutdown-test')

      launcher = Shoryuken::Launcher.new
      launcher.start

      # Wait for message to start processing
      sleep 1

      # Initiate shutdown while message is still processing
      stop_thread = Thread.new { launcher.stop }

      # Wait for graceful shutdown
      stop_thread.join(10)

      assert_equal(1, worker.completed_messages.size)
    ensure
      delete_test_queue(queue_name)
      teardown_localstack
    end
  end

  run_test "stops accepting new messages after shutdown signal" do
    setup_localstack
    reset_shoryuken

    queue_name = "lifecycle-test-#{SecureRandom.uuid}"
    create_test_queue(queue_name)
    Shoryuken.add_group('default', 1)
    Shoryuken.add_queue(queue_name, 1, 'default')

    begin
      worker = create_lifecycle_simple_worker(queue_name)
      worker.received_messages = []

      launcher = Shoryuken::Launcher.new
      launcher.start

      # Immediately stop
      launcher.stop

      # Send message after stop
      Shoryuken::Client.queues(queue_name).send_message(message_body: 'after-shutdown')

      sleep 2

      # Message should not be processed
      assert_equal(0, worker.received_messages.size)
    ensure
      delete_test_queue(queue_name)
      teardown_localstack
    end
  end

  run_test "registers worker for queue" do
    setup_localstack
    reset_shoryuken

    queue_name = "lifecycle-test-#{SecureRandom.uuid}"
    create_test_queue(queue_name)
    Shoryuken.add_group('default', 1)
    Shoryuken.add_queue(queue_name, 1, 'default')

    begin
      worker_class = create_lifecycle_simple_worker(queue_name)

      registered = Shoryuken.worker_registry.workers(queue_name)
      assert_includes(registered, worker_class)
    ensure
      delete_test_queue(queue_name)
      teardown_localstack
    end
  end

  run_test "replaces existing worker when registering same queue (non-batch)" do
    setup_localstack
    reset_shoryuken

    begin
      worker1 = Class.new do
        include Shoryuken::Worker

        def perform(sqs_msg, body); end
      end

      worker2 = Class.new do
        include Shoryuken::Worker

        def perform(sqs_msg, body); end
      end

      # Set options manually without triggering auto-registration
      worker1.get_shoryuken_options['queue'] = 'multi-worker-queue'
      worker1.get_shoryuken_options['auto_delete'] = true
      worker1.get_shoryuken_options['batch'] = false

      worker2.get_shoryuken_options['queue'] = 'multi-worker-queue'
      worker2.get_shoryuken_options['auto_delete'] = true
      worker2.get_shoryuken_options['batch'] = false

      Shoryuken.register_worker('multi-worker-queue', worker1)
      Shoryuken.register_worker('multi-worker-queue', worker2)

      # Second registration replaces the first one
      registered = Shoryuken.worker_registry.workers('multi-worker-queue')
      assert_equal(1, registered.size)
      assert_equal(worker2, registered.first)
    ensure
      teardown_localstack
    end
  end

  run_test "inherits options from parent worker" do
    setup_localstack
    reset_shoryuken

    begin
      parent_worker = Class.new do
        include Shoryuken::Worker
        shoryuken_options auto_delete: true, batch: false
      end

      child_worker = Class.new(parent_worker) do
        shoryuken_options queue: 'child-queue'
      end

      options = child_worker.get_shoryuken_options
      assert(options['auto_delete'])
      assert(!options['batch'])
      assert_equal('child-queue', options['queue'])
    ensure
      teardown_localstack
    end
  end

  run_test "allows child to override parent options" do
    setup_localstack
    reset_shoryuken

    begin
      parent_worker = Class.new do
        include Shoryuken::Worker
        shoryuken_options auto_delete: true, batch: false
      end

      child_worker = Class.new(parent_worker) do
        shoryuken_options auto_delete: false, queue: 'override-queue'
      end

      options = child_worker.get_shoryuken_options
      assert(!options['auto_delete'])
      assert_equal('override-queue', options['queue'])
    ensure
      teardown_localstack
    end
  end

  run_test "supports callable queue names" do
    setup_localstack
    reset_shoryuken

    queue_name = "lifecycle-test-#{SecureRandom.uuid}"
    dynamic_queue = "dynamic-#{SecureRandom.uuid}"

    create_test_queue(queue_name)
    create_test_queue(dynamic_queue)
    Shoryuken.add_group('default', 1)
    Shoryuken.add_queue(queue_name, 1, 'default')

    begin
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

      # Set queue as callable
      worker_class.get_shoryuken_options['queue'] = -> { dynamic_queue }
      worker_class.received_messages = []

      Shoryuken.add_queue(dynamic_queue, 1, 'default')
      Shoryuken.register_worker(dynamic_queue, worker_class)

      Shoryuken::Client.queues(dynamic_queue).send_message(message_body: 'dynamic-msg')

      poll_queues_until { worker_class.received_messages.size >= 1 }

      assert_equal(1, worker_class.received_messages.size)
    ensure
      delete_test_queue(queue_name)
      delete_test_queue(dynamic_queue)
      teardown_localstack
    end
  end

  run_test "processes messages concurrently with multiple workers" do
    setup_localstack
    reset_shoryuken

    queue_name = "lifecycle-test-#{SecureRandom.uuid}"
    create_test_queue(queue_name)
    Shoryuken.add_group('concurrent', 3) # 3 concurrent workers
    Shoryuken.add_queue(queue_name, 1, 'concurrent')

    begin
      worker = create_lifecycle_slow_worker(queue_name, processing_time: 1)
      worker.received_messages = []
      worker.start_times = []

      # Send multiple messages
      5.times do |i|
        Shoryuken::Client.queues(queue_name).send_message(message_body: "concurrent-#{i}")
      end

      sleep 1

      poll_queues_until(timeout: 20) { worker.received_messages.size >= 5 }

      assert_equal(5, worker.received_messages.size)

      # Check for concurrent processing by looking at overlapping start times
      # With concurrency, some messages should start processing close together
      time_diffs = worker.start_times.sort.each_cons(2).map { |a, b| b - a }
      assert(time_diffs.any? { |diff| diff < 0.5 }, "Expected concurrent processing")
    ensure
      delete_test_queue(queue_name)
      teardown_localstack
    end
  end
end
