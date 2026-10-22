# frozen_string_literal: true

# This spec tests enqueueing the same ActiveJob job instance twice, with new
# arguments, on a FIFO queue while CurrentAttributes are persisted.
#
# Expected behavior: the second enqueue sends a deduplication id of the current
# body, so both runs happen with their own arguments and current attributes.

setup_sqs
setup_active_job

require 'active_support/current_attributes'
require 'shoryuken/active_job/current_attributes'

queue_name = "#{DT.uuid}.fifo"
create_fifo_queue(queue_name)

class FifoReenqueueCurrent < ActiveSupport::CurrentAttributes
  attribute :user_id
end

Shoryuken::ActiveJob::CurrentAttributes.persist(FifoReenqueueCurrent)

class FifoReenqueueJob < ActiveJob::Base
  def perform(value)
    DT[:executions] << [value, FifoReenqueueCurrent.user_id]
  end
end

FifoReenqueueJob.queue_as(queue_name)

Shoryuken.add_group('default', 1)
Shoryuken.add_queue(queue_name, 1, 'default')
Shoryuken.register_worker(queue_name, Shoryuken::ActiveJob::JobWrapper)

FifoReenqueueCurrent.user_id = 'alice'
job = FifoReenqueueJob.new('first')
job.enqueue
job.arguments = ['second']
job.enqueue
FifoReenqueueCurrent.reset

poll_queues_until(timeout: 15) { DT[:executions].size >= 2 }

assert_equal([%w[first alice], %w[second alice]], DT[:executions])

delete_test_queue(queue_name)
