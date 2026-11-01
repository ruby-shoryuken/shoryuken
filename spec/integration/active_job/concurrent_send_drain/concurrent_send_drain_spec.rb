# frozen_string_literal: true

# This spec tests that ShoryukenConcurrentSendAdapter lets callers drain
# in-flight asynchronous sends before the process exits.
#
# The concurrent adapter enqueues by scheduling the SQS send on a background
# future and returning immediately. Without a way to wait for those futures,
# jobs enqueued shortly before the process exits can be silently dropped - the
# send never runs.
#
# #wait_for_pending_sends blocks until every in-flight send has finished (so the
# job actually reaches SQS). With a timeout it returns false while a send is
# still running, and a failed send (reported to the error handler) counts as
# finished. A child forked while a send is in flight does not wait for the
# parent's send, which only the parent can complete.
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

# --- A timeout shorter than the send returns false, then the drain completes --
DT.clear

DrainTestJob.perform_later('timeout payload')

assert_equal(false, adapter.wait_for_pending_sends(0.1), 'a drain timing out before the send ends must return false')
assert(DT[:sent].empty?, 'the send should still be in-flight after the timed-out drain')
assert(adapter.wait_for_pending_sends(15), 'a later drain should still wait for the send to finish')
assert_equal(1, DT[:sent].size, 'the send should have completed during the second drain')

# --- A failed send is reported and counts as drained ------------------------
DT.clear

failing_adapter = ActiveJob::QueueAdapters::ShoryukenConcurrentSendAdapter.new(
  nil,
  ->(error, _job, _options) { DT[:errors] << error }
)
ActiveJob::Base.queue_adapter = failing_adapter

DrainTestJob.set(queue: "missing-#{DT.uuid}").perform_later('lost payload')

assert(failing_adapter.wait_for_pending_sends(15), 'a failed send must not block the drain')
assert_equal(1, DT[:errors].size, 'the failed send must reach the error handler')

# --- A forked child does not wait for the parent's in-flight send -----------
DT.clear
ActiveJob::Base.queue_adapter = adapter

DrainTestJob.perform_later('sent by the parent')

reader, writer = IO.pipe
child = fork do
  reader.close
  started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  drained = adapter.wait_for_pending_sends(5)
  writer.write("#{drained} #{Process.clock_gettime(Process::CLOCK_MONOTONIC) - started}")
  writer.close
  exit!(0)
end
writer.close
child_drained, child_elapsed = reader.read.split
Process.wait(child)

assert_equal('true', child_drained, "the forked child's drain must not report the parent's send as pending")
assert(child_elapsed.to_f < 1, "the forked child's drain must return at once, took #{child_elapsed}s")
assert(adapter.wait_for_pending_sends(15), "the parent's drain must still wait for its own send")
assert_equal(1, DT[:sent].size, "the parent's send should have completed during its drain")
