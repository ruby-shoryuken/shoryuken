#!/usr/bin/env ruby
# frozen_string_literal: true

begin
  require 'active_job'
  require 'shoryuken'
  require 'digest'
  require 'json'
rescue LoadError => e
  puts "Failed to load dependencies: #{e.message}"
  exit 1
end

ActiveJob::Base.queue_adapter = :shoryuken

class FifoTestJob < ActiveJob::Base
  queue_as :test_fifo

  def perform(order_id, action)
    "Processed order #{order_id}: #{action}"
  end
end

class AttributesTestJob < ActiveJob::Base
  queue_as :attributes_test

  def perform(data)
    "Processed: #{data}"
  end
end

run_test_suite "FIFO Queue Support" do
  run_test "generates message deduplication ID for FIFO queues" do
    # Mock FIFO queue
    fifo_queue_mock = Object.new
    fifo_queue_mock.define_singleton_method(:fifo?) { true }
    fifo_queue_mock.define_singleton_method(:name) { 'test_fifo.fifo' }

    captured_params = nil
    fifo_queue_mock.define_singleton_method(:send_message) do |params|
      captured_params = params
    end

    # Mock Shoryuken::Client.queues to return FIFO queue
    Shoryuken::Client.define_singleton_method(:queues) do |queue_name = nil|
      if queue_name
        fifo_queue_mock
      else
        { test_fifo: fifo_queue_mock }
      end
    end

    # Mock register_worker
    Shoryuken.define_singleton_method(:register_worker) { |*args| nil }

    FifoTestJob.perform_later('order-123', 'process')

    assert(captured_params.has_key?(:message_deduplication_id))
    assert_equal(64, captured_params[:message_deduplication_id].length)

    # Verify deduplication ID excludes job_id and enqueued_at
    body = captured_params[:message_body]
    body_without_variable_fields = body.except('job_id', 'enqueued_at')
    expected_dedupe_id = Digest::SHA256.hexdigest(JSON.dump(body_without_variable_fields))
    assert_equal(expected_dedupe_id, captured_params[:message_deduplication_id])
  end

  run_test "supports custom message deduplication ID" do
    fifo_queue_mock = Object.new
    fifo_queue_mock.define_singleton_method(:fifo?) { true }
    fifo_queue_mock.define_singleton_method(:name) { 'test_fifo.fifo' }

    captured_params = nil
    fifo_queue_mock.define_singleton_method(:send_message) do |params|
      captured_params = params
    end

    Shoryuken::Client.define_singleton_method(:queues) do |queue_name = nil|
      fifo_queue_mock
    end

    custom_dedupe_id = 'custom-dedupe-123'

    job = FifoTestJob.new('order-456', 'cancel')
    job.sqs_send_message_parameters = { message_deduplication_id: custom_dedupe_id }
    ActiveJob::QueueAdapters::ShoryukenAdapter.enqueue(job)

    assert_equal(custom_dedupe_id, captured_params[:message_deduplication_id])
  end

  run_test "supports message group ID for FIFO queues" do
    fifo_queue_mock = Object.new
    fifo_queue_mock.define_singleton_method(:fifo?) { true }
    fifo_queue_mock.define_singleton_method(:name) { 'test_fifo.fifo' }

    captured_params = nil
    fifo_queue_mock.define_singleton_method(:send_message) do |params|
      captured_params = params
    end

    Shoryuken::Client.define_singleton_method(:queues) do |queue_name = nil|
      fifo_queue_mock
    end

    group_id = 'order-group-1'

    job = FifoTestJob.new('order-789', 'update')
    job.sqs_send_message_parameters = { message_group_id: group_id }
    ActiveJob::QueueAdapters::ShoryukenAdapter.enqueue(job)

    assert_equal(group_id, captured_params[:message_group_id])
  end
end

run_test_suite "Message Attributes" do
  run_test "supports custom message attributes" do
    regular_queue_mock = Object.new
    regular_queue_mock.define_singleton_method(:fifo?) { false }
    regular_queue_mock.define_singleton_method(:name) { 'attributes_test' }

    captured_params = nil
    regular_queue_mock.define_singleton_method(:send_message) do |params|
      captured_params = params
    end

    Shoryuken::Client.define_singleton_method(:queues) do |queue_name = nil|
      regular_queue_mock
    end

    Shoryuken.define_singleton_method(:register_worker) { |*args| nil }

    custom_attributes = {
      'trace_id' => { string_value: 'trace-123', data_type: 'String' },
      'priority' => { string_value: 'high', data_type: 'String' }
    }

    job = AttributesTestJob.new('test data')
    job.sqs_send_message_parameters = { message_attributes: custom_attributes }
    ActiveJob::QueueAdapters::ShoryukenAdapter.enqueue(job)

    attributes = captured_params[:message_attributes]
    assert_equal(custom_attributes['trace_id'], attributes['trace_id'])
    assert_equal(custom_attributes['priority'], attributes['priority'])

    # Should still include required Shoryuken attribute
    expected_shoryuken_class = {
      string_value: "Shoryuken::ActiveJob::JobWrapper",
      data_type: 'String'
    }
    assert_equal(expected_shoryuken_class, attributes['shoryuken_class'])
  end

  run_test "supports message system attributes" do
    regular_queue_mock = Object.new
    regular_queue_mock.define_singleton_method(:fifo?) { false }
    regular_queue_mock.define_singleton_method(:name) { 'attributes_test' }

    captured_params = nil
    regular_queue_mock.define_singleton_method(:send_message) do |params|
      captured_params = params
    end

    Shoryuken::Client.define_singleton_method(:queues) do |queue_name = nil|
      regular_queue_mock
    end

    system_attributes = {
      'AWSTraceHeader' => {
        string_value: 'Root=1-5e1b4151-5ac6c58d1842c9b7b43f7e55',
        data_type: 'String'
      }
    }

    job = AttributesTestJob.new('tracing test')
    job.sqs_send_message_parameters = { message_system_attributes: system_attributes }
    ActiveJob::QueueAdapters::ShoryukenAdapter.enqueue(job)

    assert_equal(system_attributes, captured_params[:message_system_attributes])
  end
end

run_test_suite "Parameter Handling" do
  run_test "properly handles job parameter mutation" do
    regular_queue_mock = Object.new
    regular_queue_mock.define_singleton_method(:fifo?) { false }
    regular_queue_mock.define_singleton_method(:name) { 'attributes_test' }

    captured_params = nil
    regular_queue_mock.define_singleton_method(:send_message) do |params|
      captured_params = params
    end

    Shoryuken::Client.define_singleton_method(:queues) do |queue_name = nil|
      regular_queue_mock
    end

    job = AttributesTestJob.new('mutation test')
    original_params = job.sqs_send_message_parameters.dup

    ActiveJob::QueueAdapters::ShoryukenAdapter.enqueue(job)

    # Verify that the job's parameters reference the same object sent to queue
    assert_equal(captured_params.object_id, job.sqs_send_message_parameters.object_id)
  end
end