#!/usr/bin/env ruby
# frozen_string_literal: true

# ActiveJob Continuations integration tests for Rails 8.0+
# Tests the stopping? method and continuation timestamp handling

require 'securerandom'
require 'active_job'
require 'shoryuken'

# Skip if ActiveJob::Continuable is not available (Rails < 8.0)
unless defined?(ActiveJob::Continuable)
  puts "Skipping continuation tests - ActiveJob::Continuable not available (requires Rails 8.0+)"
  exit 0
end

ActiveJob::Base.queue_adapter = :shoryuken

# Test job that uses ActiveJob Continuations
class ContinuableTestJob < ActiveJob::Base
  include ActiveJob::Continuable if defined?(ActiveJob::Continuable)

  queue_as :default

  class_attribute :executions_log, default: []
  class_attribute :checkpoints_reached, default: []

  def perform(max_iterations: 10)
    self.class.executions_log << { execution: executions, started_at: Time.current }

    step :initialize_work do
      self.class.checkpoints_reached << "initialize_work_#{executions}"
    end

    step :process_items, start: cursor || 0 do
      (cursor..max_iterations).each do |i|
        self.class.checkpoints_reached << "processing_item_#{i}"
        checkpoint
        sleep 0.01
        cursor.advance!
      end
    end

    step :finalize_work do
      self.class.checkpoints_reached << 'finalize_work'
    end

    self.class.executions_log.last[:completed] = true
  end
end

run_test_suite "ActiveJob Continuations - stopping? method (Rails 8.0)" do
  run_test "returns false when launcher is not initialized" do
    adapter = ActiveJob::QueueAdapters::ShoryukenAdapter.new
    assert_equal(false, adapter.stopping?)
  end

  run_test "returns true when launcher is stopping" do
    launcher = Shoryuken::Launcher.new
    runner = Shoryuken::Runner.instance
    runner.instance_variable_set(:@launcher, launcher)

    adapter = ActiveJob::QueueAdapters::ShoryukenAdapter.new
    assert_equal(false, adapter.stopping?)

    launcher.instance_variable_set(:@stopping, true)
    assert_equal(true, adapter.stopping?)
  end
end

run_test_suite "ActiveJob Continuations - timestamp handling (Rails 8.0)" do
  run_test "handles past timestamps for continuation retries" do
    job_capture = JobCapture.new
    job_capture.start_capturing

    adapter = ActiveJob::QueueAdapters::ShoryukenAdapter.new
    job = ContinuableTestJob.new
    job.sqs_send_message_parameters = {}

    # Enqueue with past timestamp (simulating continuation retry)
    past_timestamp = Time.current.to_f - 60
    adapter.enqueue_at(job, past_timestamp)

    captured_job = job_capture.last_job
    assert(captured_job[:delay_seconds] <= 0, "Past timestamp should result in immediate delivery")
  end

  run_test "accepts current timestamp" do
    job_capture = JobCapture.new
    job_capture.start_capturing

    adapter = ActiveJob::QueueAdapters::ShoryukenAdapter.new
    job = ContinuableTestJob.new
    job.sqs_send_message_parameters = {}

    current_timestamp = Time.current.to_f
    adapter.enqueue_at(job, current_timestamp)

    captured_job = job_capture.last_job
    delay = captured_job[:delay_seconds]
    assert(delay >= -1 && delay <= 1, "Current timestamp should have minimal delay")
  end

  run_test "accepts future timestamp" do
    job_capture = JobCapture.new
    job_capture.start_capturing

    adapter = ActiveJob::QueueAdapters::ShoryukenAdapter.new
    job = ContinuableTestJob.new
    job.sqs_send_message_parameters = {}

    future_timestamp = Time.current.to_f + 30
    adapter.enqueue_at(job, future_timestamp)

    captured_job = job_capture.last_job
    delay = captured_job[:delay_seconds]
    assert(delay > 0, "Future timestamp should have positive delay")
    assert(delay <= 30, "Delay should not exceed scheduled time")
  end
end
