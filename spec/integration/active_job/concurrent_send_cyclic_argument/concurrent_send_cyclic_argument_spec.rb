# frozen_string_literal: true

# This spec tests that ShoryukenConcurrentSendAdapter reports a send that
# raises an error which is not a StandardError. A job argument that refers to
# itself makes ActiveJob serialization raise SystemStackError on the send
# thread. The error handler gets the error, the returned future resolves and
# the adapter drains, and the next job is still sent.

require 'active_job/queue_adapters/shoryuken_concurrent_send_adapter'

setup_sqs
setup_active_job

DT.clear

class CyclicArgumentJob < ActiveJob::Base
  def perform(_payload)
    DT[:performed] << true
  end
end

error_handler = ->(error, _job, _options) { DT[:errors] << error }
adapter = ActiveJob::QueueAdapters::ShoryukenConcurrentSendAdapter.new(nil, error_handler)
ActiveJob::Base.queue_adapter = adapter

with_queue_name do |queue|
  create_test_queue(queue)
  CyclicArgumentJob.queue_as(queue)

  Shoryuken.add_group('default', 1)
  Shoryuken.add_queue(queue, 1, 'default')
  Shoryuken.register_worker(queue, Shoryuken::ActiveJob::JobWrapper)

  cyclic = {}
  cyclic['self'] = cyclic
  future = adapter.enqueue(CyclicArgumentJob.new(cyclic))

  assert(future.wait(10), 'the send of a cyclic argument must resolve')
  assert(adapter.wait_for_pending_sends(10), 'the adapter must drain after the failed send')
  assert_equal([SystemStackError], DT[:errors].map(&:class))

  CyclicArgumentJob.perform_later('plain')
  assert(adapter.wait_for_pending_sends(10), 'the next send must finish')

  poll_queues_until(timeout: 30) { DT[:performed].size >= 1 }

  assert_equal(1, DT[:performed].size)
  assert_equal(0, queue_size(queue))
end
