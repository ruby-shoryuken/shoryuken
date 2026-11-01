# frozen_string_literal: true

# This spec tests that an empty queue whose worker uses `batch: true` is paused
# for the configured `delay` like a single-message queue.
#
# Expected behavior:
# - A batch poll that finds no messages pauses the queue for `delay` seconds
# - The queue is not polled again until the pause has passed
# - After the pause the queue is polled again, without waiting much longer
#
# Regression: #568 - empty queues were not paused in batch processing mode.

setup_sqs

queue = DT.queue
create_test_queue(queue)

delay = 2

Shoryuken.options[:delay] = delay
Shoryuken.add_group('default', 1)
Shoryuken.add_queue(queue, 1, 'default')

class EmptyBatchQueueWorker
  include Shoryuken::Worker

  shoryuken_options auto_delete: true, batch: true

  def perform(_sqs_msgs, _bodies); end
end

Shoryuken.register_worker(queue, EmptyBatchQueueWorker)

Shoryuken.on(:dispatch) do |event|
  DT[:polls] << Process.clock_gettime(Process::CLOCK_MONOTONIC) if event[:queue_name] == queue
end

poll_queues_until(timeout: 20) { DT[:polls].size >= 4 }

gaps = DT[:polls].first(4).each_cons(2).map { |a, b| b - a }

gaps.each do |gap|
  assert(gap >= delay, "Empty queue polled again after #{gap.round(2)}s, before the #{delay}s delay: #{gaps}")
  assert(gap < delay + 1, "Empty queue stayed paused for #{gap.round(2)}s, well past the #{delay}s delay: #{gaps}")
end
