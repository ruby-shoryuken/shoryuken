# frozen_string_literal: true

# This spec tests the log line when a retry_intervals lambda raises.
#
# The middleware logs that retry_intervals raised, with the error class and message, and not
# "Failed to set backoff visibility timeout" (no visibility change was attempted). The original worker error is
# re-raised, so it reaches the exception handlers and the message comes back after the queue's visibility timeout.

setup_sqs

log = StringIO.new
Shoryuken.logger = Logger.new(log)

queue_name = DT.queue
create_test_queue(queue_name, attributes: { 'VisibilityTimeout' => '1' })
Shoryuken.add_group('default', 1)
Shoryuken.add_queue(queue_name, 1, 'default')

Shoryuken.exception_handlers = [->(error, _queue, _sqs_msg) { DT[:handled] << error.message }]

worker = Class.new do
  include Shoryuken::Worker

  shoryuken_options(
    queue: queue_name, auto_delete: true,
    retry_intervals: ->(_attempts) { raise ArgumentError, 'bad interval' }
  )

  define_method(:perform) do |sqs_msg, _body|
    DT[:message_ids] << sqs_msg.message_id
    raise 'original worker error' if DT[:message_ids].size < 2
  end
end
Shoryuken.register_worker(queue_name, worker)

Shoryuken::Client.queues(queue_name).send_message(message_body: 'raising retry_intervals')

poll_queues_until(timeout: 20) { DT[:message_ids].size >= 2 }

message_id = DT[:message_ids].first

assert_equal(['original worker error'], DT[:handled])
assert_includes(log.string, "retry_intervals raised for #{message_id}: ArgumentError: bad interval")
refute(log.string.include?('Failed to set backoff visibility timeout'), 'the visibility change was never attempted')
