# frozen_string_literal: true

# This spec tests a worker that deletes its message and then raises, with retry_intervals set.
# It used to let the error from rescheduling the deleted message escape the middleware and mask the original error.
#
# The visibility change on the stale receipt handle fails and is logged, the original worker error
# is re-raised and reaches the exception handlers, and the message stays deleted.
#
# Regression: #328 (fixed in #1030)

setup_sqs

log = StringIO.new
Shoryuken.logger = Logger.new(log)

queue_name = DT.queue
create_test_queue(queue_name, attributes: { 'VisibilityTimeout' => '3' })
Shoryuken.add_group('default', 1)
Shoryuken.add_queue(queue_name, 1, 'default')

Shoryuken.exception_handlers = [
  lambda do |error, _queue, _sqs_msg|
    DT[:handled] << error
    DT[:handled_at] << Time.now
  end
]

worker = Class.new do
  include Shoryuken::Worker

  shoryuken_options queue: queue_name, auto_delete: true, retry_intervals: [1]

  define_method(:perform) do |sqs_msg, _body|
    DT[:message_ids] << sqs_msg.message_id
    sqs_msg.delete
    raise 'original worker error'
  end
end
Shoryuken.register_worker(queue_name, worker)

Shoryuken::Client.queues(queue_name).send_message(message_body: 'deleted then raised')

# Keep polling long enough for a rescheduled (1 s) or released (3 s) message to come back
poll_queues_until(timeout: 20) { DT[:handled_at].any? && Time.now - DT[:handled_at].first >= 4 }

assert_equal(['original worker error'], DT[:handled].map(&:message))
assert_equal(RuntimeError, DT[:handled].first.class)
assert_includes(log.string, "Failed to set backoff visibility timeout for #{DT[:message_ids].first}")
assert_equal(1, DT[:message_ids].size, 'the deleted message must not be received again')
assert_equal(0, queue_size(queue_name))
