# frozen_string_literal: true

# This spec tests that WeightedRoundRobin, with all queues full, fetches from the
# queues in the order their weights (8, 4 and 1) give.
#
# - Every queue starts at weight 1, so the first round fetches each queue once
# - Each fetch that returns messages raises that queue's weight by one, up to
#   its configured weight
# - Once grown, each round fetches queue1 8 times, queue2 4 times and queue3 once

module FetchRecorder
  def fetch(queue, limit)
    DT[:fetches] << queue.name
    super
  end
end

Shoryuken::Fetcher.prepend(FetchRecorder)

setup_sqs

queue1 = DT.queues[0]
queue2 = DT.queues[1]
queue3 = DT.queues[2]

# Received messages become visible again at once, so the queues never run dry
[queue1, queue2, queue3].each { |q| create_test_queue(q, attributes: { 'VisibilityTimeout' => '0' }) }

Shoryuken.add_group('default', 10)
Shoryuken.add_queue(queue1, 8, 'default')
Shoryuken.add_queue(queue2, 4, 'default')
Shoryuken.add_queue(queue3, 1, 'default')

class FullQueueWorker
  include Shoryuken::Worker

  shoryuken_options auto_delete: false, batch: false

  def perform(_sqs_msg, _body); end
end

[queue1, queue2, queue3].each do |queue|
  Shoryuken.register_worker(queue, FullQueueWorker)
  10.times { |i| Shoryuken::Client.queues(queue).send_message(message_body: "msg-#{i}") }
end

names = { queue1 => 'queue1', queue2 => 'queue2', queue3 => 'queue3' }

expected = %w[
  queue1 queue2 queue3
  queue1 queue1 queue2 queue2 queue3
  queue1 queue1 queue1 queue1 queue2 queue2 queue2 queue2 queue3
  queue1 queue1 queue1 queue1 queue1 queue1 queue1 queue1 queue2 queue2 queue2 queue2 queue3
  queue1 queue1 queue1 queue1 queue1 queue1 queue1 queue1 queue2 queue2 queue2 queue2 queue3
]

poll_queues_until(timeout: 30) { DT[:fetches].size >= expected.size }

fetches = DT[:fetches].first(expected.size).map { |queue| names.fetch(queue) }

assert_equal(expected, fetches)
