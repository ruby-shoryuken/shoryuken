# frozen_string_literal: true

require 'active_job'
require 'active_job/queue_adapters/shoryuken_adapter'
require 'active_job/extensions'

# ActiveJob Continuations integration tests for Rails 8.1+
# Tests the stopping? method and continuation timestamp handling

# Skip if ActiveJob::Continuable is not available (Rails < 8.1)
unless defined?(ActiveJob::Continuable)
  puts "Skipping continuation tests - ActiveJob::Continuable not available (requires Rails 8.1+)"
  exit 0
end

ActiveJob::Base.queue_adapter = :shoryuken

# Test stopping? returns false when launcher is not initialized
adapter = ActiveJob::QueueAdapters::ShoryukenAdapter.new
assert_equal(false, adapter.stopping?)

# Test stopping? returns true when launcher is stopping
launcher = Shoryuken::Launcher.new
runner = Shoryuken::Runner.instance
runner.instance_variable_set(:@launcher, launcher)

adapter2 = ActiveJob::QueueAdapters::ShoryukenAdapter.new
assert_equal(false, adapter2.stopping?)

launcher.instance_variable_set(:@stopping, true)
assert_equal(true, adapter2.stopping?)

# Reset launcher state
launcher.instance_variable_set(:@stopping, false)

# Test past timestamps for continuation retries
job_capture = JobCapture.new
job_capture.start_capturing

class ContinuableTestJob < ActiveJob::Base
  include ActiveJob::Continuable if defined?(ActiveJob::Continuable)
  queue_as :default
  def perform; end
end

adapter3 = ActiveJob::QueueAdapters::ShoryukenAdapter.new
job = ContinuableTestJob.new
job.sqs_send_message_parameters = {}

past_timestamp = Time.current.to_f - 60
adapter3.enqueue_at(job, past_timestamp)

captured_job = job_capture.last_job
assert(captured_job[:delay_seconds] <= 0, "Past timestamp should result in immediate delivery")

# Test current timestamp
job_capture2 = JobCapture.new
job_capture2.start_capturing

job2 = ContinuableTestJob.new
job2.sqs_send_message_parameters = {}

current_timestamp = Time.current.to_f
adapter3.enqueue_at(job2, current_timestamp)

captured_job2 = job_capture2.last_job
delay = captured_job2[:delay_seconds]
assert(delay >= -1 && delay <= 1, "Current timestamp should have minimal delay")

# Test future timestamp
job_capture3 = JobCapture.new
job_capture3.start_capturing

job3 = ContinuableTestJob.new
job3.sqs_send_message_parameters = {}

future_timestamp = Time.current.to_f + 30
adapter3.enqueue_at(job3, future_timestamp)

captured_job3 = job_capture3.last_job
delay3 = captured_job3[:delay_seconds]
assert(delay3 > 0, "Future timestamp should have positive delay")
assert(delay3 <= 30, "Delay should not exceed scheduled time")
