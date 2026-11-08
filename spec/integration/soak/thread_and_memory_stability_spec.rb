# frozen_string_literal: true

# This spec tests that a long run of auto_visibility_timeout workers does not
# leak threads or memory. 500 messages are processed by 25 processors, and each
# perform runs past one visibility extension.
#
# Every extension timer thread ends with its perform, so after a warm-up of
# 100 messages the median thread count does not grow and RSS stays within a
# small bound. After the run at most a few timers or messages stay reachable,
# far fewer than a per-message leak would keep.
#
# Regression: #266 (an extender and its timer thread were kept for every
# processed message), #401 (the dispatch loop held a reference to every
# processor thread)

setup_sqs

DT.clear

MESSAGES = 500
WARM_UP = 100
CONCURRENCY = 25
# GC marks the machine stacks conservatively, so a stale stack slot can keep
# an object of the run alive; a leak keeps one per message
STALE_REFERENCES = 5

def median(values)
  values.sort[values.size / 2]
end

def rss_kb
  `ps -o rss= -p #{Process.pid}`.to_i
end

queue_name = DT.uuid
# Extensions run every 1.5s (half the 3s timeout)
create_test_queue(queue_name, attributes: { 'VisibilityTimeout' => '3' })
Shoryuken.add_group('default', CONCURRENCY)
Shoryuken.add_queue(queue_name, 1, 'default')

soak_worker = Class.new do
  include Shoryuken::Worker

  shoryuken_options auto_visibility_timeout: true, auto_delete: true

  def perform(sqs_msg, _body)
    sleep 1.7
    DT[:processed] << sqs_msg.message_id
  end
end

soak_worker.get_shoryuken_options['queue'] = queue_name
Shoryuken.register_worker(queue_name, soak_worker)

queue = Shoryuken::Client.queues(queue_name)
(1..MESSAGES).each_slice(10) do |slice|
  queue.send_messages(slice.map { |i| { message_body: "soak #{i}" } })
end

sampler = Thread.new do
  loop do
    DT[:samples] << { processed: DT[:processed].size, threads: Thread.list.size, rss: rss_kb }
    sleep 0.2
  end
end

poll_queues_until(timeout: 120) { DT[:processed].size >= MESSAGES }

sampler.kill

assert_equal(MESSAGES, DT[:processed].uniq.size, 'every message must be processed')
assert_equal(MESSAGES, DT[:processed].size, 'no message may be processed twice')

warm = DT[:samples].select { |s| s[:processed].between?(WARM_UP / 2, WARM_UP) }
late = DT[:samples].select { |s| s[:processed] >= MESSAGES - WARM_UP }

assert(warm.any? && late.any?, "samples must cover warm-up and the end, got #{DT[:samples].size}")

# A killed timer thread stays in Thread.list until it is scheduled again, so
# one sample can hold an outgoing and an incoming timer of the same processor
warm_threads = median(warm.map { |s| s[:threads] })
late_threads = median(late.map { |s| s[:threads] })
assert(
  late_threads <= warm_threads + 5,
  "thread count must stay flat after warm-up, grew from #{warm_threads} to #{late_threads}"
)

warm_rss = median(warm.map { |s| s[:rss] })
late_rss = median(late.map { |s| s[:rss] })
assert(
  late_rss - warm_rss < 15_000,
  "RSS must stay flat after warm-up, grew from #{warm_rss / 1024}MB to #{late_rss / 1024}MB"
)

GC.start
live_timers = ObjectSpace.each_object(Shoryuken::Helpers::TimerTask).count
live_messages = ObjectSpace.each_object(Shoryuken::Message).count
assert(live_timers <= STALE_REFERENCES, "extension timers of the run must not stay alive, got #{live_timers}")
assert(live_messages <= STALE_REFERENCES, "messages of the run must not stay alive, got #{live_messages}")

delete_test_queue(queue_name)
