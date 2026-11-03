# frozen_string_literal: true

# This spec tests that ShoryukenConcurrentSendAdapter keeps CurrentAttributes
# set by the enqueuing code, though it sends the message on another thread.
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

Shoryuken::ActiveJob::CurrentAttributes.persist(ConcurrentSendCurrent)

class ConcurrentSendContextJob < ActiveJob::Base
  def perform(label)
    DT[:executions] << {
      label: label,
      user_id: ConcurrentSendCurrent.user_id,
      tenant_id: ConcurrentSendCurrent.tenant_id
    }
  end
end

adapter = ActiveJob::QueueAdapters::ShoryukenConcurrentSendAdapter.new
ActiveJob::Base.queue_adapter = adapter

with_queue_name do |queue|
  create_test_queue(queue)
  ConcurrentSendContextJob.queue_as(queue)

  Shoryuken.add_group('default', 1)
  Shoryuken.add_queue(queue, 1, 'default')
  Shoryuken.register_worker(queue, Shoryuken::ActiveJob::JobWrapper)

  ConcurrentSendCurrent.set(user_id: 42, tenant_id: 'acme') do
    ConcurrentSendContextJob.perform_later('first')
  end

  ConcurrentSendCurrent.set(user_id: 7, tenant_id: 'other') do
    ConcurrentSendContextJob.perform_later('second')
    ConcurrentSendCurrent.user_id = 8
  end

  ConcurrentSendContextJob.perform_later('none')

  assert(adapter.wait_for_pending_sends(10), 'all sends must finish')

  poll_queues_until(timeout: 30) { DT[:executions].size >= 3 }

  executions = DT[:executions].to_h { |execution| [execution[:label], execution.except(:label)] }
  assert_equal({ user_id: 42, tenant_id: 'acme' }, executions['first'])
  assert_equal({ user_id: 7, tenant_id: 'other' }, executions['second'])
  assert_equal({ user_id: nil, tenant_id: nil }, executions['none'])
end
