# frozen_string_literal: true

# This spec tests that message attributes survive a redrive to the dead letter queue.
# Expected behavior: a perform_async job that fails maxReceiveCount times moves to the DLQ with its
# shoryuken_class and custom attributes intact, so Shoryuken polling the DLQ runs the original worker,
# not the worker registered for the DLQ.
# Regression: #659

setup_sqs

queue_name = DT.queues[0]
dlq_name = DT.queues[1]

create_queue_with_dlq(queue_name, dlq_name, attributes: { 'VisibilityTimeout' => '1' })

Shoryuken.add_group('default', 1)
Shoryuken.add_queue(queue_name, 1, 'default')
Shoryuken.add_queue(dlq_name, 1, 'default')

class DlqOriginalWorker
  include Shoryuken::Worker

  shoryuken_options auto_delete: true

  def perform(sqs_msg, _body)
    DT[:runs] << [
      sqs_msg.queue_name,
      self.class.name,
      sqs_msg.message_attributes.dig('tenant', :string_value)
    ]

    raise 'fails until redriven' unless sqs_msg.queue_name == DT.queues[1]
  end
end

class DlqFallbackWorker
  include Shoryuken::Worker

  shoryuken_options auto_delete: true

  def perform(sqs_msg, _body)
    DT[:runs] << [sqs_msg.queue_name, self.class.name, nil]
  end
end

DlqOriginalWorker.get_shoryuken_options['queue'] = queue_name
# Without shoryuken_class, messages on either queue go to the fallback worker
Shoryuken.register_worker(queue_name, DlqFallbackWorker)
Shoryuken.register_worker(dlq_name, DlqFallbackWorker)

DlqOriginalWorker.perform_async(
  'payload',
  message_attributes: { 'tenant' => { string_value: 'acme', data_type: 'String' } }
)

poll_queues_until(timeout: 30) do
  DT[:runs].any? { |queue, worker, _| queue == dlq_name || worker == 'DlqFallbackWorker' }
end

assert_equal(
  [
    [queue_name, 'DlqOriginalWorker', 'acme'],
    [queue_name, 'DlqOriginalWorker', 'acme'],
    [dlq_name, 'DlqOriginalWorker', 'acme']
  ],
  DT[:runs]
)
assert_equal(0, queue_size(queue_name))
assert_equal(0, queue_size(dlq_name))
