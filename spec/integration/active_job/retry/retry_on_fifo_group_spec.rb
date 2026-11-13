# frozen_string_literal: true

# This spec tests that a retry_on retry of a job enqueued with .set on a FIFO
# queue keeps the message group id and the custom message attributes.
#
# It used to send the retry with the default ShoryukenMessage group and without
# the custom attributes, as the job the worker deserializes had no SQS
# parameters.

setup_sqs
setup_active_job

queue_name = "#{DT.uuid}.fifo"
create_fifo_queue(queue_name)

class FifoGroupRetryJob < ActiveJob::Base
  retry_on RuntimeError, wait: 0, attempts: 2

  def perform
    raise 'Simulated failure' if executions == 1

    DT[:successes] << executions
  end
end

class ReceivedMessageRecorder
  def call(_worker_instance, _queue, sqs_msg, _body)
    DT[:received] << {
      group: sqs_msg.attributes['MessageGroupId'],
      tenant: sqs_msg.message_attributes['tenant']&.string_value
    }
    yield
  end
end

FifoGroupRetryJob.queue_as(queue_name)

Shoryuken.server_middleware { |chain| chain.add(ReceivedMessageRecorder) }
Shoryuken.add_group('default', 1)
Shoryuken.add_queue(queue_name, 1, 'default')
Shoryuken.register_worker(queue_name, Shoryuken::ActiveJob::JobWrapper)

FifoGroupRetryJob.set(
  message_group_id: 'order-42',
  message_attributes: { 'tenant' => { string_value: 'acme', data_type: 'String' } }
).perform_later

poll_queues_until(timeout: 30) { DT[:successes].size >= 1 }

assert_equal([2], DT[:successes])
assert_equal(
  [{ group: 'order-42', tenant: 'acme' }, { group: 'order-42', tenant: 'acme' }],
  DT[:received]
)

delete_test_queue(queue_name)
