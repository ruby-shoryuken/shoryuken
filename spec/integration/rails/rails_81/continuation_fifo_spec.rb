# frozen_string_literal: true

# This spec tests that an ActiveJob::Continuable job enqueued with .set on a
# FIFO queue resumes in its message group with its custom message attributes.
#
# It used to send the resume with the default ShoryukenMessage group and
# without the custom attributes, as the job the worker deserializes had no SQS
# parameters.

setup_sqs
setup_active_job

queue_name = "#{DT.uuid}.fifo"
create_fifo_queue(queue_name)

module StopOnce
  def stopping?
    return false unless DT[:stops].empty?

    DT[:stops] << true
    true
  end
end

ActiveJob::QueueAdapters::ShoryukenAdapter.prepend(StopOnce)

class FifoContinuationJob < ActiveJob::Base
  include ActiveJob::Continuable

  # FIFO queues do not support per-message delays
  self.resume_options = { wait: 0 }

  def perform
    step(:one) { DT[:steps] << :one }
    step(:two) { DT[:steps] << :two }
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

FifoContinuationJob.queue_as(queue_name)

Shoryuken.server_middleware { |chain| chain.add(ReceivedMessageRecorder) }
Shoryuken.add_group('default', 1)
Shoryuken.add_queue(queue_name, 1, 'default')
Shoryuken.register_worker(queue_name, Shoryuken::ActiveJob::JobWrapper)

FifoContinuationJob.set(
  message_group_id: 'order-42',
  message_attributes: { 'tenant' => { string_value: 'acme', data_type: 'String' } }
).perform_later

poll_queues_until(timeout: 30) { DT[:steps].include?(:two) }

assert_equal(%i[one two], DT[:steps])
assert_equal(
  [{ group: 'order-42', tenant: 'acme' }, { group: 'order-42', tenant: 'acme' }],
  DT[:received]
)

delete_test_queue(queue_name)
