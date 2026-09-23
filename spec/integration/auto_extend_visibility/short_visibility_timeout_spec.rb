# frozen_string_literal: true

# This spec tests that auto_visibility_timeout still processes messages when the
# queue's visibility timeout is short (<= EXTEND_UPFRONT_SECONDS).
#
# AutoExtendVisibility schedules a TimerTask at execution_interval =
# visibility_timeout - EXTEND_UPFRONT_SECONDS (5s). When the queue's visibility
# timeout is <= 5s that interval is <= 0, and TimerTask#initialize raises
# ArgumentError *before* the worker runs - so every receive fails and the
# message is reprocessed (and re-fails) until it hits a DLQ.
#
# Expected behavior: a short visibility timeout no longer breaks processing; the
# extension interval is clamped to a positive value and the worker runs normally.
#
# Regression: auto_visibility_timeout + a <= 5s queue visibility timeout broke
# processing entirely.

require 'timeout'

setup_sqs

DT.clear

queue_name = DT.queue
# 5s visibility timeout -> interval would be 5 - 5 = 0 -> TimerTask raised pre-fix.
create_test_queue(queue_name, attributes: { 'VisibilityTimeout' => '5' })
Shoryuken.add_group('default', 1)
Shoryuken.add_queue(queue_name, 1, 'default')

short_vt_worker = Class.new do
  include Shoryuken::Worker

  shoryuken_options auto_delete: true, auto_visibility_timeout: true

  def perform(_sqs_msg, body)
    DT[:processed] << body
  end
end

short_vt_worker.get_shoryuken_options['queue'] = queue_name
Shoryuken.register_worker(queue_name, short_vt_worker)

queue_url = Shoryuken::Client.sqs.get_queue_url(queue_name: queue_name).queue_url
Shoryuken::Client.sqs.send_message(queue_url: queue_url, message_body: 'hello')

poll_queues_until(timeout: 20) { DT[:processed].size >= 1 }

assert_equal(
  ['hello'],
  DT[:processed].to_a,
  'auto_visibility_timeout must not break processing on a queue with a short visibility timeout'
)
