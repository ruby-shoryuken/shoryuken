# frozen_string_literal: true

# This spec tests ActiveJob adapter configuration including adapter type,
# Rails 7.2+ transaction commit hook, and singleton pattern.


ActiveJob::Base.queue_adapter = :shoryuken

class ConfigTestJob < ActiveJob::Base
  queue_as :config_test

  def perform(data)
    "Processed: #{data}"
  end
end

# Test adapter type identification
adapter = ActiveJob::Base.queue_adapter
assert_equal("ActiveJob::QueueAdapters::ShoryukenAdapter", adapter.class.name)

# Test Rails 7.2+ transaction commit hook support
adapter_instance = ActiveJob::QueueAdapters::ShoryukenAdapter.new
assert(adapter_instance.respond_to?(:enqueue_after_transaction_commit?))
assert_equal(true, adapter_instance.enqueue_after_transaction_commit?)

# Test singleton pattern
instance1 = ActiveJob::QueueAdapters::ShoryukenAdapter.instance
instance2 = ActiveJob::QueueAdapters::ShoryukenAdapter.instance
assert_equal(instance1.object_id, instance2.object_id)
assert(instance1.is_a?(ActiveJob::QueueAdapters::ShoryukenAdapter))
