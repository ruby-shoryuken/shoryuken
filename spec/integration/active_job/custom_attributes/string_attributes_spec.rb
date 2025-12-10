# frozen_string_literal: true

# ActiveJob custom string message attributes are sent to SQS and preserved

setup_localstack
setup_active_job

queue_name = DT.queue
create_test_queue(queue_name)

class StringAttributesTestJob < ActiveJob::Base
  def perform
    DT[:executions] << { job_id: job_id }
  end
end

StringAttributesTestJob.queue_as(queue_name)

Shoryuken.add_group('default', 1)
Shoryuken.add_queue(queue_name, 1, 'default')
Shoryuken.register_worker(queue_name, Shoryuken::ActiveJob::JobWrapper)

job = StringAttributesTestJob.new
job.sqs_send_message_parameters = {
  message_attributes: {
    'trace_id' => { string_value: 'trace-abc-123', data_type: 'String' },
    'correlation_id' => { string_value: 'corr-xyz-789', data_type: 'String' }
  }
}
ActiveJob::QueueAdapters::ShoryukenAdapter.enqueue(job)

poll_queues_until(timeout: 30) { DT[:executions].size >= 1 }

params = job.sqs_send_message_parameters
assert(params[:message_attributes].key?('trace_id'))
assert(params[:message_attributes].key?('correlation_id'))
assert(params[:message_attributes].key?('shoryuken_class'))
assert_equal('trace-abc-123', params[:message_attributes]['trace_id'][:string_value])
assert_equal('corr-xyz-789', params[:message_attributes]['correlation_id'][:string_value])
