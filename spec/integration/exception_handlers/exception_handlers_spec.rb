# frozen_string_literal: true

# This spec tests custom exception handlers.
# Exception handlers are called when a worker raises an error.

setup_localstack

queue_name = DT.queue
create_test_queue(queue_name, attributes: { 'VisibilityTimeout' => '2' })
Shoryuken.add_group('default', 1)
Shoryuken.add_queue(queue_name, 1, 'default')

# Save original handlers to restore later
original_handlers = Shoryuken.exception_handlers.dup

# Custom exception handler that records exceptions
custom_handler = Object.new
custom_handler.define_singleton_method(:call) do |exception, queue, sqs_msg|
  DT[:exceptions] << {
    message: exception.message,
    queue: queue,
    message_id: sqs_msg.message_id
  }
end

# Add custom handler alongside default
Shoryuken.exception_handlers << custom_handler

worker_class = Class.new do
  include Shoryuken::Worker

  shoryuken_options auto_delete: false, batch: false

  def perform(sqs_msg, body)
    receive_count = sqs_msg.attributes['ApproximateReceiveCount'].to_i
    DT[:attempts] << receive_count

    if receive_count < 2
      raise 'Intentional failure for testing'
    end

    # Succeed on second attempt and delete
    DT[:success] << body
    sqs_msg.delete
  end
end

worker_class.get_shoryuken_options['queue'] = queue_name
Shoryuken.register_worker(queue_name, worker_class)

Shoryuken::Client.queues(queue_name).send_message(message_body: 'exception test')

sleep 1

begin
  poll_queues_until(timeout: 15) { DT[:success].size >= 1 }

  # Verify exception handler was called on first attempt
  assert(DT[:exceptions].size >= 1, 'Exception handler should have been called')
  assert_equal('Intentional failure for testing', DT[:exceptions].first[:message])
  assert_equal(queue_name, DT[:exceptions].first[:queue])

  # Verify message was eventually processed successfully
  assert_equal(1, DT[:success].size)
  assert_equal('exception test', DT[:success].first)
ensure
  # Restore original handlers to prevent cross-test interference
  Shoryuken.exception_handlers.replace(original_handlers)
end
