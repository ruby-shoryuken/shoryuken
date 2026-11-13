# frozen_string_literal: true

# This spec tests the delays of raw worker `perform_at` and `perform_in`.
#
# A future time is delivered after its delay. A time in the past and a negative
# interval are sent at once with a delay of 0. On a FIFO queue a delay raises
# `Shoryuken::Errors::FifoDelayNotSupportedError` before anything is sent, while
# an interval of 0 and a time in the past are delivered.
#
# It used to send a past time with a negative `DelaySeconds` and a FIFO delay as
# is, both rejected by SQS with `Aws::SQS::Errors::InvalidParameterValue`.

setup_sqs

queue_name = DT.uuid
fifo_queue_name = "#{DT.uuid}.fifo"
create_test_queue(queue_name)
create_fifo_queue(fifo_queue_name)

def receive_bodies(queue_name, wait_time_seconds: 0)
  Shoryuken::Client.sqs.receive_message(
    queue_url: queue_url(queue_name),
    max_number_of_messages: 10,
    wait_time_seconds: wait_time_seconds
  ).messages.map(&:body)
end

worker = Class.new do
  include Shoryuken::Worker

  shoryuken_options queue: queue_name

  def perform(sqs_msg, body); end
end

worker.perform_at(Time.now - 60, 'past time')
worker.perform_in(-5, 'negative interval')

assert_equal(0, queue_counts(queue_name, delayed: true)[:delayed])
assert_equal(['negative interval', 'past time'], receive_bodies(queue_name).sort)

sent_at = Time.now
worker.perform_at(Time.now + 3, 'future time')

assert_equal(1, queue_counts(queue_name, delayed: true)[:delayed])
assert_equal([], receive_bodies(queue_name))

received = []
received += receive_bodies(queue_name, wait_time_seconds: 1) while received.empty? && Time.now - sent_at < 10

assert_equal(['future time'], received)
assert(Time.now - sent_at >= 2.5, 'A future time should be delivered after its delay')

perform_in_error = raised_error(Shoryuken::Errors::FifoDelayNotSupportedError) do
  worker.perform_in(5, 'fifo delay', queue: fifo_queue_name, message_group_id: 'group')
end
perform_at_error = raised_error(Shoryuken::Errors::FifoDelayNotSupportedError) do
  worker.perform_at(Time.now + 60, 'fifo time', queue: fifo_queue_name, message_group_id: 'group')
end

assert(perform_in_error, 'perform_in with a delay on a FIFO queue should raise FifoDelayNotSupportedError')
assert(perform_at_error, 'perform_at with a future time on a FIFO queue should raise FifoDelayNotSupportedError')
assert_includes(perform_in_error.message, "FIFO queue '#{fifo_queue_name}' does not support per-message delays")
assert_equal(0, queue_size(fifo_queue_name, delayed: true), 'Nothing should be sent')

worker.perform_in(0, 'fifo no delay', queue: fifo_queue_name, message_group_id: 'group')
worker.perform_at(Time.now - 60, 'fifo past time', queue: fifo_queue_name, message_group_id: 'group')

assert_equal(['fifo no delay', 'fifo past time'], receive_bodies(fifo_queue_name))

delete_test_queue(queue_name)
delete_test_queue(fifo_queue_name)
