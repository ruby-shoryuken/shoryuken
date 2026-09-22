# frozen_string_literal: true

# A custom polling strategy can put :max_number_of_messages in the
# QueueConfiguration options. For a FIFO queue that must never raise the
# per-receive count above 1: SQS can otherwise return several messages from the
# same group in one receive, which Shoryuken would hand to separate processor
# threads and run concurrently / out of order.
#
# This drives a real launcher with a strategy that asks for 10 messages per
# receive and asserts, end-to-end, that the fetcher still caps the FIFO request
# to 1 (and that the messages are processed in order). The assertion on the
# requested count is deterministic regardless of how the SQS backend chooses to
# respond.

require 'delegate'

setup_sqs

# Records the max_number_of_messages Shoryuken actually asks SQS for, then
# forwards every call unchanged to the real client.
class RecordingSqsClient < SimpleDelegator
  def receive_message(params)
    DT[:receive_max] << params[:max_number_of_messages]
    __getobj__.receive_message(params)
  end
end

Shoryuken::Client.sqs = RecordingSqsClient.new(Shoryuken::Client.sqs)

# Strategy that requests 10 messages per receive via the queue options - the
# value the FIFO guard must clamp back down to 1.
class MaxOverridePollingStrategy < Shoryuken::Polling::BaseStrategy
  def initialize(queues, _delay = nil)
    @queue = queues.first
    @paused_until = Time.at(0)
  end

  def next_queue
    return nil if Time.now < @paused_until

    Shoryuken::Polling::QueueConfiguration.new(@queue, max_number_of_messages: 10)
  end

  # Pause briefly on an empty poll so the dispatch loop doesn't busy-spin once
  # the queue is drained.
  def messages_found(_queue, count)
    @paused_until = Time.now + 0.5 if count.zero?
  end

  def active_queues
    [[@queue, 1]]
  end
end

queue_name = "#{DT.uuid}.fifo"
create_fifo_queue(queue_name)
Shoryuken.add_group('default', 1, polling_strategy: MaxOverridePollingStrategy)
Shoryuken.add_queue(queue_name, 1, 'default')

worker_class = Class.new do
  include Shoryuken::Worker

  def perform(_sqs_msg, body)
    DT[:processed] << body
  end
end
worker_class.get_shoryuken_options['queue'] = queue_name
worker_class.get_shoryuken_options['auto_delete'] = true
worker_class.get_shoryuken_options['batch'] = false
Shoryuken.register_worker(queue_name, worker_class)

queue_url = Shoryuken::Client.sqs.get_queue_url(queue_name: queue_name).queue_url

3.times do |i|
  Shoryuken::Client.sqs.send_message(
    queue_url: queue_url,
    message_body: "msg-#{i}",
    message_group_id: 'group-a',
    message_deduplication_id: SecureRandom.uuid
  )
end

sleep 1

poll_queues_until { DT[:processed].size >= 3 }

# Messages were processed, in order...
assert_equal(%w[msg-0 msg-1 msg-2], DT[:processed])

# ...and every FIFO receive requested at most one message, even though the
# strategy asked for ten - the one-at-a-time guard stays authoritative.
assert(DT[:receive_max].any?, 'expected at least one receive_message call')
assert(
  DT[:receive_max].all? { |max| max == 1 },
  "FIFO receive should cap max_number_of_messages at 1, saw: #{DT[:receive_max].uniq.inspect}"
)
