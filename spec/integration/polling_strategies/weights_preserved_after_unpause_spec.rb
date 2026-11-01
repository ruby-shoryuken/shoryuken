# frozen_string_literal: true

# This spec tests that WeightedRoundRobin keeps the grown weights of active
# queues when a paused FIFO queue is unpaused by a processed message.
#
# - A busy standard queue grows to its configured weight (3)
# - A FIFO queue pauses while its only message group is in flight
# - When that message is processed, the FIFO queue is unpaused and the busy
#   queue keeps weight 3
#
# It used to call uniq! on the active queues in message_processed, resetting
# every queue weight back to 1.
#
# Regression: #687

class RecordingWeightedRoundRobin < Shoryuken::Polling::WeightedRoundRobin
  def next_queue
    queue = super
    DT[:after_unpause] << active_queues if DT[:after_processed].any? && DT[:after_unpause].empty?
    queue
  end

  def message_processed(queue)
    super
    DT[:after_processed] << active_queues
  end
end

setup_sqs

busy_queue = DT.queue
fifo_queue = "#{DT.uuid}.fifo"

# Received messages become visible again at once, so the busy queue never runs dry
create_test_queue(busy_queue, attributes: { 'VisibilityTimeout' => '0' })
create_fifo_queue(fifo_queue)

# A long delay keeps the FIFO queue paused until message_processed unpauses it
Shoryuken.add_group('default', 5, delay: 30, polling_strategy: RecordingWeightedRoundRobin)
Shoryuken.add_queue(busy_queue, 3, 'default')
Shoryuken.add_queue(fifo_queue, 1, 'default')

class BusyWorker
  include Shoryuken::Worker

  shoryuken_options auto_delete: false, batch: false

  def perform(_sqs_msg, _body); end
end

class SlowFifoWorker
  include Shoryuken::Worker

  shoryuken_options auto_delete: true, batch: false

  def perform(_sqs_msg, body)
    sleep 2
    DT[:fifo_processed] << body
  end
end

Shoryuken.register_worker(busy_queue, BusyWorker)
Shoryuken.register_worker(fifo_queue, SlowFifoWorker)

5.times { |i| Shoryuken::Client.queues(busy_queue).send_message(message_body: "busy-#{i}") }

Shoryuken::Client.queues(fifo_queue).send_message(
  message_body: 'fifo-msg',
  message_group_id: 'group'
)

poll_queues_until(timeout: 20) { DT[:after_unpause].any? }

assert_equal(['fifo-msg'], DT[:fifo_processed])

after_processed = DT[:after_processed].first.to_h
assert_equal(3, after_processed[busy_queue], "Weight reset by message_processed: #{DT[:after_processed].first}")

after_unpause = DT[:after_unpause].first.to_h
assert_equal(3, after_unpause[busy_queue], "Weight lost after unpause: #{DT[:after_unpause].first}")
assert_equal(1, after_unpause[fifo_queue], "FIFO queue not unpaused: #{DT[:after_unpause].first}")
