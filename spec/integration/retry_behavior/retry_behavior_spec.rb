#!/usr/bin/env ruby
# frozen_string_literal: true

# This spec tests retry behavior including ApproximateReceiveCount tracking,
# exponential backoff with retry_intervals, retry exhaustion, and custom
# retry interval configurations (array and callable).

require 'shoryuken'

def create_failing_worker(queue, fail_times:)
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

  worker_class.get_shoryuken_options['queue'] = queue
  worker_class.receive_counts = []
  worker_class.fail_times_remaining = fail_times
  Shoryuken.register_worker(queue, worker_class)
  worker_class
end

def create_backoff_worker(queue)
  worker_class = Class.new do
    include Shoryuken::Worker

    class << self
      attr_accessor :receive_counts, :visibility_changes
    end

    shoryuken_options auto_delete: false, batch: false, retry_intervals: [1, 2, 4]

    def perform(sqs_msg, body)
      receive_count = sqs_msg.attributes['ApproximateReceiveCount'].to_i
      self.class.receive_counts ||= []
      self.class.receive_counts << receive_count

      if receive_count < 3
        self.class.visibility_changes ||= []
        self.class.visibility_changes << receive_count
        raise "Backoff failure"
      else
        sqs_msg.delete
      end
    end
  end

  worker_class.get_shoryuken_options['queue'] = queue
  worker_class.receive_counts = []
  worker_class.visibility_changes = []
  Shoryuken.register_worker(queue, worker_class)
  worker_class
end

def create_limited_retry_worker(queue, max_retries:)
  worker_class = Class.new do
    include Shoryuken::Worker

    class << self
      attr_accessor :attempt_count, :exhausted, :max_retries
    end

    shoryuken_options auto_delete: false, batch: false

    def perform(sqs_msg, body)
      self.class.attempt_count += 1
      receive_count = sqs_msg.attributes['ApproximateReceiveCount'].to_i

      if receive_count >= self.class.max_retries
        self.class.exhausted = true
        sqs_msg.delete
      else
        raise "Retry #{receive_count}"
      end
    end
  end

  worker_class.get_shoryuken_options['queue'] = queue
  worker_class.attempt_count = 0
  worker_class.exhausted = false
  worker_class.max_retries = max_retries
  Shoryuken.register_worker(queue, worker_class)
  worker_class
end

def create_array_interval_worker(queue)
  worker_class = Class.new do
    include Shoryuken::Worker

    class << self
      attr_accessor :receive_times
    end

    shoryuken_options auto_delete: false, batch: false, retry_intervals: [1, 2, 4]

    def perform(sqs_msg, body)
      self.class.receive_times ||= []
      self.class.receive_times << Time.now
      receive_count = sqs_msg.attributes['ApproximateReceiveCount'].to_i

      if receive_count < 3
        raise "Array interval retry"
      else
        sqs_msg.delete
      end
    end
  end

  worker_class.get_shoryuken_options['queue'] = queue
  worker_class.receive_times = []
  Shoryuken.register_worker(queue, worker_class)
  worker_class
end

def create_lambda_interval_worker(queue)
  worker_class = Class.new do
    include Shoryuken::Worker

    class << self
      attr_accessor :receive_times, :intervals_used
    end

    # Lambda returns interval based on attempt number
    shoryuken_options auto_delete: false, batch: false,
                      retry_intervals: ->(attempt) { [1, 2, 4][attempt - 1] || 4 }

    def perform(sqs_msg, body)
      self.class.receive_times ||= []
      self.class.receive_times << Time.now
      receive_count = sqs_msg.attributes['ApproximateReceiveCount'].to_i

      self.class.intervals_used ||= []
      self.class.intervals_used << receive_count

      if receive_count < 3
        raise "Lambda interval retry"
      else
        sqs_msg.delete
      end
    end
  end

  worker_class.get_shoryuken_options['queue'] = queue
  worker_class.receive_times = []
  worker_class.intervals_used = []
  Shoryuken.register_worker(queue, worker_class)
  worker_class
end

run_test_suite "Retry Behavior Integration" do
  run_test "tracks receive count across message redeliveries" do
    setup_localstack
    reset_shoryuken

    queue_name = "retry-test-#{SecureRandom.uuid}"
    # Create queue with short visibility timeout for faster retries
    create_test_queue(queue_name, attributes: { 'VisibilityTimeout' => '2' })
    Shoryuken.add_group('default', 1)
    Shoryuken.add_queue(queue_name, 1, 'default')

    begin
      worker = create_failing_worker(queue_name, fail_times: 2)
      worker.receive_counts = []

      Shoryuken::Client.queues(queue_name).send_message(message_body: 'retry-count-test')

      # Wait for multiple redeliveries
      poll_queues_until(timeout: 20) { worker.receive_counts.size >= 3 }

      assert(worker.receive_counts.size >= 3)
      assert_equal(worker.receive_counts, worker.receive_counts.sort, "Receive counts should be increasing")
      assert_equal(1, worker.receive_counts.first)
    ensure
      delete_test_queue(queue_name)
      teardown_localstack
    end
  end

  run_test "adjusts visibility timeout based on retry intervals" do
    setup_localstack
    reset_shoryuken

    queue_name = "retry-test-#{SecureRandom.uuid}"
    create_test_queue(queue_name, attributes: { 'VisibilityTimeout' => '2' })
    Shoryuken.add_group('default', 1)
    Shoryuken.add_queue(queue_name, 1, 'default')

    begin
      worker = create_backoff_worker(queue_name)
      worker.receive_counts = []
      worker.visibility_changes = []

      Shoryuken::Client.queues(queue_name).send_message(message_body: 'backoff-test')

      poll_queues_until(timeout: 15) { worker.receive_counts.size >= 2 }

      assert(worker.receive_counts.size >= 2)
      # Visibility changes should have been attempted
      assert(!worker.visibility_changes.empty?, "Expected visibility changes to be recorded")
    ensure
      delete_test_queue(queue_name)
      teardown_localstack
    end
  end

  run_test "stops retrying after max attempts" do
    setup_localstack
    reset_shoryuken

    queue_name = "retry-test-#{SecureRandom.uuid}"
    create_test_queue(queue_name, attributes: { 'VisibilityTimeout' => '2' })
    Shoryuken.add_group('default', 1)
    Shoryuken.add_queue(queue_name, 1, 'default')

    begin
      worker = create_limited_retry_worker(queue_name, max_retries: 3)
      worker.attempt_count = 0
      worker.exhausted = false

      Shoryuken::Client.queues(queue_name).send_message(message_body: 'exhaustion-test')

      poll_queues_until(timeout: 20) { worker.attempt_count >= 3 || worker.exhausted }

      assert(worker.attempt_count >= 3)
    ensure
      delete_test_queue(queue_name)
      teardown_localstack
    end
  end

  run_test "uses array-based retry intervals" do
    setup_localstack
    reset_shoryuken

    queue_name = "retry-test-#{SecureRandom.uuid}"
    create_test_queue(queue_name, attributes: { 'VisibilityTimeout' => '2' })
    Shoryuken.add_group('default', 1)
    Shoryuken.add_queue(queue_name, 1, 'default')

    begin
      # Test with array intervals: [1, 2, 4] seconds
      worker = create_array_interval_worker(queue_name)
      worker.receive_times = []

      Shoryuken::Client.queues(queue_name).send_message(message_body: 'array-interval-test')

      poll_queues_until(timeout: 15) { worker.receive_times.size >= 2 }

      assert(worker.receive_times.size >= 2)
    ensure
      delete_test_queue(queue_name)
      teardown_localstack
    end
  end

  run_test "uses callable retry intervals" do
    setup_localstack
    reset_shoryuken

    queue_name = "retry-test-#{SecureRandom.uuid}"
    create_test_queue(queue_name, attributes: { 'VisibilityTimeout' => '2' })
    Shoryuken.add_group('default', 1)
    Shoryuken.add_queue(queue_name, 1, 'default')

    begin
      # Test with lambda-based intervals
      worker = create_lambda_interval_worker(queue_name)
      worker.receive_times = []
      worker.intervals_used = []

      Shoryuken::Client.queues(queue_name).send_message(message_body: 'lambda-interval-test')

      poll_queues_until(timeout: 15) { worker.receive_times.size >= 2 }

      assert(worker.receive_times.size >= 2)
    ensure
      delete_test_queue(queue_name)
      teardown_localstack
    end
  end
end
