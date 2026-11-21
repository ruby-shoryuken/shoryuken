# frozen_string_literal: true

# This spec tests that WeightedRoundRobin polls a paused FIFO queue again as
# soon as its in-flight message is processed, even when an earlier-paused
# queue is still paused ahead of it.
#
# - An empty standard queue is paused first for the 30s delay
# - A FIFO queue pauses next while its only message group is in flight
# - When that message is processed, the FIFO queue is polled again and its
#   second message is processed within seconds, not after the delay
#
# It used to unpause only the head of the paused list, so the FIFO queue
# stayed stuck behind the standard queue until the delay ended.
#
# Regression: #1015

class PauseRecordingWeightedRoundRobin < Shoryuken::Polling::WeightedRoundRobin
  def messages_found(queue, messages_found)
    DT[:paused] << queue if messages_found.zero?
    super
  end
end

setup_sqs

STANDARD_QUEUE = DT.queues[0]
FIFO_QUEUE = "#{DT.queues[1]}.fifo".freeze

create_test_queue(STANDARD_QUEUE)
create_fifo_queue(FIFO_QUEUE)

Shoryuken.add_group('default', 4, delay: 30, polling_strategy: PauseRecordingWeightedRoundRobin)
Shoryuken.add_queue(STANDARD_QUEUE, 1, 'default')
Shoryuken.add_queue(FIFO_QUEUE, 1, 'default')

class IdleWorker
  include Shoryuken::Worker

  shoryuken_options queue: STANDARD_QUEUE, auto_delete: true, batch: false

  def perform(_sqs_msg, _body); end
end

class SlowFifoWorker
  include Shoryuken::Worker

  shoryuken_options queue: FIFO_QUEUE, auto_delete: true, batch: false

  def perform(_sqs_msg, body)
    # Keeps the message group in flight so the next FIFO poll finds nothing
    sleep 1
    DT[:fifo_processed] << [body, Process.clock_gettime(Process::CLOCK_MONOTONIC)]
  end
end

%w[fifo-1 fifo-2].each do |body|
  Shoryuken::Client.queues(FIFO_QUEUE).send_message(
    message_body: body,
    message_group_id: 'group'
  )
end

poll_queues_until(timeout: 15) { DT[:fifo_processed].size >= 2 }

assert_equal([STANDARD_QUEUE, FIFO_QUEUE], DT[:paused].first(2), "Unexpected pause order: #{DT[:paused]}")
assert_equal(%w[fifo-1 fifo-2], DT[:fifo_processed].map(&:first))

gap = DT[:fifo_processed][1][1] - DT[:fifo_processed][0][1]
assert(gap < 5, "Second FIFO message processed #{gap.round(2)}s after the first, stuck behind the paused queue")
