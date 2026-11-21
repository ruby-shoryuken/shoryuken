# frozen_string_literal: true

# This spec tests a message body that the worker's body_parser cannot parse.
#
# The body is parsed before the server middleware chain runs, so the parse
# error skips the chain: the worker never runs, the error reaches the exception
# handlers and the message is not deleted. It comes back after the queue's
# visibility timeout, also when the worker lists the error in
# `non_retryable_exceptions` or sets `retry_intervals`.

setup_sqs

ParserFailure = Class.new(StandardError)

plain_queue, non_retryable_queue, backoff_queue, proc_queue = DT.uuids(4)
queues = [plain_queue, non_retryable_queue, backoff_queue, proc_queue]
queues.each { |queue| create_test_queue(queue, attributes: { 'VisibilityTimeout' => '2' }) }
Shoryuken.add_group('default', 4)
queues.each { |queue| Shoryuken.add_queue(queue, 1, 'default') }

Shoryuken.exception_handlers = [
  ->(error, queue, _sqs_msg) { DT[:handled] << [queue, error.class, Time.now] }
]

{
  plain_queue => { body_parser: :json },
  non_retryable_queue => { body_parser: :json, non_retryable_exceptions: [JSON::ParserError] },
  backoff_queue => { body_parser: :json, retry_intervals: [30] },
  proc_queue => { body_parser: ->(_sqs_msg) { raise ParserFailure, 'cannot parse' } }
}.each do |queue, options|
  Class.new do
    include Shoryuken::Worker

    shoryuken_options queue: queue, auto_delete: true, **options

    define_method(:perform) { |_sqs_msg, _body| DT[:performed] << queue }
  end

  Shoryuken::Client.queues(queue).send_message(message_body: '{not json')
end

poll_queues_until(timeout: 20) do
  [plain_queue, proc_queue].all? { |queue| DT[:handled].count { |handled_queue, _, _| handled_queue == queue } >= 3 }
end

handled = DT[:handled].group_by(&:first)

assert_equal([], DT[:performed], 'the worker must not run for a body it cannot parse')

[non_retryable_queue, backoff_queue].each do |queue|
  assert(
    handled.fetch(queue, []).size >= 2,
    "#{queue}: the parse error must skip the middleware and come back: #{handled[queue].inspect}"
  )
end

[plain_queue, non_retryable_queue, backoff_queue].each do |queue|
  assert_equal([JSON::ParserError], handled[queue].map { |_, error_class, _| error_class }.uniq)
end
assert_equal([ParserFailure], handled[proc_queue].map { |_, error_class, _| error_class }.uniq)

queues.each do |queue|
  gaps = handled[queue].map(&:last).each_cons(2).map { |earlier, later| later - earlier }
  assert(
    gaps.all? { |gap| gap.between?(1, 10) },
    "#{queue}: the message must come back after the 2s visibility timeout, not be deleted or delayed: #{gaps}"
  )
  assert_equal(1, queue_size(queue), "#{queue}: the message must not be deleted")
end

queues.each { |queue| delete_test_queue(queue) }
