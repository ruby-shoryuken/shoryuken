# frozen_string_literal: true

# This spec tests that ShoryukenConcurrentSendAdapter lets callers drain
# in-flight asynchronous sends before the process exits.
#
# The concurrent adapter enqueues by scheduling the SQS send on a background
# future and returning immediately. Without a way to wait for those futures,
# jobs enqueued shortly before the process exits can be silently dropped - the
# send never runs.
#
# Expected behavior: #wait_for_pending_sends blocks until every in-flight send
# has finished (so the job actually reaches SQS), with an optional timeout.
#
# Regression: the adapter offered no drain, so in-flight sends could be lost.

require 'timeout'
require 'active_job/queue_adapters/shoryuken_concurrent_send_adapter'

setup_sqs
setup_active_job

DT.clear

queue_name = DT.queue
create_test_queue(queue_name)

# Slow the real SQS send so the async enqueue is provably still in-flight right
# after perform_later returns - i.e. it would be lost if the process exited now.
slow_send = Class.new do
  def call(_options)
    sleep 1
    yield
  ensure
    DT[:sent] << true
  end
end

Shoryuken.client_middleware { |chain| chain.add slow_send }

adapter = ActiveJob::QueueAdapters::ShoryukenConcurrentSendAdapter.new
ActiveJob::Base.queue_adapter = adapter

class DrainTestJob < ActiveJob::Base
  def perform(_payload); end
end

DrainTestJob.queue_as(queue_name)

DrainTestJob.perform_later('payload')

# The send runs asynchronously; immediately after enqueue it has not happened.
assert(DT[:sent].empty?, 'send should still be in-flight immediately after perform_later')

# Draining must block until the in-flight send completes.
assert(
  adapter.wait_for_pending_sends(15),
  'wait_for_pending_sends should report that all in-flight sends drained'
)
assert_equal(1, DT[:sent].size, 'the in-flight send should have completed during the drain')

# End-to-end: the drained job actually reached SQS.
queue_url = Shoryuken::Client.sqs.get_queue_url(queue_name: queue_name).queue_url
count = nil
Timeout.timeout(10) do
  loop do
    count = Shoryuken::Client.sqs.get_queue_attributes(
      queue_url: queue_url,
      attribute_names: ['ApproximateNumberOfMessages']
    ).attributes['ApproximateNumberOfMessages'].to_i
    break if count >= 1

    sleep 0.3
  end
end

assert_equal(1, count, 'the drained job should be present in SQS')
