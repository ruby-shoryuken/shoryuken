# frozen_string_literal: true

# ActiveJob custom numeric message attributes are sent to SQS with correct data type

setup_localstack
setup_active_job

queue_name = DT.queue
create_test_queue(queue_name)

class NumberAttributesTestJob < ActiveJob::Base
  def perform
    DT[:executions] << { job_id: job_id }
  end
end

NumberAttributesTestJob.queue_as(queue_name)

Shoryuken.add_group('default', 1)
Shoryuken.add_queue(queue_name, 1, 'default')
Shoryuken.register_worker(queue_name, Shoryuken::ActiveJob::JobWrapper)

job = NumberAttributesTestJob.new
job.sqs_send_message_parameters = {
  message_attributes: {
    'priority' => { string_value: '10', data_type: 'Number' },
    'retry_count' => { string_value: '0', data_type: 'Number' }
  }
}
ActiveJob::QueueAdapters::ShoryukenAdapter.enqueue(job)

poll_queues_until(timeout: 30) { DT[:executions].size >= 1 }

params = job.sqs_send_message_parameters
assert(params[:message_attributes].key?('priority'))
assert_equal('10', params[:message_attributes]['priority'][:string_value])
assert_equal('Number', params[:message_attributes]['priority'][:data_type])
