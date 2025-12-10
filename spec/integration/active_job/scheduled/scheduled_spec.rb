# frozen_string_literal: true

# Scheduled ActiveJob integration test
# Tests jobs scheduled with set(wait:) are delivered after the delay

setup_localstack
setup_active_job

queue_name = DT.queue
create_test_queue(queue_name)

class ScheduledTestJob < ActiveJob::Base
  def perform(label)
    DT[:executions] << {
      label: label,
      job_id: job_id,
      executed_at: Time.now
    }
  end
end

ScheduledTestJob.queue_as(queue_name)

Shoryuken.add_group('default', 1)
Shoryuken.add_queue(queue_name, 1, 'default')
Shoryuken.register_worker(queue_name, Shoryuken::ActiveJob::JobWrapper)

immediate_enqueue_time = Time.now
ScheduledTestJob.perform_later('immediate')
DT[:timestamps] << { label: 'immediate', time: immediate_enqueue_time }

delayed_enqueue_time = Time.now
ScheduledTestJob.set(wait: 3.seconds).perform_later('delayed_3s')
DT[:timestamps] << { label: 'delayed_3s', time: delayed_enqueue_time }

delayed_5s_enqueue_time = Time.now
ScheduledTestJob.set(wait: 5.seconds).perform_later('delayed_5s')
DT[:timestamps] << { label: 'delayed_5s', time: delayed_5s_enqueue_time }

poll_queues_until(timeout: 30) do
  DT[:executions].size >= 3
end

assert_equal(3, DT[:executions].size, "Expected 3 job executions")

# Find each job's execution
immediate_job = DT[:executions].find { |e| e[:label] == 'immediate' }
delayed_3s_job = DT[:executions].find { |e| e[:label] == 'delayed_3s' }
delayed_5s_job = DT[:executions].find { |e| e[:label] == 'delayed_5s' }

assert(immediate_job, "Immediate job should have executed")
assert(delayed_3s_job, "3s delayed job should have executed")
assert(delayed_5s_job, "5s delayed job should have executed")

def enqueue_time(label)
  DT[:timestamps].find { |t| t[:label] == label }[:time]
end

immediate_delay = immediate_job[:executed_at] - enqueue_time('immediate')
assert(immediate_delay < 10, "Immediate job should execute within 10 seconds, took #{immediate_delay}s")

# Using 2 seconds tolerance for SQS delivery variation
delayed_3s_actual_delay = delayed_3s_job[:executed_at] - enqueue_time('delayed_3s')
assert(delayed_3s_actual_delay >= 2, "3s delayed job should execute after at least 2s, took #{delayed_3s_actual_delay}s")

delayed_5s_actual_delay = delayed_5s_job[:executed_at] - enqueue_time('delayed_5s')
assert(delayed_5s_actual_delay >= 4, "5s delayed job should execute after at least 4s, took #{delayed_5s_actual_delay}s")

assert(
  immediate_job[:executed_at] <= delayed_3s_job[:executed_at],
  "Immediate job should execute before 3s delayed job"
)
assert(
  delayed_3s_job[:executed_at] <= delayed_5s_job[:executed_at],
  "3s delayed job should execute before 5s delayed job"
)
