# frozen_string_literal: true

# This spec tests that the error a batch worker raises reaches the exception
# handlers with its own class and message, with and without retry_intervals.
# The failed batch is not deleted: it comes back after the visibility timeout.
#
# Regression: a batch worker with retry_intervals raised a NoMethodError from
# the exponential backoff middleware, which masked the worker's error (#1030).

setup_sqs

BACKOFF_QUEUE = DT.queues[0]
PLAIN_QUEUE = DT.queues[1]
create_test_queue(BACKOFF_QUEUE, attributes: { 'VisibilityTimeout' => '1' })
create_test_queue(PLAIN_QUEUE, attributes: { 'VisibilityTimeout' => '1' })
Shoryuken.add_group('default', 2)
Shoryuken.add_queue(BACKOFF_QUEUE, 1, 'default')
Shoryuken.add_queue(PLAIN_QUEUE, 1, 'default')

BatchWorkerError = Class.new(StandardError)

original_handlers = Shoryuken.exception_handlers.dup

recorder = Object.new
recorder.define_singleton_method(:call) do |exception, queue, sqs_msg|
  DT[:errors] << { queue: queue, class: exception.class, message: exception.message, batch: sqs_msg.is_a?(Array) }
end
Shoryuken.exception_handlers << recorder

class BackoffBatchWorker
  include Shoryuken::Worker

  shoryuken_options(queue: BACKOFF_QUEUE, batch: true, auto_delete: true, retry_intervals: [60])

  def perform(_sqs_msgs, _bodies)
    DT[:batches] << BACKOFF_QUEUE
    raise BatchWorkerError, "#{BACKOFF_QUEUE} batch failed"
  end
end

class PlainBatchWorker
  include Shoryuken::Worker

  shoryuken_options(queue: PLAIN_QUEUE, batch: true, auto_delete: true)

  def perform(_sqs_msgs, _bodies)
    DT[:batches] << PLAIN_QUEUE
    raise BatchWorkerError, "#{PLAIN_QUEUE} batch failed"
  end
end

Shoryuken::Client.queues(BACKOFF_QUEUE).send_message(message_body: 'backoff')
Shoryuken::Client.queues(PLAIN_QUEUE).send_message(message_body: 'plain')

begin
  poll_queues_until(timeout: 20) do
    [BACKOFF_QUEUE, PLAIN_QUEUE].all? { |queue| DT[:batches].count(queue) >= 2 }
  end

  [BACKOFF_QUEUE, PLAIN_QUEUE].each do |queue|
    errors = DT[:errors].select { |error| error[:queue] == queue }

    assert(errors.size >= 2, "Expected a handler call per failed batch of #{queue}: #{errors}")
    errors.each do |error|
      assert_equal(BatchWorkerError, error[:class])
      assert_equal("#{queue} batch failed", error[:message])
      assert(error[:batch], 'Expected the handler to receive the batch')
    end
  end
ensure
  Shoryuken.exception_handlers.replace(original_handlers)
end
