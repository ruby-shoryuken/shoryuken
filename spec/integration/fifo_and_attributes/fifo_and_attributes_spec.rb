# frozen_string_literal: true

require 'active_job'
require 'active_job/queue_adapters/shoryuken_adapter'

# This spec tests FIFO queue support including message deduplication ID generation
# and message attributes handling.

require 'digest'
require 'json'

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

# Test FIFO queue message deduplication ID generation
fifo_queue_mock = Object.new
fifo_queue_mock.define_singleton_method(:fifo?) { true }
fifo_queue_mock.define_singleton_method(:name) { 'test_fifo.fifo' }

captured_params = nil
fifo_queue_mock.define_singleton_method(:send_message) do |params|
  captured_params = params
end

Shoryuken::Client.define_singleton_method(:queues) do |queue_name = nil|
  if queue_name
    fifo_queue_mock
  else
    { test_fifo: fifo_queue_mock }
  end
end

Shoryuken.define_singleton_method(:register_worker) { |*args| nil }

FifoTestJob.perform_later('order-123', 'process')

assert(captured_params.key?(:message_deduplication_id))
assert_equal(64, captured_params[:message_deduplication_id].length)

# Verify deduplication ID excludes job_id and enqueued_at
body = captured_params[:message_body]
body_without_variable_fields = body.except('job_id', 'enqueued_at')
expected_dedupe_id = Digest::SHA256.hexdigest(JSON.dump(body_without_variable_fields))
assert_equal(expected_dedupe_id, captured_params[:message_deduplication_id])

# Test custom message attributes
regular_queue_mock = Object.new
regular_queue_mock.define_singleton_method(:fifo?) { false }
regular_queue_mock.define_singleton_method(:name) { 'attributes_test' }

captured_attrs = nil
regular_queue_mock.define_singleton_method(:send_message) do |params|
  captured_attrs = params
end

Shoryuken::Client.define_singleton_method(:queues) do |queue_name = nil|
  regular_queue_mock
end

custom_attributes = {
  'trace_id' => { string_value: 'trace-123', data_type: 'String' },
  'priority' => { string_value: 'high', data_type: 'String' }
}

job = AttributesTestJob.new('test data')
job.sqs_send_message_parameters = { message_attributes: custom_attributes }
ActiveJob::QueueAdapters::ShoryukenAdapter.enqueue(job)

attributes = captured_attrs[:message_attributes]
assert_equal(custom_attributes['trace_id'], attributes['trace_id'])
assert_equal(custom_attributes['priority'], attributes['priority'])

# Should still include required Shoryuken attribute
expected_shoryuken_class = {
  string_value: "Shoryuken::ActiveJob::JobWrapper",
  data_type: 'String'
}
assert_equal(expected_shoryuken_class, attributes['shoryuken_class'])
