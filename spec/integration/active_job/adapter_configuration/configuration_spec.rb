# frozen_string_literal: true

# This spec tests ActiveJob adapter configuration including adapter type,
# its AbstractAdapter base class with plain Active Job (no Rails),
# Rails 7.2+ transaction commit hook, and singleton pattern.

setup_active_job

class ConfigTestJob < ActiveJob::Base
  queue_as :config_test

  def perform(data)
    "Processed: #{data}"
  end
end

adapter = ActiveJob::Base.queue_adapter
assert_equal('ActiveJob::QueueAdapters::ShoryukenAdapter', adapter.class.name)

require 'active_job/queue_adapters/shoryuken_concurrent_send_adapter'
refute(defined?(Rails))
assert_equal(ActiveJob::QueueAdapters::AbstractAdapter, ActiveJob::QueueAdapters::ShoryukenAdapter.superclass)
assert(ActiveJob::QueueAdapters::ShoryukenConcurrentSendAdapter < ActiveJob::QueueAdapters::AbstractAdapter)

adapter_instance = ActiveJob::QueueAdapters::ShoryukenAdapter.new
assert(adapter_instance.respond_to?(:enqueue_after_transaction_commit?))
assert_equal(true, adapter_instance.enqueue_after_transaction_commit?)

instance1 = ActiveJob::QueueAdapters::ShoryukenAdapter.instance
instance2 = ActiveJob::QueueAdapters::ShoryukenAdapter.instance
assert_equal(instance1.object_id, instance2.object_id)
assert(instance1.is_a?(ActiveJob::QueueAdapters::ShoryukenAdapter))
