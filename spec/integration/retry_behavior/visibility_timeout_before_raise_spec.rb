# frozen_string_literal: true

# This spec tests setting sqs_msg.visibility_timeout before raising from a worker.
#
# The queue's visibility timeout is 30 seconds and no retry_intervals are set. A worker that sets
# visibility_timeout = 0 and raises gets the message again at once; one that sets visibility_timeout = 2
# gets it again after about 2 seconds. Both come back well before the queue's 30 seconds.

setup_sqs

IMMEDIATE_QUEUE = DT.queues[0]
DELAYED_QUEUE = DT.queues[1]

Shoryuken.add_group('default', 2)
[IMMEDIATE_QUEUE, DELAYED_QUEUE].each do |queue_name|
  create_test_queue(queue_name, attributes: { 'VisibilityTimeout' => '30' })
  Shoryuken.add_queue(queue_name, 1, 'default')
end

def record_and_fail_first(key, sqs_msg, timeout)
  DT[key] << Time.now
  return unless sqs_msg.attributes['ApproximateReceiveCount'].to_i == 1

  sqs_msg.visibility_timeout = timeout
  raise "Simulated failure for #{key}"
end

class ImmediateWorker
  include Shoryuken::Worker

  shoryuken_options queue: IMMEDIATE_QUEUE, auto_delete: true, batch: false

  def perform(sqs_msg, _body)
    record_and_fail_first(:immediate, sqs_msg, 0)
  end
end

class DelayedWorker
  include Shoryuken::Worker

  shoryuken_options queue: DELAYED_QUEUE, auto_delete: true, batch: false

  def perform(sqs_msg, _body)
    record_and_fail_first(:delayed, sqs_msg, 2)
  end
end

Shoryuken::Client.queues(IMMEDIATE_QUEUE).send_message(message_body: 'immediate')
Shoryuken::Client.queues(DELAYED_QUEUE).send_message(message_body: 'delayed')

poll_queues_until(timeout: 20) { DT[:immediate].size >= 2 && DT[:delayed].size >= 2 }

immediate_gap = DT[:immediate][1] - DT[:immediate][0]
delayed_gap = DT[:delayed][1] - DT[:delayed][0]

assert_equal(2, DT[:immediate].size)
assert_equal(2, DT[:delayed].size)
assert(immediate_gap < 5, "visibility_timeout = 0 should redeliver at once (was #{immediate_gap}s)")
assert(delayed_gap >= 1.5, "visibility_timeout = 2 should hide the message for about 2s (was #{delayed_gap}s)")
assert(delayed_gap < 10, "visibility_timeout = 2 should redeliver well before 30s (was #{delayed_gap}s)")

assert_equal(0, queue_size(IMMEDIATE_QUEUE))
assert_equal(0, queue_size(DELAYED_QUEUE))
