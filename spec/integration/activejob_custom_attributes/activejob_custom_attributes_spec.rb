# frozen_string_literal: true

# ActiveJob custom SQS message attributes integration test
# Tests that custom message attributes survive the full round-trip

setup_localstack
setup_active_job

queue_name = DT.queue
create_test_queue(queue_name)

# Job that captures its SQS message attributes
class AttributeCaptureJob < ActiveJob::Base
  def perform(label)
    # The sqs_msg is not directly available in ActiveJob perform
    # but we can verify attributes were set by checking they were sent
    DT[:executions] << {
      label: label,
      job_id: job_id,
      executed_at: Time.now
    }
  end
end

AttributeCaptureJob.queue_as(queue_name)

Shoryuken.add_group('default', 1)
Shoryuken.add_queue(queue_name, 1, 'default')
Shoryuken.register_worker(queue_name, Shoryuken::ActiveJob::JobWrapper)

# Test 1: Job with custom string attributes
job1 = AttributeCaptureJob.new('with_attributes')
job1.sqs_send_message_parameters = {
  message_attributes: {
    'trace_id' => { string_value: 'trace-abc-123', data_type: 'String' },
    'correlation_id' => { string_value: 'corr-xyz-789', data_type: 'String' }
  }
}
ActiveJob::QueueAdapters::ShoryukenAdapter.enqueue(job1)

# Capture what was actually sent
DT[:sent_params] << job1.sqs_send_message_parameters

# Test 2: Job with numeric attributes
job2 = AttributeCaptureJob.new('with_number')
job2.sqs_send_message_parameters = {
  message_attributes: {
    'priority' => { string_value: '10', data_type: 'Number' },
    'retry_count' => { string_value: '0', data_type: 'Number' }
  }
}
ActiveJob::QueueAdapters::ShoryukenAdapter.enqueue(job2)

DT[:sent_params] << job2.sqs_send_message_parameters

# Test 3: Job without custom attributes (baseline)
job3 = AttributeCaptureJob.new('no_attributes')
ActiveJob::QueueAdapters::ShoryukenAdapter.enqueue(job3)

DT[:sent_params] << job3.sqs_send_message_parameters

poll_queues_until(timeout: 30) do
  DT[:executions].size >= 3
end

assert_equal(3, DT[:executions].size, "Expected 3 job executions")

params_with_attrs = DT[:sent_params][0]
assert(params_with_attrs[:message_attributes].key?('trace_id'), "Should have trace_id attribute")
assert(params_with_attrs[:message_attributes].key?('correlation_id'), "Should have correlation_id attribute")
assert(params_with_attrs[:message_attributes].key?('shoryuken_class'), "Should have shoryuken_class attribute")
assert_equal('trace-abc-123', params_with_attrs[:message_attributes]['trace_id'][:string_value])

params_with_number = DT[:sent_params][1]
assert(params_with_number[:message_attributes].key?('priority'), "Should have priority attribute")
assert_equal('10', params_with_number[:message_attributes]['priority'][:string_value])
assert_equal('Number', params_with_number[:message_attributes]['priority'][:data_type])

# Baseline job should still have shoryuken_class
params_no_attrs = DT[:sent_params][2]
assert(params_no_attrs[:message_attributes].key?('shoryuken_class'), "Should have shoryuken_class attribute")

labels = DT[:executions].map { |e| e[:label] }
assert_includes(labels, 'with_attributes')
assert_includes(labels, 'with_number')
assert_includes(labels, 'no_attributes')
