# frozen_string_literal: true

# This spec tests that ShoryukenConcurrentSendAdapter keeps CurrentAttributes
# set by the enqueuing code, though it sends the message on another thread.
# Every persisted class reaches the job, and the send thread does not keep
# them for the next send.
#
# It used to send every message without them: the message was built on the
# executor thread, where the attributes of the caller are not set.

setup_sqs
setup_active_job

require 'active_support/current_attributes'
require 'shoryuken/active_job/current_attributes'
require 'active_job/queue_adapters/shoryuken_concurrent_send_adapter'

class ConcurrentSendCurrent < ActiveSupport::CurrentAttributes
  attribute :user_id, :tenant_id
end

class ConcurrentSendContext < ActiveSupport::CurrentAttributes
  attribute :locale
end

Shoryuken::ActiveJob::CurrentAttributes.persist(ConcurrentSendCurrent, ConcurrentSendContext)

class ConcurrentSendContextJob < ActiveJob::Base
  def perform(label)
    DT[:executions] << {
      label: label,
      user_id: ConcurrentSendCurrent.user_id,
      tenant_id: ConcurrentSendCurrent.tenant_id,
      locale: ConcurrentSendContext.locale
    }
  end
end

class SendThreadRecorder
  def call(_options)
    DT[:send_threads] << Thread.current.object_id
    yield
  end
end

Shoryuken.client_middleware { |chain| chain.add(SendThreadRecorder) }

def enqueue_and_wait(adapter, label)
  ConcurrentSendContextJob.perform_later(label)
  assert(adapter.wait_for_pending_sends(10), "the #{label} send must finish")
end

# Sends run on Concurrent.global_io_executor; one thread makes a value kept from an earlier send visible
send_executor = Concurrent::FixedThreadPool.new(1)
Concurrent.define_singleton_method(:global_io_executor) { send_executor }

adapter = ActiveJob::QueueAdapters::ShoryukenConcurrentSendAdapter.new
ActiveJob::Base.queue_adapter = adapter

with_queue_name do |queue|
  create_test_queue(queue)
  ConcurrentSendContextJob.queue_as(queue)

  Shoryuken.add_group('default', 1)
  Shoryuken.add_queue(queue, 1, 'default')
  Shoryuken.register_worker(queue, Shoryuken::ActiveJob::JobWrapper)

  ConcurrentSendCurrent.user_id = 42
  ConcurrentSendCurrent.tenant_id = 'acme'
  ConcurrentSendContext.locale = 'pl'
  enqueue_and_wait(adapter, 'first')
  ConcurrentSendCurrent.reset
  ConcurrentSendContext.reset

  ConcurrentSendCurrent.user_id = 7
  ConcurrentSendCurrent.tenant_id = 'other'
  ConcurrentSendContextJob.perform_later('second')
  ConcurrentSendCurrent.user_id = 8
  ConcurrentSendCurrent.reset
  assert(adapter.wait_for_pending_sends(10), 'the second send must finish')

  enqueue_and_wait(adapter, 'none')

  refute(DT[:send_threads].include?(Thread.current.object_id), 'every send must run on another thread')
  assert_equal(1, DT[:send_threads].uniq.size, "all sends must run on one thread: #{DT[:send_threads]}")

  poll_queues_until(timeout: 30) { DT[:executions].size >= 3 }

  executions = DT[:executions].to_h { |execution| [execution[:label], execution.except(:label)] }
  assert_equal({ user_id: 42, tenant_id: 'acme', locale: 'pl' }, executions['first'])
  assert_equal({ user_id: 7, tenant_id: 'other', locale: nil }, executions['second'])
  assert_equal({ user_id: nil, tenant_id: nil, locale: nil }, executions['none'])
end
