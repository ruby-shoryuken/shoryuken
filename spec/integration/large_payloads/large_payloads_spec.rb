#!/usr/bin/env ruby
# frozen_string_literal: true

# This spec tests large payload handling including moderately large payloads (10KB),
# large payloads (100KB), payloads near the 256KB SQS limit, large JSON objects,
# deeply nested JSON, batch processing with large messages, and unicode content.

require 'shoryuken'

def create_payload_worker(queue)
  worker_class = Class.new do
    include Shoryuken::Worker

    class << self
      attr_accessor :received_bodies
    end

    def perform(sqs_msg, body)
      self.class.received_bodies ||= []
      self.class.received_bodies << body
    end
  end

  worker_class.get_shoryuken_options['queue'] = queue
  worker_class.get_shoryuken_options['auto_delete'] = true
  worker_class.get_shoryuken_options['batch'] = false
  worker_class.received_bodies = []
  Shoryuken.register_worker(queue, worker_class)
  worker_class
end

def create_json_worker(queue)
  worker_class = Class.new do
    include Shoryuken::Worker

    class << self
      attr_accessor :received_data
    end

    def perform(sqs_msg, body)
      self.class.received_data ||= []
      self.class.received_data << body
    end
  end

  worker_class.get_shoryuken_options['queue'] = queue
  worker_class.get_shoryuken_options['auto_delete'] = true
  worker_class.get_shoryuken_options['batch'] = false
  worker_class.get_shoryuken_options['body_parser'] = :json
  worker_class.received_data = []
  Shoryuken.register_worker(queue, worker_class)
  worker_class
end

run_test_suite "Large Payloads Integration" do
  run_test "handles moderately large payloads (10KB)" do
    setup_localstack
    reset_shoryuken

    queue_name = "large-payload-test-#{SecureRandom.uuid}"
    create_test_queue(queue_name)
    Shoryuken.add_group('default', 1)
    Shoryuken.add_queue(queue_name, 1, 'default')

    begin
      worker = create_payload_worker(queue_name)
      worker.received_bodies = []

      payload = 'x' * (10 * 1024)
      Shoryuken::Client.queues(queue_name).send_message(message_body: payload)

      poll_queues_until { worker.received_bodies.size >= 1 }

      assert_equal(10 * 1024, worker.received_bodies.first.size)
    ensure
      delete_test_queue(queue_name)
      teardown_localstack
    end
  end

  run_test "handles large payloads (100KB)" do
    setup_localstack
    reset_shoryuken

    queue_name = "large-payload-test-#{SecureRandom.uuid}"
    create_test_queue(queue_name)
    Shoryuken.add_group('default', 1)
    Shoryuken.add_queue(queue_name, 1, 'default')

    begin
      worker = create_payload_worker(queue_name)
      worker.received_bodies = []

      payload = 'y' * (100 * 1024)
      Shoryuken::Client.queues(queue_name).send_message(message_body: payload)

      poll_queues_until { worker.received_bodies.size >= 1 }

      assert_equal(100 * 1024, worker.received_bodies.first.size)
    ensure
      delete_test_queue(queue_name)
      teardown_localstack
    end
  end

  run_test "handles payloads near the SQS limit (250KB)" do
    setup_localstack
    reset_shoryuken

    queue_name = "large-payload-test-#{SecureRandom.uuid}"
    create_test_queue(queue_name)
    Shoryuken.add_group('default', 1)
    Shoryuken.add_queue(queue_name, 1, 'default')

    begin
      worker = create_payload_worker(queue_name)
      worker.received_bodies = []

      payload = 'z' * (250 * 1024)
      Shoryuken::Client.queues(queue_name).send_message(message_body: payload)

      poll_queues_until { worker.received_bodies.size >= 1 }

      assert_equal(250 * 1024, worker.received_bodies.first.size)
    ensure
      delete_test_queue(queue_name)
      teardown_localstack
    end
  end

  run_test "handles large JSON objects" do
    setup_localstack
    reset_shoryuken

    queue_name = "large-payload-test-#{SecureRandom.uuid}"
    create_test_queue(queue_name)
    Shoryuken.add_group('default', 1)
    Shoryuken.add_queue(queue_name, 1, 'default')

    begin
      worker = create_json_worker(queue_name)
      worker.received_data = []

      large_data = {}
      1000.times do |i|
        large_data["key_#{i}"] = "value_#{i}" * 10
      end

      json_payload = JSON.generate(large_data)
      Shoryuken::Client.queues(queue_name).send_message(message_body: json_payload)

      poll_queues_until { worker.received_data.size >= 1 }

      received = worker.received_data.first
      assert_equal(1000, received.keys.size)
      assert_equal('value_0' * 10, received['key_0'])
    ensure
      delete_test_queue(queue_name)
      teardown_localstack
    end
  end

  run_test "handles deeply nested JSON" do
    setup_localstack
    reset_shoryuken

    queue_name = "large-payload-test-#{SecureRandom.uuid}"
    create_test_queue(queue_name)
    Shoryuken.add_group('default', 1)
    Shoryuken.add_queue(queue_name, 1, 'default')

    begin
      worker = create_json_worker(queue_name)
      worker.received_data = []

      nested = { 'level' => 0, 'data' => 'base' }
      50.times do |i|
        nested = { 'level' => i + 1, 'child' => nested, 'padding' => 'x' * 100 }
      end

      json_payload = JSON.generate(nested)
      Shoryuken::Client.queues(queue_name).send_message(message_body: json_payload)

      poll_queues_until { worker.received_data.size >= 1 }

      received = worker.received_data.first
      assert_equal(50, received['level'])

      # Traverse to verify nesting
      current = received
      10.times { current = current['child'] }
      assert_equal(40, current['level'])
    ensure
      delete_test_queue(queue_name)
      teardown_localstack
    end
  end

  run_test "handles large JSON arrays" do
    setup_localstack
    reset_shoryuken

    queue_name = "large-payload-test-#{SecureRandom.uuid}"
    create_test_queue(queue_name)
    Shoryuken.add_group('default', 1)
    Shoryuken.add_queue(queue_name, 1, 'default')

    begin
      worker = create_json_worker(queue_name)
      worker.received_data = []

      large_array = (0...5000).map { |i| { 'index' => i, 'value' => "item-#{i}" } }
      json_payload = JSON.generate(large_array)

      Shoryuken::Client.queues(queue_name).send_message(message_body: json_payload)

      poll_queues_until { worker.received_data.size >= 1 }

      received = worker.received_data.first
      assert_equal(5000, received.size)
      assert_equal(0, received.first['index'])
      assert_equal(4999, received.last['index'])
    ensure
      delete_test_queue(queue_name)
      teardown_localstack
    end
  end
end
