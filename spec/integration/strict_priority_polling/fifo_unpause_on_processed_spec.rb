# frozen_string_literal: true

# This spec tests that StrictPriority unpauses a FIFO queue when its in-flight
# message is processed, instead of waiting for the `delay`.
#
# - Two messages share one message group, so the second stays hidden while the
#   first is in flight
# - The poll that finds no visible message pauses the FIFO queue for 30 seconds
# - When the first message is processed, the queue is unpaused and the second
#   message runs within a few seconds
#
# Regression: #643

class RecordingStrictPriority < Shoryuken::Polling::StrictPriority
  def message_processed(queue)
    DT[:paused_on_processed] << !active_queues.to_h.key?(queue)
    super
  end
end

setup_sqs

queue = "#{DT.uuid}.fifo"
create_fifo_queue(queue)

# A long delay keeps the FIFO queue paused unless message_processed unpauses it
Shoryuken.options[:delay] = 30
Shoryuken.add_group('default', 4, polling_strategy: RecordingStrictPriority)
Shoryuken.add_queue(queue, 1, 'default')

class SlowFifoWorker
  include Shoryuken::Worker

  shoryuken_options auto_delete: true, batch: false

  def perform(_sqs_msg, body)
    # Keeps the first message in flight long enough for an empty poll to pause the queue
    sleep 2
    DT[:processed] << { body: body, at: Process.clock_gettime(Process::CLOCK_MONOTONIC) }
  end
end

Shoryuken.register_worker(queue, SlowFifoWorker)

2.times do |i|
  Shoryuken::Client.queues(queue).send_message(
    message_body: "fifo-#{i}",
    message_group_id: 'group'
  )
end

poll_queues_until(timeout: 20) { DT[:processed].size >= 2 }

assert_equal(%w[fifo-0 fifo-1], DT[:processed].map { |m| m[:body] })
assert_equal(true, DT[:paused_on_processed].first, 'FIFO queue was not paused while its group was in flight')

gap = DT[:processed][1][:at] - DT[:processed][0][:at]
assert(gap < 10, "Second message ran #{gap.round(2)}s after the first, the queue stayed paused")
