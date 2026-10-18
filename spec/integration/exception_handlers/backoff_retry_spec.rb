# frozen_string_literal: true

# This spec tests which worker failures reach the exception handlers when the
# exponential backoff middleware is in play.
#
# Expected behavior: a failure that `retry_intervals` schedules for a retry is
# rescued by the middleware, so the exception handlers are not called and the
# message comes back after the interval, not after the queue's visibility
# timeout. A failure without `retry_intervals`, or one whose interval lambda
# returns nil (no retry scheduled), is re-raised and reaches the handlers.

setup_sqs

backoff_queue, plain_queue, unscheduled_queue = DT.uuids(3)
create_test_queue(backoff_queue, attributes: { 'VisibilityTimeout' => '30' })
create_test_queue(plain_queue, attributes: { 'VisibilityTimeout' => '2' })
create_test_queue(unscheduled_queue, attributes: { 'VisibilityTimeout' => '2' })
Shoryuken.add_group('default', 1)
[backoff_queue, plain_queue, unscheduled_queue].each { |queue| Shoryuken.add_queue(queue, 1, 'default') }

Shoryuken.exception_handlers = [
  ->(_error, queue, sqs_msg) { DT[:handled] << [queue, sqs_msg.attributes['ApproximateReceiveCount'].to_i] }
]

{
  backoff_queue => { retry_intervals: [1] },
  plain_queue => {},
  unscheduled_queue => { retry_intervals: ->(_attempts) {} }
}.each do |queue, options|
  Class.new do
    include Shoryuken::Worker

    shoryuken_options queue: queue, auto_delete: true, **options

    define_method(:perform) do |sqs_msg, _body|
      receive_count = sqs_msg.attributes['ApproximateReceiveCount'].to_i
      DT[queue] << [receive_count, Time.now]
      raise "failure on attempt #{receive_count}" if receive_count < 3
    end
  end

  Shoryuken::Client.queues(queue).send_message(message_body: 'fails twice')
end

poll_queues_until(timeout: 20) do
  [backoff_queue, plain_queue, unscheduled_queue].all? { |queue| DT[queue].size >= 3 }
end

handled = DT[:handled].group_by(&:first).transform_values { |calls| calls.map(&:last) }

# --- Retried by retry_intervals ---
receive_counts, times = DT[backoff_queue].transpose
assert_equal([1, 2, 3], receive_counts)
gaps = times.each_cons(2).map { |earlier, later| later - earlier }
assert(gaps.all? { |gap| gap.between?(1, 10) }, "retries must follow the 1s interval, not the 30s VisibilityTimeout: #{gaps}")
assert_equal(nil, handled[backoff_queue], 'a scheduled retry must not reach the exception handlers')

# --- No retry_intervals ---
assert_equal([1, 2], handled[plain_queue])

# --- Interval lambda returns nil ---
assert_equal([1, 2], handled[unscheduled_queue])

[backoff_queue, plain_queue, unscheduled_queue].each { |queue| delete_test_queue(queue) }
