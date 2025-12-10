#!/usr/bin/env ruby
# frozen_string_literal: true

# This spec tests concurrent message processing including single vs multiple
# processor behavior, concurrent worker tracking accuracy, slow message handling,
# thread safety with atomic operations, queue draining efficiency, and error
# isolation between concurrent workers.

require 'shoryuken'
require 'concurrent'
require 'digest'

def create_tracking_worker(queue)
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

  worker_class.get_shoryuken_options['queue'] = queue
  worker_class.processing_times = []
  worker_class.concurrent_count = Concurrent::AtomicFixnum.new(0)
  worker_class.max_concurrent = Concurrent::AtomicFixnum.new(0)
  Shoryuken.register_worker(queue, worker_class)
  worker_class
end

def create_mixed_speed_worker(queue)
  worker_class = Class.new do
    include Shoryuken::Worker

    class << self
      attr_accessor :received_messages, :completion_times
    end

    shoryuken_options auto_delete: true, batch: false

    def perform(sqs_msg, body)
      self.class.received_messages ||= []
      self.class.received_messages << body

      # Slow messages take longer
      sleep(body.start_with?('slow') ? 2 : 0.1)

      self.class.completion_times ||= []
      self.class.completion_times << [body, Time.now]
    end
  end

  worker_class.get_shoryuken_options['queue'] = queue
  worker_class.received_messages = []
  worker_class.completion_times = []
  Shoryuken.register_worker(queue, worker_class)
  worker_class
end

def create_counter_worker(queue)
  worker_class = Class.new do
    include Shoryuken::Worker

    class << self
      attr_accessor :counter, :received_messages
    end

    shoryuken_options auto_delete: true, batch: false

    def perform(sqs_msg, body)
      self.class.counter.increment
      sleep 0.05 # Small delay to increase chance of race conditions

      self.class.received_messages ||= []
      self.class.received_messages << body
    end
  end

  worker_class.get_shoryuken_options['queue'] = queue
  worker_class.counter = Concurrent::AtomicFixnum.new(0)
  worker_class.received_messages = []
  Shoryuken.register_worker(queue, worker_class)
  worker_class
end

def create_integrity_worker(queue)
  worker_class = Class.new do
    include Shoryuken::Worker

    class << self
      attr_accessor :received_checksums, :expected_checksums
    end

    shoryuken_options auto_delete: true, batch: false

    def perform(sqs_msg, body)
      checksum = Digest::MD5.hexdigest(body)
      self.class.received_checksums ||= Concurrent::Array.new
      self.class.received_checksums << checksum
    end
  end

  worker_class.get_shoryuken_options['queue'] = queue
  worker_class.received_checksums = Concurrent::Array.new
  worker_class.expected_checksums = Concurrent::Array.new
  Shoryuken.register_worker(queue, worker_class)
  worker_class
end

def create_concurrent_simple_worker(queue)
  worker_class = Class.new do
    include Shoryuken::Worker

    class << self
      attr_accessor :received_messages
    end

    shoryuken_options auto_delete: true, batch: false

    def perform(sqs_msg, body)
      sleep 0.1 # Small processing time
      self.class.received_messages ||= []
      self.class.received_messages << body
    end
  end

  worker_class.get_shoryuken_options['queue'] = queue
  worker_class.received_messages = []
  Shoryuken.register_worker(queue, worker_class)
  worker_class
end

def create_error_isolation_worker(queue)
  worker_class = Class.new do
    include Shoryuken::Worker

    class << self
      attr_accessor :successful_messages, :failed_messages
    end

    shoryuken_options auto_delete: true, batch: false

    def perform(sqs_msg, body)
      if body.start_with?('bad')
        self.class.failed_messages ||= Concurrent::Array.new
        self.class.failed_messages << body
        raise "Simulated error for #{body}"
      else
        self.class.successful_messages ||= Concurrent::Array.new
        self.class.successful_messages << body
      end
    end
  end

  worker_class.get_shoryuken_options['queue'] = queue
  worker_class.successful_messages = Concurrent::Array.new
  worker_class.failed_messages = Concurrent::Array.new
  Shoryuken.register_worker(queue, worker_class)
  worker_class
end

run_test_suite "Concurrent Processing Integration" do
  run_test "processes messages sequentially with single processor" do
    setup_localstack
    reset_shoryuken

    queue_name = "concurrent-test-#{SecureRandom.uuid}"
    create_test_queue(queue_name)
    Shoryuken.add_group('default', 1)
    Shoryuken.add_queue(queue_name, 1, 'default')

    begin
      worker = create_tracking_worker(queue_name)
      worker.processing_times = []
      worker.concurrent_count = Concurrent::AtomicFixnum.new(0)
      worker.max_concurrent = Concurrent::AtomicFixnum.new(0)

      # Send multiple messages
      5.times { |i| Shoryuken::Client.queues(queue_name).send_message(message_body: "msg-#{i}") }

      poll_queues_until { worker.processing_times.size >= 5 }

      assert_equal(5, worker.processing_times.size)
      # With single processor, max concurrent should be 1
      assert_equal(1, worker.max_concurrent.value)
    ensure
      delete_test_queue(queue_name)
      teardown_localstack
    end
  end

  run_test "processes messages concurrently with multiple processors" do
    setup_localstack
    reset_shoryuken

    queue_name = "concurrent-test-#{SecureRandom.uuid}"
    create_test_queue(queue_name)
    Shoryuken.add_group('concurrent', 5) # 5 concurrent processors
    Shoryuken.add_queue(queue_name, 1, 'concurrent')

    begin
      worker = create_tracking_worker(queue_name)
      worker.processing_times = []
      worker.concurrent_count = Concurrent::AtomicFixnum.new(0)
      worker.max_concurrent = Concurrent::AtomicFixnum.new(0)

      # Send multiple messages
      10.times { |i| Shoryuken::Client.queues(queue_name).send_message(message_body: "msg-#{i}") }

      poll_queues_until(timeout: 20) { worker.processing_times.size >= 10 }

      assert_equal(10, worker.processing_times.size)
      # With multiple processors, we should see concurrency > 1
      assert(worker.max_concurrent.value > 1, "Expected concurrency > 1")
    ensure
      delete_test_queue(queue_name)
      teardown_localstack
    end
  end

  run_test "tracks concurrent processing accurately" do
    setup_localstack
    reset_shoryuken

    queue_name = "concurrent-test-#{SecureRandom.uuid}"
    create_test_queue(queue_name)
    Shoryuken.add_group('concurrent', 5)
    Shoryuken.add_queue(queue_name, 1, 'concurrent')

    begin
      worker = create_tracking_worker(queue_name)
      worker.processing_times = []
      worker.concurrent_count = Concurrent::AtomicFixnum.new(0)
      worker.max_concurrent = Concurrent::AtomicFixnum.new(0)

      # Send enough messages to saturate processors
      15.times { |i| Shoryuken::Client.queues(queue_name).send_message(message_body: "saturate-#{i}") }

      poll_queues_until(timeout: 30) { worker.processing_times.size >= 15 }

      assert_equal(15, worker.processing_times.size)
      # Max concurrent should not exceed configured processors
      assert(worker.max_concurrent.value <= 5, "Expected max concurrent <= 5")
    ensure
      delete_test_queue(queue_name)
      teardown_localstack
    end
  end

  run_test "continues processing while slow messages are being handled" do
    setup_localstack
    reset_shoryuken

    queue_name = "concurrent-test-#{SecureRandom.uuid}"
    create_test_queue(queue_name)
    Shoryuken.add_group('slow', 3)
    Shoryuken.add_queue(queue_name, 1, 'slow')

    begin
      worker = create_mixed_speed_worker(queue_name)
      worker.received_messages = []
      worker.completion_times = []

      # Send mix of slow and fast messages
      Shoryuken::Client.queues(queue_name).send_message(message_body: 'slow-1')
      Shoryuken::Client.queues(queue_name).send_message(message_body: 'fast-1')
      Shoryuken::Client.queues(queue_name).send_message(message_body: 'fast-2')
      Shoryuken::Client.queues(queue_name).send_message(message_body: 'slow-2')
      Shoryuken::Client.queues(queue_name).send_message(message_body: 'fast-3')

      poll_queues_until(timeout: 20) { worker.received_messages.size >= 5 }

      assert_equal(5, worker.received_messages.size)

      # Fast messages should complete before slow ones (in some cases)
      fast_times = worker.completion_times.select { |m, _| m.start_with?('fast') }.map(&:last)
      slow_times = worker.completion_times.select { |m, _| m.start_with?('slow') }.map(&:last)

      # At least some fast messages should complete before all slow messages
      assert(fast_times.min < slow_times.max, "Expected some fast messages to complete before slow ones")
    ensure
      delete_test_queue(queue_name)
      teardown_localstack
    end
  end

  run_test "handles shared state safely with atomic operations" do
    setup_localstack
    reset_shoryuken

    queue_name = "concurrent-test-#{SecureRandom.uuid}"
    create_test_queue(queue_name)
    Shoryuken.add_group('threaded', 5)
    Shoryuken.add_queue(queue_name, 1, 'threaded')

    begin
      worker = create_counter_worker(queue_name)
      worker.counter = Concurrent::AtomicFixnum.new(0)
      worker.received_messages = []

      # Send many messages to trigger concurrent access
      20.times { |i| Shoryuken::Client.queues(queue_name).send_message(message_body: "count-#{i}") }

      poll_queues_until(timeout: 30) { worker.received_messages.size >= 20 }

      assert_equal(20, worker.received_messages.size)
      # Counter should exactly match message count due to atomic operations
      assert_equal(20, worker.counter.value)
    ensure
      delete_test_queue(queue_name)
      teardown_localstack
    end
  end

  run_test "maintains message integrity under concurrent processing" do
    setup_localstack
    reset_shoryuken

    queue_name = "concurrent-test-#{SecureRandom.uuid}"
    create_test_queue(queue_name)
    Shoryuken.add_group('threaded', 5)
    Shoryuken.add_queue(queue_name, 1, 'threaded')

    begin
      worker = create_integrity_worker(queue_name)
      worker.received_checksums = Concurrent::Array.new
      worker.expected_checksums = Concurrent::Array.new

      # Send messages with checksums
      20.times do |i|
        body = "integrity-test-#{i}-#{SecureRandom.hex(16)}"
        checksum = Digest::MD5.hexdigest(body)
        worker.expected_checksums << checksum
        Shoryuken::Client.queues(queue_name).send_message(message_body: body)
      end

      poll_queues_until(timeout: 30) { worker.received_checksums.size >= 20 }

      assert_equal(20, worker.received_checksums.size)
      # All checksums should match (no data corruption)
      assert_equal(worker.expected_checksums.sort, worker.received_checksums.sort)
    ensure
      delete_test_queue(queue_name)
      teardown_localstack
    end
  end

  run_test "drains queue efficiently with multiple processors" do
    setup_localstack
    reset_shoryuken

    queue_name = "concurrent-test-#{SecureRandom.uuid}"
    create_test_queue(queue_name)
    Shoryuken.add_group('drain', 3)
    Shoryuken.add_queue(queue_name, 1, 'drain')

    begin
      worker = create_concurrent_simple_worker(queue_name)
      worker.received_messages = []

      # Send burst of messages
      start_time = Time.now
      50.times { |i| Shoryuken::Client.queues(queue_name).send_message(message_body: "drain-#{i}") }

      poll_queues_until(timeout: 60) { worker.received_messages.size >= 50 }
      end_time = Time.now

      assert_equal(50, worker.received_messages.size)

      # Processing should be faster than sequential (50 * 0.1s = 5s minimum sequential)
      # With 3 processors, should be around 2-3s
      processing_time = end_time - start_time
      assert(processing_time < 10, "Expected processing time < 10s, got #{processing_time}s")
    ensure
      delete_test_queue(queue_name)
      teardown_localstack
    end
  end

  run_test "isolates errors between concurrent workers" do
    setup_localstack
    reset_shoryuken

    queue_name = "concurrent-test-#{SecureRandom.uuid}"
    create_test_queue(queue_name)
    Shoryuken.add_group('errors', 3)
    Shoryuken.add_queue(queue_name, 1, 'errors')

    begin
      worker = create_error_isolation_worker(queue_name)
      worker.successful_messages = Concurrent::Array.new
      worker.failed_messages = Concurrent::Array.new

      # Send mix of good and bad messages
      5.times do |i|
        Shoryuken::Client.queues(queue_name).send_message(message_body: "good-#{i}")
        Shoryuken::Client.queues(queue_name).send_message(message_body: "bad-#{i}")
      end

      poll_queues_until(timeout: 20) { worker.successful_messages.size >= 5 }

      # Good messages should succeed despite bad message failures
      assert_equal(5, worker.successful_messages.size)
      assert(worker.failed_messages.size >= 1, "Expected at least 1 failed message")
    ensure
      delete_test_queue(queue_name)
      teardown_localstack
    end
  end
end
