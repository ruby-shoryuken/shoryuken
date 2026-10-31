# frozen_string_literal: true

def expect_empty_queue_pause(batch:)
  queue = DT.queue
  create_test_queue(queue)

  delay = 2

  Shoryuken.options[:delay] = delay
  Shoryuken.add_group('default', 1)
  Shoryuken.add_queue(queue, 1, 'default')

  worker = Class.new do
    include Shoryuken::Worker

    shoryuken_options auto_delete: true, batch: batch

    def perform(_sqs_msg, _body); end
  end

  Shoryuken.register_worker(queue, worker)

  Shoryuken.on(:dispatch) do |event|
    DT[:polls] << Process.clock_gettime(Process::CLOCK_MONOTONIC) if event[:queue_name] == queue
  end

  poll_queues_until(timeout: 20) { DT[:polls].size >= 4 }

  gaps = DT[:polls].first(4).each_cons(2).map { |a, b| b - a }

  gaps.each do |gap|
    assert(gap >= delay, "Empty queue polled again after #{gap.round(2)}s, before the #{delay}s delay: #{gaps}")
    assert(gap < delay + 1, "Empty queue stayed paused for #{gap.round(2)}s, well past the #{delay}s delay: #{gaps}")
  end
end
