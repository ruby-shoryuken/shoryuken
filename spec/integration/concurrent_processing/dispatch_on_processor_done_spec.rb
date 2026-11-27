# frozen_string_literal: true

# This spec tests that a processor that finishes gets its next message at once, not after MIN_DISPATCH_INTERVAL.
#
# It used to wait for the rest of a fixed 0.1 s sleep that the dispatch loop takes while every processor is busy,
# so one processor ran short jobs at about 10 messages per second.

setup_sqs

queue = DT.queue
create_test_queue(queue)

MESSAGES = 30

Shoryuken.options[:delay] = 0
Shoryuken.add_group('default', 1)
Shoryuken.add_queue(queue, 1, 'default')

class NoopWorker
  include Shoryuken::Worker

  shoryuken_options auto_delete: true, batch: false

  def perform(_sqs_msg, _body)
    DT[:processed] << Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end
end

Shoryuken.register_worker(queue, NoopWorker)

(MESSAGES / 10).times do |batch|
  Shoryuken::Client.queues(queue).send_messages(Array.new(10) { |i| "msg-#{batch}-#{i}" })
end

poll_queues_until(timeout: 20) { DT[:processed].size >= MESSAGES }

elapsed = DT[:processed].last - DT[:processed].first
fixed_sleeps = (MESSAGES - 1) * Shoryuken::Manager::MIN_DISPATCH_INTERVAL

assert_equal(MESSAGES, DT[:processed].size)
assert(
  elapsed < fixed_sleeps / 2,
  "#{MESSAGES} messages took #{elapsed.round(2)}s on one processor, close to #{fixed_sleeps.round(2)}s of dispatch sleeps"
)
