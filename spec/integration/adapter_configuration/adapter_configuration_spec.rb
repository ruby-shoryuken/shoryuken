#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative '../../integrations_helper'

begin
  require 'active_job'
  require 'shoryuken'
rescue LoadError => e
  puts "Failed to load dependencies: #{e.message}"
  exit 1
end

ActiveJob::Base.queue_adapter = :shoryuken

class ConfigTestJob < ActiveJob::Base
  queue_as :config_test

  def perform(data)
    "Processed: #{data}"
  end
end

class QueuePrefixJob < ActiveJob::Base
  def self.queue_name_prefix
    'prefix'
  end

  queue_as :test

  def perform(data)
    "Processed: #{data}"
  end
end

class DynamicQueueJob < ActiveJob::Base
  queue_as do
    if defined?(Rails) && Rails.respond_to?(:env)
      "#{Rails.env}_dynamic"
    else
      'test_dynamic'
    end
  end

  def perform(data)
    "Processed: #{data}"
  end
end

run_test_suite "Adapter Configuration" do
  run_test "correctly identifies adapter type" do
    adapter = ActiveJob::Base.queue_adapter
    assert_equal("ActiveJob::QueueAdapters::ShoryukenAdapter", adapter.class.name)
  end

  run_test "supports Rails 7.2+ transaction commit hook" do
    adapter = ActiveJob::QueueAdapters::ShoryukenAdapter.new
    assert(adapter.respond_to?(:enqueue_after_transaction_commit?))
    assert_equal(true, adapter.enqueue_after_transaction_commit?)
  end

  run_test "maintains singleton pattern" do
    instance1 = ActiveJob::QueueAdapters::ShoryukenAdapter.instance
    instance2 = ActiveJob::QueueAdapters::ShoryukenAdapter.instance

    assert_equal(instance1.object_id, instance2.object_id)
    assert(instance1.is_a?(ActiveJob::QueueAdapters::ShoryukenAdapter))
  end
end

run_test_suite "Queue Name Resolution" do
  run_test "handles basic queue names" do
    job_capture = JobCapture.new
    job_capture.start_capturing

    ConfigTestJob.perform_later('basic test')

    job = job_capture.last_job
    message_body = job[:message_body]
    assert_equal('config_test', message_body['queue_name'])
  end

  run_test "handles queue name prefixes" do
    job_capture = JobCapture.new
    job_capture.start_capturing

    QueuePrefixJob.perform_later('prefix test')

    job = job_capture.last_job
    message_body = job[:message_body]
    assert_equal('prefix_test', message_body['queue_name'])
  end

  run_test "handles dynamic queue names" do
    job_capture = JobCapture.new
    job_capture.start_capturing

    DynamicQueueJob.perform_later('dynamic test')

    job = job_capture.last_job
    message_body = job[:message_body]
    assert_equal('test_dynamic', message_body['queue_name'])
  end
end

run_test_suite "Delay Calculation" do
  run_test "calculates correct delay for future timestamps" do
    job_capture = JobCapture.new
    job_capture.start_capturing

    future_time = Time.current + 5.minutes
    ConfigTestJob.set(wait_until: future_time).perform_later('delayed test')

    job = job_capture.last_job
    delay = job[:delay_seconds]
    assert(delay >= 295 && delay <= 305)  # 5 minutes ± 5 seconds
  end

  run_test "enforces 15 minute maximum delay" do
    adapter = ActiveJob::QueueAdapters::ShoryukenAdapter.new
    far_future = Time.current + 20.minutes

    job = ConfigTestJob.new('too far')

    assert_raises(RuntimeError) do
      adapter.enqueue_at(job, far_future.to_f)
    end
  end

  run_test "handles immediate execution" do
    job_capture = JobCapture.new
    job_capture.start_capturing

    adapter = ActiveJob::QueueAdapters::ShoryukenAdapter.new
    job = ConfigTestJob.new('immediate')
    adapter.enqueue_at(job, Time.current.to_f)

    captured_job = job_capture.last_job
    assert_equal(0, captured_job[:delay_seconds])
  end

  run_test "handles negative delays as immediate" do
    job_capture = JobCapture.new
    job_capture.start_capturing

    adapter = ActiveJob::QueueAdapters::ShoryukenAdapter.new
    job = ConfigTestJob.new('past')
    past_time = Time.current - 1.minute
    adapter.enqueue_at(job, past_time.to_f)

    captured_job = job_capture.last_job
    # Should be 0 or negative delay gets rounded to 0
    assert(captured_job[:delay_seconds] <= 0)
  end
end

run_test_suite "Message Parameter Handling" do
  run_test "merges job parameters correctly" do
    queue_mock = Object.new
    queue_mock.define_singleton_method(:fifo?) { false }
    queue_mock.define_singleton_method(:name) { 'config_test' }

    captured_params = nil
    queue_mock.define_singleton_method(:send_message) do |params|
      captured_params = params
    end

    Shoryuken::Client.define_singleton_method(:queues) do |queue_name = nil|
      queue_mock
    end

    Shoryuken.define_singleton_method(:register_worker) { |*args| nil }

    job = ConfigTestJob.new('param test')
    job.sqs_send_message_parameters.merge!({
      custom_param: 'custom_value',
      message_attributes: { 'custom' => { string_value: 'test', data_type: 'String' } }
    })

    ActiveJob::QueueAdapters::ShoryukenAdapter.enqueue(job)

    assert_equal('custom_value', captured_params[:custom_param])
    assert_equal('test', captured_params[:message_attributes]['custom'][:string_value])

    # Should still include required Shoryuken attributes
    expected_shoryuken_class = {
      string_value: "Shoryuken::ActiveJob::JobWrapper",
      data_type: 'String'
    }
    assert_equal(expected_shoryuken_class, captured_params[:message_attributes]['shoryuken_class'])
  end
end

run_test_suite "Edge Cases" do
  run_test "handles very large argument counts" do
    job_capture = JobCapture.new
    job_capture.start_capturing

    # Create job with many arguments
    many_args = (1..50).to_a

    class ManyArgsJob < ActiveJob::Base
      queue_as :default

      def perform(*args)
        "Processed #{args.length} arguments"
      end
    end

    ManyArgsJob.perform_later(*many_args)

    job = job_capture.last_job
    message_body = job[:message_body]
    assert_equal(50, message_body['arguments'].length)
    assert_equal(many_args, message_body['arguments'])
  end

  run_test "handles unicode and special characters" do
    job_capture = JobCapture.new
    job_capture.start_capturing

    unicode_data = "Hello 世界 🌍 Special chars: àáâãäåæç"
    ConfigTestJob.perform_later(unicode_data)

    job = job_capture.last_job
    message_body = job[:message_body]
    assert_equal(unicode_data, message_body['arguments'].first)
  end

  run_test "handles deeply nested data structures" do
    job_capture = JobCapture.new
    job_capture.start_capturing

    nested_data = {
      'level1' => {
        'level2' => {
          'level3' => {
            'array' => [1, 2, { 'nested_array' => ['a', 'b', 'c'] }],
            'boolean' => true,
            'null' => nil
          }
        }
      }
    }

    ConfigTestJob.perform_later(nested_data)

    job = job_capture.last_job
    message_body = job[:message_body]
    args_data = message_body['arguments'].first

    assert_equal('c', args_data['level1']['level2']['level3']['array'][2]['nested_array'][2])
    assert_equal(true, args_data['level1']['level2']['level3']['boolean'])
    assert_equal(nil, args_data['level1']['level2']['level3']['null'])
  end
end