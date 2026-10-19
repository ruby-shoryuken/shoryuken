# frozen_string_literal: true

# This spec tests how the fetcher retries failed SQS receives: an incremental,
# bounded backoff (1s, 2s, 3s) instead of a random sleep.
#
# Fetcher#fetch_with_auto_retry used to sleep a random 1-5s between attempts on
# the dispatch thread, so recovery from a transient receive failure took an
# unpredictable time, and a persistent failure kept the manager retrying for up
# to 15s before it stopped.
#
# Expected behavior: a transient failure is retried after 1s, then 2s, and the
# message is then processed; a persistent failure stops the manager after three
# retries (1s + 2s + 3s), so Launcher#healthy? reports it.
#
# Regression: retries waited a random 1-5s each.

require 'timeout'

setup_sqs

# Fails the first `failures` receive calls (like a transient SQS outage) and
# records when each receive was attempted.
module FailingReceive
  class << self
    attr_accessor :failures
  end

  def receive_messages(options)
    DT[:receive_calls] << Time.now

    if DT[:receive_calls].size <= FailingReceive.failures
      raise Seahorse::Client::NetworkingError, StandardError.new('connection reset')
    end

    super
  end
end

Shoryuken::Queue.prepend(FailingReceive)

def start_launcher(queue_name, worker)
  Shoryuken.groups.clear
  Shoryuken.add_group('default', 1)
  Shoryuken.add_queue(queue_name, 1, 'default')
  worker.get_shoryuken_options['queue'] = queue_name
  Shoryuken.register_worker(queue_name, worker)

  executor = Concurrent::CachedThreadPool.new(auto_terminate: true)
  Shoryuken.define_singleton_method(:launcher_executor) { executor }

  launcher = Shoryuken::Launcher.new
  launcher.start
  launcher
end

worker = Class.new do
  include Shoryuken::Worker

  shoryuken_options auto_delete: true

  def perform(_sqs_msg, body)
    DT[:processed] << body
  end
end

# --- A transient failure is retried with a 1s, then 2s backoff --------------
DT.clear
FailingReceive.failures = 2

queue_name = DT.uuid
create_test_queue(queue_name)
Shoryuken::Client.queues(queue_name).send_message(message_body: 'after transient failure')

launcher = start_launcher(queue_name, worker)
Timeout.timeout(15) { sleep 0.1 until DT[:processed].any? }
launcher.stop

assert_equal(['after transient failure'], DT[:processed])

calls = DT[:receive_calls]
first_gap = calls[1] - calls[0]
second_gap = calls[2] - calls[1]
assert(first_gap.between?(0.9, 1.5), "the first retry must wait about 1s, waited #{first_gap.round(2)}s")
assert(second_gap.between?(1.9, 2.5), "the second retry must wait about 2s, waited #{second_gap.round(2)}s")

delete_test_queue(queue_name)

# --- A persistent failure stops the manager after a bounded time ------------
DT.clear
FailingReceive.failures = Float::INFINITY

queue_name = DT.uuid
create_test_queue(queue_name)

launcher = start_launcher(queue_name, worker)
started_at = Time.now
Timeout.timeout(15) { sleep 0.1 while launcher.healthy? }
elapsed = Time.now - started_at
launcher.stop!

assert_equal(4, DT[:receive_calls].size, 'a persistent failure must be tried once and retried three times')
assert(elapsed.between?(5.5, 7.5), "the manager must stop after 1s + 2s + 3s of backoff, took #{elapsed.round(2)}s")

delete_test_queue(queue_name)
